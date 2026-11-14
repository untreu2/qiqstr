package me.untreu.qiqstr.ui.dm

import android.util.Base64
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.qiqstr.core.createBlossomAuthEvent
import com.qiqstr.core.dbQueryEvents
import com.qiqstr.core.dbSearchProfiles
import com.qiqstr.core.fetchEvents
import com.qiqstr.core.fetchEventsFromRelays
import com.qiqstr.core.getConnectedRelayCount
import com.qiqstr.core.sendEvent
import com.qiqstr.core.sendEventTo
import com.qiqstr.core.sha256Hash
import com.qiqstr.core.subscribeToEvents
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.takeWhile
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.strings
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.bridge.EventStream
import me.untreu.qiqstr.data.services.RelayConfig
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.NotificationBadge
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Profile
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

@Immutable
data class DMFileInfo(
    val url: String,
    val mimeType: String,
    val groupId: String,
    val imeta: List<String>,
    val originalHash: String?,
    val filename: String,
    val size: Int?,
) {
    val isEncrypted: Boolean get() = originalHash != null && imeta.any { it.startsWith("n ") }
    val isImage: Boolean get() = mimeType.lowercase().startsWith("image/")
    val isVideo: Boolean get() = mimeType.lowercase().startsWith("video/")
    val fileExtension: String get() = DMMediaCrypto.fileExtension(mimeType)
    val imetaWithoutURL: List<String> get() = imeta.filter { !it.startsWith("url ") }

    fun toJson(): JSONObject = JSONObject()
        .put("url", url).put("mimeType", mimeType).put("groupId", groupId).put("imeta", JSONArray(imeta))
        .put("originalHash", originalHash ?: JSONObject.NULL).put("filename", filename).put("size", size ?: JSONObject.NULL)

    companion object {
        fun fromImeta(values: List<String>, groupId: String): DMFileInfo? {
            val fields = HashMap<String, String>()
            for (value in values) {
                val space = value.indexOf(' ')
                if (space < 0) continue
                val key = value.substring(0, space)
                if (!fields.containsKey(key)) fields[key] = value.substring(space + 1)
            }
            val url = fields["url"]?.ifEmpty { null } ?: return null
            val mime = fields["m"] ?: return null
            return DMFileInfo(url, mime, groupId, values, fields["x"]?.lowercase(), fields["filename"] ?: "", fields["size"]?.toIntOrNull())
        }

        fun fromJson(j: JSONObject): DMFileInfo? {
            val url = j.str("url") ?: return null
            return DMFileInfo(url, j.text("mimeType"), j.text("groupId"), j.strings("imeta"), j.str("originalHash"), j.text("filename"), if (j.isNull("size")) null else j.int("size"))
        }
    }
}

enum class DMDeliveryState { SENT, SENDING, FAILED }

enum class DMPeerStatus { UNKNOWN, CHECKING, READY, UNAVAILABLE }

@Immutable
data class DMMessage(
    val id: String,
    val sender: String,
    val peer: String,
    val content: String,
    val createdAt: Long,
    val isMine: Boolean,
    val kind: Int,
    val file: DMFileInfo? = null,
    val state: DMDeliveryState = DMDeliveryState.SENT,
) {
    val isFile: Boolean get() = kind == 15

    fun toJson(): JSONObject = JSONObject()
        .put("id", id).put("sender", sender).put("peer", peer).put("content", content).put("createdAt", createdAt)
        .put("isMine", isMine).put("kind", kind).put("file", file?.toJson() ?: JSONObject.NULL).put("state", state.name.lowercase())

    companion object {
        fun fromJson(j: JSONObject): DMMessage? {
            val id = j.str("id") ?: return null
            val sender = j.str("sender") ?: return null
            val peer = j.str("peer") ?: return null
            val state = DMDeliveryState.entries.firstOrNull { it.name.lowercase() == j.text("state") } ?: DMDeliveryState.SENT
            return DMMessage(id, sender, peer, j.text("content"), j.long("createdAt"), j.optBoolean("isMine"), j.int("kind"), j.optJSONObject("file")?.let(DMFileInfo::fromJson), state)
        }

        fun fromMarmot(j: JSONObject, me: String, peer: String): List<DMMessage> {
            val id = j.str("id") ?: return emptyList()
            val sender = j.str("pubkey") ?: return emptyList()
            val groupId = j.str("groupId") ?: return emptyList()
            if (j.int("kind") != 9) return emptyList()
            val state = j.text("state")
            if (state == "deleted" || state == "epoch_invalidated") return emptyList()
            val createdAt = j.long("createdAt")
            val isMine = sender == me
            val content = j.text("content")
            val media = j.tags().filter { it.firstOrNull() == "imeta" }.mapNotNull { DMFileInfo.fromImeta(it.drop(1), groupId) }
            val hasText = content.isNotBlank()
            val messages = mutableListOf<DMMessage>()
            if (hasText) messages.add(DMMessage(id, sender, peer, content, createdAt, isMine, 14))
            media.forEachIndexed { index, file ->
                val messageId = if (!hasText && index == 0) id else "$id:$index"
                messages.add(DMMessage(messageId, sender, peer, file.url, createdAt, isMine, 15, file))
            }
            return messages
        }
    }
}

@Immutable
data class DMConversation(val peer: String, val lastMessage: DMMessage, val isUnread: Boolean) {
    val id: String get() = peer
    val timestamp: Long get() = lastMessage.createdAt
}

@Immutable
data class DMPreparedFile(
    val url: String,
    val mimeType: String,
    val groupId: String,
    val imeta: List<String>,
    val originalHash: String,
    val filename: String,
    val size: Int,
) {
    val tag: List<String> get() = listOf("imeta", "url $url") + imeta
}

private class CachedKeyPackage(val event: String?, val fetchedAt: Long)

object DMService {
    const val MAX_FILE_SIZE = 50 * 1024 * 1024
    private const val MESSAGE_KIND = 9
    private const val HISTORY_LIMIT = 500
    private const val HISTORY_PAGE = 200
    private const val UNPROCESSED_LIMIT = 300
    private const val KEY_PACKAGE_REFRESH = 7 * 86_400L
    private const val KEY_ROTATION_AGE = 30 * 86_400L
    private const val GIFT_WRAP_JITTER = 3 * 86_400L

    var conversations by mutableStateOf<List<DMConversation>>(emptyList())
        private set
    var messagesByPeer by mutableStateOf<Map<String, List<DMMessage>>>(emptyMap())
        private set
    var following by mutableStateOf<Set<String>>(emptySet())
        private set
    var isLoading by mutableStateOf(false)
        private set
    var hasLoaded by mutableStateOf(false)
        private set
    var isRefreshing by mutableStateOf(false)
        private set
    var peerStatus by mutableStateOf<Map<String, DMPeerStatus>>(emptyMap())
        private set
    var deliveryRelays by mutableStateOf<Map<String, List<String>>>(emptyMap())
        private set
    var accepted by mutableStateOf<Set<String>>(emptySet())
        private set
    var historyComplete by mutableStateOf<Set<String>>(emptySet())
        private set
    var loadingOlder by mutableStateOf<Set<String>>(emptySet())
        private set

    private var activePeerState by mutableStateOf<String?>(null)
    var activePeer: String?
        get() = activePeerState
        set(value) {
            activePeerState = value
            if (value != null) markRead(value)
        }

    private var listVisibleState by mutableStateOf(false)
    var isListVisible: Boolean
        get() = listVisibleState
        set(value) {
            listVisibleState = value
            if (value) markTabSeen()
        }

    private var generation = 0
    private var me: String? = null
    private var privateKey: String? = null
    private var groups = HashMap<String, MarmotGroup>()
    private val seenEvents = HashSet<String>()
    private var hiddenIds = LinkedHashSet<String>()
    private var clearedAt = HashMap<String, Long>()
    private var welcomeTask: Job? = null
    private var groupTask: Job? = null
    private var subscribedGroups: Set<String> = emptySet()
    private var startTask: Job? = null
    private val chatCreation = HashMap<String, Deferred<String>>()
    private val keyPackages = HashMap<String, CachedKeyPackage>()
    private val inboxRelayCache = HashMap<String, List<String>>()
    private var remoteRelaysFetchedAt = 0L
    private var readMarks = HashMap<String, Long>()
    private var readBaseline = 0L
    private var tabSeenAt = 0L
    private val verifiedMedia = HashSet<String>()
    private val mediaTasks = HashMap<String, Deferred<File>>()
    private val unprocessed = HashMap<String, String>()
    private val unprocessedOrder = ArrayList<String>()
    private val historyLoaded = HashMap<String, Int>()
    private var outboxReady = false

    fun reset() {
        generation += 1
        welcomeTask?.cancel()
        welcomeTask = null
        groupTask?.cancel()
        groupTask = null
        subscribedGroups = emptySet()
        startTask?.cancel()
        startTask = null
        chatCreation.values.forEach { it.cancel() }
        chatCreation.clear()
        me = null
        privateKey = null
        groups = HashMap()
        seenEvents.clear()
        hiddenIds = LinkedHashSet()
        clearedAt = HashMap()
        keyPackages.clear()
        inboxRelayCache.clear()
        remoteRelaysFetchedAt = 0L
        readMarks = HashMap()
        readBaseline = 0
        tabSeenAt = 0
        verifiedMedia.clear()
        mediaTasks.values.forEach { it.cancel() }
        mediaTasks.clear()
        deliveryRelays = emptyMap()
        accepted = emptySet()
        historyComplete = emptySet()
        loadingOlder = emptySet()
        unprocessed.clear()
        unprocessedOrder.clear()
        historyLoaded.clear()
        outboxReady = false
        peerStatus = emptyMap()
        conversations = emptyList()
        messagesByPeer = emptyMap()
        following = emptySet()
        isLoading = false
        hasLoaded = false
        isRefreshing = false
        activePeerState = null
        listVisibleState = false
        NotificationBadge.hasUnreadMessages = false
    }

    suspend fun start() {
        val me = Session.pubkey ?: return
        val key = Session.privateKey
        if (key == null) {
            isLoading = false
            hasLoaded = true
            return
        }
        val running = startTask
        if (this.me == me && running != null) {
            running.join()
            return
        }
        if (this.me != null && this.me != me) reset()
        this.me = me
        privateKey = key
        val generation = this.generation
        loadReadState(me)
        hiddenIds = LinkedHashSet(Prefs.stringList(storeKey("marmot_hidden", me)).orEmpty())
        clearedAt = loadLongMap(storeKey("cleared", me))
        accepted = Prefs.stringList(storeKey("accepted", me)).orEmpty().toSet()
        isLoading = true
        val task = App.scope.launch { performStart(me, key, generation) }
        startTask = task
        task.join()
    }

    private suspend fun performStart(me: String, key: String, generation: Int) {
        val opened = coroutineScope {
            val followingLoaded = launch { reloadFollowing() }
            val opened = runCatching { MarmotEngine.open(key) }.getOrNull() == me
            followingLoaded.join()
            opened
        }
        if (generation != this.generation) return
        if (!opened) {
            isLoading = false
            hasLoaded = true
            return
        }
        reloadGroups(loadingAll = true, generation = generation)
        if (generation != this.generation) return
        loadOutbox(me)
        startRealtime(generation)
        fetchFromRelays(initial = true, generation = generation)
        if (generation != this.generation) return
        isLoading = false
        hasLoaded = true
        publishKeyPackageIfNeeded(me, generation)
        retryPendingWelcomes(generation)
        rotateKeys(generation)
    }

    suspend fun refresh() {
        if (me == null) { start(); return }
        if (isRefreshing) return
        isRefreshing = true
        try {
            val generation = this.generation
            fetchFromRelays(initial = false, generation = generation)
            if (generation != this.generation) return
            if (welcomeTask == null) startRealtime(generation)
            retryPendingWelcomes(generation)
        } finally {
            isRefreshing = false
        }
    }

    suspend fun incomingMessages(since: Long): List<DMMessage> {
        if (hasLoaded && me == Session.pubkey) refresh() else start()
        val blocked = Session.mutedPubkeys.toSet()
        return messagesByPeer.values.flatten().filter {
            !it.isMine && it.state == DMDeliveryState.SENT && it.createdAt > since && it.peer !in blocked && isKnown(it.peer)
        }
    }

    fun deleteConversation(peer: String) {
        val me = me ?: return
        val latest = messagesByPeer[peer]?.maxOfOrNull { it.createdAt } ?: 0
        clearedAt[peer] = maxOf(latest, TimeFormat.now, clearedAt[peer] ?: 0)
        saveLongMap(storeKey("cleared", me), clearedAt)
        messagesByPeer = messagesByPeer - peer
        saveOutbox()
        rebuildConversations()
        DataBus.dmChanged()
    }

    fun accept(peer: String) {
        val me = me ?: return
        if (peer in accepted) return
        accepted = accepted + peer
        Prefs.setStringList(storeKey("accepted", me), accepted.toList())
        rebuildConversations()
        DataBus.dmChanged()
    }

    fun isRequest(peer: String): Boolean = !isKnown(peer) && (messagesByPeer[peer]?.any { !it.isMine } ?: false)

    fun canLoadOlder(peer: String): Boolean {
        val me = me ?: return false
        return groups.values.any { group ->
            group.peer(me) == peer && (historyLoaded[group.id] ?: 0) >= HISTORY_LIMIT && group.id !in historyComplete
        }
    }

    suspend fun loadOlder(peer: String) {
        val me = me ?: return
        if (peer in loadingOlder) return
        loadingOlder = loadingOlder + peer
        try {
            val generation = this.generation
            val loaded = mutableListOf<DMMessage>()
            for (group in groups.values.toList()) {
                if (group.peer(me) != peer || group.id in historyComplete) continue
                val offset = historyLoaded[group.id] ?: 0
                val raw = runCatching { MarmotEngine.messages(group.id, HISTORY_PAGE, offset) }.getOrNull() ?: continue
                if (generation != this.generation) return
                val page = Json.array(raw)
                historyLoaded[group.id] = offset + page.size
                if (page.size < HISTORY_PAGE) historyComplete = historyComplete + group.id
                loaded += page.reversed().flatMap { DMMessage.fromMarmot(it, me, peer) }
            }
            apply(loaded.sortedBy { it.createdAt })
        } finally {
            loadingOlder = loadingOlder - peer
        }
    }

    fun mutesChanged() {
        if (me == null) return
        rebuildConversations()
        DataBus.dmChanged()
    }

    suspend fun reloadFollowing() {
        val me = me ?: Session.pubkey ?: return
        val list = SyncService.followingList(me).toSet()
        if (list != following) following = list
    }

    fun messages(peer: String): List<DMMessage> = messagesByPeer[peer].orEmpty()

    fun conversation(peer: String): DMConversation? = conversations.firstOrNull { it.peer == peer }

    fun isFollowing(pubkey: String): Boolean = pubkey in following

    fun isKnown(peer: String): Boolean =
        peer in following || peer in accepted || (messagesByPeer[peer]?.any { it.isMine } ?: false)

    val unreadCount: Int get() = conversations.count { it.isUnread }

    val currentPubkey: String? get() = me

    fun errorMessage(error: Throwable): String = coreErrorMessage(error)

    fun status(peer: String): DMPeerStatus {
        val known = peerStatus[peer]
        if (preferredGroup(peer) != null) return DMPeerStatus.READY
        return known ?: DMPeerStatus.UNKNOWN
    }

    fun chatRelays(peer: String): List<String> {
        val relays = mutableListOf<String>()
        for (group in groups.values) {
            if (group.peer(me ?: "") != peer) continue
            for (relay in group.relays) if (relay !in relays) relays.add(relay)
        }
        return relays
    }

    suspend fun checkPeer(peer: String) {
        if (preferredGroup(peer) != null || peerStatus[peer] == DMPeerStatus.CHECKING) return
        peerStatus = peerStatus + (peer to DMPeerStatus.CHECKING)
        val found = keyPackage(peer, fresh = false) != null
        if (me == null) return
        peerStatus = peerStatus + (peer to if (preferredGroup(peer) != null || found) DMPeerStatus.READY else DMPeerStatus.UNAVAILABLE)
    }

    private fun storeKey(name: String, me: String) = "dm_${name}_$me"

    private suspend fun reloadGroups(loadingAll: Boolean, generation: Int) {
        val me = me ?: return
        val list = runCatching { MarmotEngine.groups() }.getOrNull() ?: return
        if (generation != this.generation) return
        val active = HashMap<String, MarmotGroup>()
        for (group in list) if (group.isActive && group.peer(me) != null) active[group.id] = group
        val previous = groups.keys.toSet()
        groups = active
        val targets = if (loadingAll) active.keys.toList() else active.keys.filter { it !in previous }
        val loaded = mutableListOf<DMMessage>()
        for (id in targets) {
            val group = active[id] ?: continue
            val peer = group.peer(me) ?: continue
            val raw = runCatching { MarmotEngine.messages(id, HISTORY_LIMIT) }.getOrNull() ?: continue
            val page = Json.array(raw)
            historyLoaded[id] = page.size
            historyComplete = if (page.size < HISTORY_LIMIT) historyComplete + id else historyComplete - id
            loaded += page.reversed().flatMap { DMMessage.fromMarmot(it, me, peer) }
        }
        if (generation != this.generation) return
        val ordered = loaded.withIndex()
            .sortedWith { lhs, rhs ->
                when {
                    lhs.value.createdAt != rhs.value.createdAt -> lhs.value.createdAt.compareTo(rhs.value.createdAt)
                    lhs.value.isMine != rhs.value.isMine -> if (lhs.value.isMine) -1 else 1
                    else -> lhs.index.compareTo(rhs.index)
                }
            }
            .map { it.value }
        apply(ordered)
        val statuses = peerStatus.toMutableMap()
        for (group in active.values) {
            val peer = group.peer(me) ?: continue
            if (statuses[peer] != DMPeerStatus.READY) statuses[peer] = DMPeerStatus.READY
        }
        if (statuses != peerStatus) peerStatus = statuses
        if (active.values.map { it.nostrGroupId }.toSet() != subscribedGroups) startGroupRealtime(generation)
    }

    private suspend fun fetchFromRelays(initial: Boolean, generation: Int) {
        val me = me ?: return
        val cursor = Prefs.long(storeKey("marmot_cursor", me))
        val startedAt = TimeFormat.now
        val reachable = runCatching { getConnectedRelayCount() }.getOrDefault(0u) > 0u
        val wrapFilter = mutableMapOf<String, Any>("kinds" to listOf(1059), "#p" to listOf(me), "limit" to if (initial) 500 else 200)
        if (cursor > 0) wrapFilter["since"] = cursor - GIFT_WRAP_JITTER
        val wraps = rawArray(runCatching { fetchEvents(Json.string(wrapFilter), (if (initial) 10 else 8).toUInt()) }.getOrNull())
        if (generation != this.generation) return
        ingest(wraps, generation)
        if (generation != this.generation) return
        fetchGroupMessages(if (cursor > 0) cursor - 600 else null, generation)
        if (generation != this.generation || !reachable) return
        Prefs.set(storeKey("marmot_cursor", me), startedAt)
    }

    private suspend fun fetchGroupMessages(since: Long?, generation: Int) {
        val list = groups.values.toList()
        if (list.isEmpty()) return
        val filter = mutableMapOf<String, Any>("kinds" to listOf(445), "#h" to list.map { it.nostrGroupId }, "limit" to 1000)
        if (since != null) filter["since"] = since
        val json = Json.string(filter)
        val main = RelayConfig.mainRelays.toSet()
        val remote = (list.flatMap { it.relays }.toSet() - main).toList()
        val fetchRemote = remote.isNotEmpty() && System.currentTimeMillis() - remoteRelaysFetchedAt > 45_000
        if (fetchRemote) remoteRelaysFetchedAt = System.currentTimeMillis()
        val merged = coroutineScope {
            val pooled = async { runCatching { fetchEvents(json, 8u) }.getOrNull() }
            val extra = async { if (fetchRemote) runCatching { fetchEventsFromRelays(json, remote, 8u) }.getOrNull() else null }
            rawArray(pooled.await()) + rawArray(extra.await())
        }
        if (generation != this.generation) return
        ingest(merged, generation)
    }

    private fun startRealtime(generation: Int) {
        welcomeTask?.cancel()
        welcomeTask = App.scope.launch {
            val me = me ?: return@launch
            val filter = Json.string(mapOf("kinds" to listOf(1059), "#p" to listOf(me), "since" to TimeFormat.now - GIFT_WRAP_JITTER))
            listen(filter, generation)
        }
        startGroupRealtime(generation)
    }

    private fun startGroupRealtime(generation: Int) {
        groupTask?.cancel()
        val ids = groups.values.map { it.nostrGroupId }.toSet()
        subscribedGroups = ids
        if (ids.isEmpty()) {
            groupTask = null
            return
        }
        val filter = Json.string(mapOf("kinds" to listOf(445), "#h" to ids.toList(), "since" to TimeFormat.now - 60))
        groupTask = App.scope.launch { listen(filter, generation) }
    }

    private suspend fun listen(filter: String, generation: Int) {
        while (currentCoroutineContext().isActive && generation == this.generation) {
            try {
                EventStream.make { sink -> subscribeToEvents(filter, sink) }
                    .takeWhile { generation == this.generation }
                    .collect { raw -> ingest(listOf(raw), generation) }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
            }
            if (!currentCoroutineContext().isActive || generation != this.generation) break
            delay(5_000)
        }
    }

    private suspend fun ingest(raws: List<String>, generation: Int, depth: Int = 0) {
        if (seenEvents.size > 20_000) seenEvents.clear()
        val groupEvents = HashMap<String, String>()
        val fresh = raws.filter { raw ->
            val event = Json.obj(raw) ?: return@filter false
            val id = event.str("id") ?: return@filter false
            if (id in seenEvents) return@filter false
            seenEvents.add(id)
            if (event.int("kind") == 445) groupEvents[id] = raw
            true
        }
        if (fresh.isEmpty()) return
        val outcomes = MarmotEngine.process(fresh)
        if (generation != this.generation) return
        val me = me ?: return
        var groupsChanged = false
        var joined = false
        val incoming = mutableListOf<DMMessage>()
        val retry = mutableListOf<String>()
        for (outcome in outcomes) {
            groupEvents[outcome.eventId]?.let { raw ->
                if (outcome.type == "ignored" || outcome.type == "error") holdUnprocessed(outcome.eventId, raw) else unprocessed.remove(outcome.eventId)
            }
            when (outcome.type) {
                "message" -> {
                    val peer = outcome.groupId?.let { groups[it] }?.peer(me)
                    if (peer == null) {
                        groupsChanged = true
                        continue
                    }
                    Json.obj(outcome.messageJSON)?.let { incoming += DMMessage.fromMarmot(it, me, peer) }
                }
                "welcome" -> {
                    groupsChanged = true
                    if (outcome.isNewWelcome) joined = true
                }
                "proposal" -> {
                    groupsChanged = true
                    val groupId = outcome.groupId
                    val commit = outcome.evolutionEvent
                    if (groupId != null && commit != null) {
                        val relays = relays(groupId)
                        MarmotEngine.finishCommit(groupId, commit) { event -> !publish(event, relays).isNullOrEmpty() }
                    }
                }
                "commit" -> {
                    groupsChanged = true
                    retry += outcome.retry
                }
            }
        }
        apply(incoming)
        if (groupsChanged) reloadGroups(loadingAll = false, generation = generation)
        if (retry.isNotEmpty() && depth < 4) reprocess(retry.toSet(), generation, depth + 1)
        if (joined) {
            Prefs.remove(storeKey("marmot_kp_at", me))
            fetchGroupMessages(null, generation)
            rotateKeys(generation)
            publishKeyPackageIfNeeded(me, generation)
        }
    }

    private fun holdUnprocessed(id: String, raw: String) {
        if (unprocessed.containsKey(id)) return
        unprocessed[id] = raw
        unprocessedOrder.add(id)
        while (unprocessedOrder.size > UNPROCESSED_LIMIT) unprocessed.remove(unprocessedOrder.removeAt(0))
    }

    private suspend fun reprocess(ids: Set<String>, generation: Int, depth: Int) {
        val raws = ids.mapNotNull { unprocessed[it] }.toMutableList()
        val missing = (ids - unprocessed.keys).toList()
        if (missing.isNotEmpty()) {
            val filter = Json.string(mapOf("ids" to missing, "limit" to missing.size))
            val relays = groups.values.flatMap { it.relays }.toSet().toList()
            val fetched = coroutineScope {
                val pooled = async { runCatching { fetchEvents(filter, 6u) }.getOrNull() }
                val extra = async { if (relays.isEmpty()) null else runCatching { fetchEventsFromRelays(filter, relays, 6u) }.getOrNull() }
                rawArray(pooled.await()) + rawArray(extra.await())
            }
            raws += fetched.filter { raw -> Json.obj(raw)?.str("id")?.let { it in ids } ?: false }
        }
        if (generation != this.generation || raws.isEmpty()) return
        for (id in ids) {
            seenEvents.remove(id)
            unprocessed.remove(id)
        }
        unprocessedOrder.removeAll { it in ids }
        ingest(raws, generation, depth)
    }

    private fun apply(messages: List<DMMessage>) {
        val visible = messages.filter { it.id !in hiddenIds }
        if (visible.isEmpty()) return
        val work = HashMap<String, MutableList<DMMessage>>()
        val changedPeers = HashSet<String>()
        for (message in visible) if (insert(message, work)) changedPeers.add(message.peer)
        if (changedPeers.isEmpty()) return
        commit(work)
        activePeerState?.let { if (it in changedPeers) markReadSilently(it) }
        rebuildConversations()
        val missing = changedPeers.filter { ProfileCache.profile(it) == null }
        if (missing.isNotEmpty()) App.scope.launch { ProfileCache.load(missing) }
        DataBus.dmChanged()
    }

    private fun commit(work: Map<String, MutableList<DMMessage>>) {
        if (work.isEmpty()) return
        val next = messagesByPeer.toMutableMap()
        for ((peer, list) in work) next[peer] = list.toList()
        messagesByPeer = next
    }

    private fun insert(message: DMMessage, work: HashMap<String, MutableList<DMMessage>>): Boolean {
        clearedAt[message.peer]?.let { if (message.createdAt <= it) return false }
        val list = work[message.peer] ?: messagesByPeer[message.peer].orEmpty().toMutableList()
        val existing = list.indexOfFirst { it.id == message.id }
        if (existing >= 0) {
            if (list[existing].state == DMDeliveryState.SENT) return false
            list[existing] = message
            work[message.peer] = list
            return true
        }
        val index = list.indexOfLast { it.createdAt <= message.createdAt } + 1
        list.add(index, message)
        work[message.peer] = list
        return true
    }

    private fun insert(message: DMMessage): Boolean {
        val work = HashMap<String, MutableList<DMMessage>>()
        val inserted = insert(message, work)
        commit(work)
        return inserted
    }

    private fun updateList(peer: String, change: (MutableList<DMMessage>) -> Unit) {
        val list = messagesByPeer[peer]?.toMutableList() ?: return
        change(list)
        messagesByPeer = if (list.isEmpty()) messagesByPeer - peer else messagesByPeer + (peer to list.toList())
    }

    private fun preferredGroup(peer: String): MarmotGroup? {
        val me = me ?: return null
        return groups.values.filter { it.peer(me) == peer }.maxWithOrNull(compareBy<MarmotGroup>({ it.lastMessageAt }, { it.id }))
    }

    private fun rebuildConversations() {
        val blocked = Session.mutedPubkeys.toSet()
        conversations = messagesByPeer.mapNotNull { (peer, list) ->
            if (peer in blocked) return@mapNotNull null
            val last = list.lastOrNull { it.state == DMDeliveryState.SENT } ?: list.lastOrNull() ?: return@mapNotNull null
            DMConversation(peer, last, isUnread(peer, list))
        }.sortedByDescending { it.timestamp }
        updateBadge()
    }

    private fun lastIncoming(list: List<DMMessage>): DMMessage? = list.lastOrNull { !it.isMine }

    private fun isUnread(peer: String, list: List<DMMessage>): Boolean {
        val incoming = lastIncoming(list) ?: return false
        val last = list.lastOrNull()
        if (last != null && last.isMine && last.createdAt >= incoming.createdAt && last.state == DMDeliveryState.SENT) return false
        return incoming.createdAt > maxOf(readMarks[peer] ?: 0, readBaseline)
    }

    private fun updateBadge() {
        val unseen = conversations.any { conversation ->
            if (!conversation.isUnread || !isKnown(conversation.peer)) return@any false
            val incoming = lastIncoming(messagesByPeer[conversation.peer].orEmpty()) ?: return@any false
            incoming.createdAt > tabSeenAt
        }
        if (listVisibleState && unseen) {
            markTabSeen()
            return
        }
        NotificationBadge.hasUnreadMessages = unseen
    }

    private fun loadReadState(me: String) {
        readMarks = loadLongMap(storeKey("read_marks", me))
        val baseline = Prefs.long(storeKey("read_baseline", me))
        if (baseline > 0) {
            readBaseline = baseline
        } else {
            readBaseline = TimeFormat.now
            Prefs.set(storeKey("read_baseline", me), readBaseline)
        }
        val seen = Prefs.long(storeKey("tab_seen", me))
        tabSeenAt = if (seen > 0) seen else readBaseline
    }

    private fun loadLongMap(key: String): HashMap<String, Long> {
        val json = Json.obj(Prefs.string(key)) ?: return HashMap()
        val result = HashMap<String, Long>()
        for (name in json.keys()) result[name] = json.long(name)
        return result
    }

    private fun saveLongMap(key: String, map: Map<String, Long>) {
        Prefs.set(key, JSONObject(map as Map<*, *>).toString())
    }

    private fun persistReadMarks() {
        val me = me ?: return
        saveLongMap(storeKey("read_marks", me), readMarks)
    }

    private fun markReadSilently(peer: String) {
        val latest = messagesByPeer[peer]?.lastOrNull()?.createdAt ?: 0
        readMarks[peer] = maxOf(latest, TimeFormat.now, readMarks[peer] ?: 0)
        persistReadMarks()
    }

    fun markRead(peer: String) {
        markReadSilently(peer)
        rebuildConversations()
    }

    fun markUnread(peer: String) {
        val incoming = lastIncoming(messagesByPeer[peer].orEmpty()) ?: return
        readMarks[peer] = incoming.createdAt - 1
        persistReadMarks()
        rebuildConversations()
    }

    fun markAllRead() {
        for ((peer, list) in messagesByPeer) readMarks[peer] = maxOf(list.lastOrNull()?.createdAt ?: 0, TimeFormat.now)
        persistReadMarks()
        rebuildConversations()
    }

    fun markTabSeen() {
        val me = me ?: return
        tabSeenAt = TimeFormat.now
        Prefs.set(storeKey("tab_seen", me), tabSeenAt)
        NotificationBadge.hasUnreadMessages = false
    }

    suspend fun send(text: String, peer: String) {
        val content = text.trim()
        if (content.isEmpty()) return
        val me = me ?: throw CoreError(L("dmNotSignedIn"))
        val pending = DMMessage("pending-${UUID.randomUUID()}", me, peer, content, TimeFormat.now, true, 14, state = DMDeliveryState.SENDING)
        addPending(pending)
        try {
            val groupId = ensureChat(peer)
            val sent = MarmotEngine.send(groupId, MESSAGE_KIND, content, emptyList())
            deliver(sent, groupId, peer, pending.id)
        } catch (error: Throwable) {
            markFailed(pending.id, peer)
            throw error
        }
    }

    suspend fun sendFile(data: ByteArray, mimeType: String, peer: String) {
        val prepared = prepareFile(data, mimeType, peer)
        sendPrepared(prepared, peer)
    }

    suspend fun prepareFile(data: ByteArray, mimeType: String, peer: String): DMPreparedFile {
        if (data.size > MAX_FILE_SIZE) throw CoreError(L("fileTooLarge"))
        val key = privateKey ?: throw CoreError(L("dmNotSignedIn"))
        val groupId = ensureChat(peer)
        val ext = DMMediaCrypto.fileExtension(mimeType)
        val filename = "${UUID.randomUUID().toString().take(8).lowercase()}.$ext"
        val encrypted = try {
            MarmotEngine.encryptMedia(groupId, data, mimeType, filename)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            throw CoreError("${L("encryptionFailed")}: ${coreErrorMessage(error)}")
        }
        try {
            val body = withContext(Dispatchers.IO) { encrypted.file.readBytes() }
            DMMediaCrypto.cacheFile(encrypted.originalHash, ext)?.let { file ->
                withContext(Dispatchers.IO) {
                    runCatching {
                        file.parentFile?.mkdirs()
                        val temp = File(file.parentFile, "${file.name}.${UUID.randomUUID()}.tmp")
                        temp.writeBytes(data)
                        temp.renameTo(file)
                    }
                }
                verifiedMedia.add(file.name)
            }
            val url = try {
                DMMediaCrypto.upload(body, encrypted.encryptedHash, key, RelayConfig.encryptedMediaServers)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                throw CoreError(L("failedToUploadEncryptedMedia"))
            }
            return DMPreparedFile(url, encrypted.mimeType, groupId, encrypted.imeta, encrypted.originalHash, encrypted.filename, encrypted.size)
        } finally {
            withContext(Dispatchers.IO) { encrypted.file.delete() }
        }
    }

    suspend fun sendPrepared(file: DMPreparedFile, peer: String) {
        val me = me ?: throw CoreError(L("dmNotSignedIn"))
        val tag = file.tag
        val info = DMFileInfo(file.url, file.mimeType, file.groupId, tag.drop(1), file.originalHash, file.filename, file.size)
        val pending = DMMessage("pending-${UUID.randomUUID()}", me, peer, file.url, TimeFormat.now, true, 15, info, DMDeliveryState.SENDING)
        addPending(pending)
        try {
            if (groups[file.groupId] == null) throw CoreError(L("dmSendFailed"))
            val sent = MarmotEngine.send(file.groupId, MESSAGE_KIND, "", listOf(tag))
            deliver(sent, file.groupId, peer, pending.id)
        } catch (error: Throwable) {
            markFailed(pending.id, peer)
            throw error
        }
    }

    suspend fun retry(message: DMMessage) {
        discard(message)
        val file = message.file
        val hash = file?.originalHash
        if (message.isFile && file != null && hash != null) {
            val prepared = DMPreparedFile(file.url, file.mimeType, file.groupId, file.imetaWithoutURL, hash, file.filename, file.size ?: 0)
            sendPrepared(prepared, message.peer)
        } else {
            send(message.content, message.peer)
        }
    }

    fun discard(message: DMMessage) {
        if (message.state == DMDeliveryState.SENT) return
        updateList(message.peer) { list -> list.removeAll { it.id == message.id } }
        saveOutbox()
        rebuildConversations()
    }

    private fun addPending(message: DMMessage) {
        insert(message)
        saveOutbox()
        rebuildConversations()
    }

    private fun markFailed(id: String, peer: String) {
        val index = messagesByPeer[peer]?.indexOfFirst { it.id == id } ?: return
        if (index < 0) return
        updateList(peer) { list -> list[index] = list[index].copy(state = DMDeliveryState.FAILED) }
        saveOutbox()
        rebuildConversations()
    }

    private fun outboxFile(me: String): File = File(File(MarmotEngine.storageDirectory, me.lowercase()), "outbox.json")

    private fun loadOutbox(me: String) {
        val file = outboxFile(me)
        if (!file.exists()) {
            outboxReady = true
            return
        }
        val raw = runCatching { file.readText() }.getOrNull() ?: return
        val array = runCatching { JSONArray(raw) }.getOrNull() ?: return
        val saved = (0 until array.length()).mapNotNull { array.optJSONObject(it)?.let(DMMessage::fromJson) }
        outboxReady = true
        for (message in saved) {
            if (!message.isMine || message.sender != me || wasDelivered(message)) continue
            insert(message.copy(state = DMDeliveryState.FAILED))
        }
        saveOutbox()
        rebuildConversations()
    }

    private fun wasDelivered(message: DMMessage): Boolean = messagesByPeer[message.peer].orEmpty().any { sent ->
        sent.isMine && sent.state == DMDeliveryState.SENT && sent.kind == message.kind && sent.content == message.content &&
            kotlin.math.abs(sent.createdAt - message.createdAt) < 300
    }

    private fun saveOutbox() {
        val me = me ?: return
        if (!outboxReady) return
        val unsent = messagesByPeer.values.flatten().filter { it.isMine && it.state != DMDeliveryState.SENT }.sortedBy { it.createdAt }
        val file = outboxFile(me)
        if (unsent.isEmpty()) {
            file.delete()
            return
        }
        runCatching {
            file.parentFile?.mkdirs()
            val array = JSONArray()
            unsent.takeLast(100).forEach { array.put(it.toJson()) }
            val temp = File(file.parentFile, "outbox.json.tmp")
            temp.writeText(array.toString())
            temp.renameTo(file)
        }
    }

    private fun hide(ids: List<String>) {
        val me = me ?: return
        if (ids.isEmpty()) return
        hiddenIds.addAll(ids)
        Prefs.setStringList(storeKey("marmot_hidden", me), hiddenIds.toList().takeLast(500))
    }

    private suspend fun deliver(sent: MarmotSent, groupId: String, peer: String, pendingId: String) {
        val me = me ?: throw CoreError(L("dmNotSignedIn"))
        val generation = this.generation
        val messages = Json.obj(sent.messageJSON)?.let { DMMessage.fromMarmot(it, me, peer) }.orEmpty()
        Json.obj(sent.eventJSON)?.str("id")?.let { seenEvents.add(it) }
        val accepted = publish(sent.eventJSON, relays(groupId))
        if (generation != this.generation) return
        if (accepted.isNullOrEmpty()) {
            hide(messages.map { it.id })
            throw CoreError(L("dmSendFailed"))
        }
        val visible = messages.filter { it.id !in hiddenIds }
        updateList(peer) { list ->
            val index = list.indexOfFirst { it.id == pendingId }
            if (index < 0) return@updateList
            if (visible.isEmpty()) {
                list[index] = list[index].copy(state = DMDeliveryState.SENT)
            } else {
                val visibleIds = visible.map { it.id }.toSet()
                list.removeAll { it.id in visibleIds }
                val slot = list.indexOfFirst { it.id == pendingId }
                if (slot >= 0) {
                    list.removeAt(slot)
                    list.addAll(slot, visible)
                }
            }
        }
        val sortedRelays = accepted.sorted()
        deliveryRelays = deliveryRelays + messages.associate { it.id to sortedRelays }
        groups[groupId]?.let { groups[groupId] = it.copy(lastMessageAt = TimeFormat.now) }
        apply(messages)
        markReadSilently(peer)
        saveOutbox()
        rebuildConversations()
    }

    private fun relays(groupId: String): List<String> {
        val relays = groups[groupId]?.relays.orEmpty()
        return relays.ifEmpty { RelayConfig.mainRelays }
    }

    private suspend fun ensureChat(peer: String): String {
        preferredGroup(peer)?.let { return it.id }
        chatCreation[peer]?.let { return it.await() }
        val task = App.scope.async { createChat(peer) }
        chatCreation[peer] = task
        try {
            return task.await()
        } finally {
            if (chatCreation[peer] === task) chatCreation.remove(peer)
        }
    }

    private suspend fun createChat(peer: String): String {
        if (me == null) throw CoreError(L("dmNotSignedIn"))
        val generation = this.generation
        val keyPackage = keyPackage(peer, fresh = true)
        if (keyPackage == null) {
            peerStatus = peerStatus + (peer to DMPeerStatus.UNAVAILABLE)
            val name = ProfileCache.profile(peer)?.bestName ?: Profile.shortNpub(peer)
            throw CoreError(L("dmPeerNotOnMarmot", "name" to name))
        }
        currentCoroutineContext().ensureActive()
        if (generation != this.generation) throw CancellationException()
        val chat = MarmotEngine.createChat(keyPackage, RelayConfig.mainRelays)
        val group = Json.obj(chat.groupJSON)?.let(MarmotGroup::from)
        if (generation != this.generation || group == null) throw CoreError(L("dmSendFailed"))
        groups[group.id] = group
        peerStatus = peerStatus + (peer to DMPeerStatus.READY)
        startGroupRealtime(generation)
        val inbox = inboxRelays(peer)
        val targets = chat.welcomeRelays.toMutableList()
        for (relay in inbox + RelayConfig.discoveryRelays) if (relay !in targets) targets.add(relay)
        for (welcome in chat.welcomes) {
            val accepted = publish(welcome, targets).orEmpty()
            if (accepted.isEmpty()) savePendingWelcome(welcome, targets)
        }
        return group.id
    }

    private suspend fun keyPackage(peer: String, fresh: Boolean): String? {
        keyPackages[peer]?.let { cached ->
            val age = System.currentTimeMillis() - cached.fetchedAt
            if (cached.event != null && (!fresh || age < 600_000)) return cached.event
            if (cached.event == null && age < 60_000) return null
        }
        val listFilter = Json.string(mapOf("kinds" to listOf(10051), "authors" to listOf(peer), "limit" to 1))
        val lists = coroutineScope {
            val pooled = async { runCatching { fetchEvents(listFilter, 5u) }.getOrNull() }
            val discovered = async { runCatching { fetchEventsFromRelays(listFilter, RelayConfig.discoveryRelays, 5u) }.getOrNull() }
            Json.array(pooled.await()) + Json.array(discovered.await())
        }
        val relays = relayURLs(lists).toMutableList()
        for (relay in RelayConfig.discoveryRelays) if (relay !in relays) relays.add(relay)
        val filter = Json.string(mapOf("kinds" to listOf(30443, 443), "authors" to listOf(peer), "limit" to 20))
        val events = coroutineScope {
            val pooled = async { runCatching { fetchEvents(filter, 6u) }.getOrNull() }
            val remote = async { runCatching { fetchEventsFromRelays(filter, relays, 6u) }.getOrNull() }
            Json.array(pooled.await()) + Json.array(remote.await())
        }
        val picked = if (events.isEmpty()) null else runCatching { MarmotEngine.pickKeyPackage(JSONArray(events).toString(), peer) }.getOrNull()
        keyPackages[peer] = CachedKeyPackage(picked, System.currentTimeMillis())
        return picked
    }

    private suspend fun inboxRelays(pubkey: String): List<String> {
        inboxRelayCache[pubkey]?.let { return it }
        val filter = Json.string(mapOf("kinds" to listOf(10050), "authors" to listOf(pubkey), "limit" to 1))
        var relays = relayURLs(Json.array(runCatching { dbQueryEvents(filter, 1u) }.getOrNull()))
        if (relays.isEmpty()) relays = relayURLs(Json.array(runCatching { fetchEvents(filter, 5u) }.getOrNull()))
        inboxRelayCache[pubkey] = relays
        return relays
    }

    private suspend fun publishKeyPackageIfNeeded(me: String, generation: Int) {
        val stampKey = storeKey("marmot_kp_at", me)
        if (TimeFormat.now - Prefs.long(stampKey) <= KEY_PACKAGE_REFRESH) return
        val listFilter = Json.string(mapOf("kinds" to listOf(10051), "authors" to listOf(me), "limit" to 1))
        val existing = relayURLs(Json.array(runCatching { fetchEvents(listFilter, 5u) }.getOrNull()))
        val main = RelayConfig.mainRelays
        val relays = existing.ifEmpty { main }
        val targets = relays.toMutableList()
        for (relay in main + RelayConfig.discoveryRelays) if (relay !in targets) targets.add(relay)
        if (generation != this.generation) return
        if (existing.isEmpty()) {
            runCatching { MarmotEngine.keyPackageRelaysEvent(relays) }.getOrNull()?.let { publish(it, targets) }
        }
        if (generation != this.generation) return
        val event = runCatching { MarmotEngine.keyPackageEvent(relays) }.getOrNull() ?: return
        val accepted = publish(event, targets).orEmpty()
        if (generation != this.generation || accepted.isEmpty()) return
        Prefs.set(stampKey, TimeFormat.now)
    }

    private suspend fun rotateKeys(generation: Int) {
        if (generation != this.generation) return
        val targets = groups.keys.associateWith { relays(it) }
        val fallback = RelayConfig.mainRelays
        MarmotEngine.rotateKeys(KEY_ROTATION_AGE) { groupId, commit ->
            publish(commit, targets[groupId] ?: fallback).orEmpty().isNotEmpty()
        }
        if (generation != this.generation) return
        reloadGroups(loadingAll = false, generation = generation)
    }

    private fun savePendingWelcome(event: String, relays: List<String>) {
        val me = me ?: return
        val key = storeKey("marmot_pending_welcomes", me)
        val list = pendingWelcomes(key).toMutableList()
        list.add(JSONObject().put("event", event).put("relays", JSONArray(relays)))
        Prefs.set(key, JSONArray(list.takeLast(50)).toString())
    }

    private fun pendingWelcomes(key: String): List<JSONObject> = Json.array(Prefs.string(key))

    private suspend fun retryPendingWelcomes(generation: Int) {
        val me = me ?: return
        val key = storeKey("marmot_pending_welcomes", me)
        val list = pendingWelcomes(key)
        if (list.isEmpty()) return
        val remaining = mutableListOf<JSONObject>()
        for (item in list) {
            val event = item.str("event") ?: continue
            val relays = if (item.has("relays")) item.strings("relays") else RelayConfig.mainRelays
            val accepted = publish(event, relays).orEmpty()
            if (accepted.isEmpty()) remaining.add(item)
        }
        if (generation != this.generation) return
        Prefs.set(key, JSONArray(remaining).toString())
    }

    private suspend fun publish(json: String, relays: List<String>): List<String>? {
        if (relays.isNotEmpty()) {
            val raw = runCatching { sendEventTo(json, relays) }.getOrNull()
            if (raw != null) {
                val accepted = acceptedRelays(raw)
                if (accepted.isNotEmpty()) return accepted
            }
        }
        val raw = runCatching { sendEvent(json) }.getOrNull() ?: return null
        return acceptedRelays(raw)
    }

    private fun acceptedRelays(raw: String): List<String> = Json.obj(raw)?.strings("success").orEmpty()

    suspend fun decryptedFile(message: DMMessage): File {
        val file = message.file
        val hash = file?.originalHash ?: throw CoreError(L("failedToDecryptMedia"))
        val target = DMMediaCrypto.cacheFile(hash, file.fileExtension) ?: throw CoreError(L("failedToDecryptMedia"))
        val name = target.name
        if (name in verifiedMedia && target.exists()) return target
        mediaTasks[name]?.let { return it.await() }
        val task = App.scope.async(Dispatchers.IO) {
            val cached = if (target.exists()) runCatching { target.readBytes() }.getOrNull() else null
            if (cached != null && sha256Hash(cached).lowercase() == hash) return@async target
            val encrypted = DMMediaCrypto.download(file.url)
            val decrypted = try {
                MarmotEngine.decryptMedia(file.groupId, file.imeta, encrypted)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                throw CoreError(L("decryptionFailed"))
            }
            target.parentFile?.mkdirs()
            val temp = File(target.parentFile, "${target.name}.${UUID.randomUUID()}.tmp")
            temp.writeBytes(decrypted)
            if (!temp.renameTo(target)) {
                temp.delete()
                throw CoreError(L("failedToDecryptMedia"))
            }
            target
        }
        mediaTasks[name] = task
        try {
            val result = task.await()
            verifiedMedia.add(name)
            return result
        } finally {
            if (mediaTasks[name] === task) mediaTasks.remove(name)
        }
    }

    suspend fun searchProfiles(query: String, limit: Int = 40): List<Profile> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return emptyList()
        val raw = runCatching { dbSearchProfiles(trimmed, limit.toUInt()) }.getOrNull() ?: return emptyList()
        val profiles = Json.array(raw).map { Profile.from(it) }.filter { it.pubkey.isNotEmpty() }
        profiles.forEach { ProfileCache.set(it) }
        return profiles
    }

    suspend fun followingPubkeys(): List<String> {
        val me = me ?: Session.pubkey ?: return emptyList()
        return SyncService.followingList(me)
    }

    private fun relayURLs(events: List<JSONObject>): List<String> {
        val latest = events.maxByOrNull { it.long("created_at") } ?: return emptyList()
        val urls = mutableListOf<String>()
        for (tag in latest.tags()) {
            if (tag.size <= 1 || tag[0] != "relay") continue
            val url = tag[1].trim()
            if ((url.startsWith("wss://") || url.startsWith("ws://")) && url !in urls) urls.add(url)
        }
        return urls
    }

    private fun rawArray(raw: String?): List<String> {
        if (raw.isNullOrEmpty()) return emptyList()
        val array = runCatching { JSONArray(raw) }.getOrNull() ?: return emptyList()
        return (0 until array.length()).mapNotNull { array.optJSONObject(it)?.toString() }
    }
}

object DMMediaCrypto {
    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder().callTimeout(120, TimeUnit.SECONDS).readTimeout(120, TimeUnit.SECONDS).writeTimeout(120, TimeUnit.SECONDS).build()
    }

    suspend fun upload(data: ByteArray, sha256: String, privateKey: String, servers: List<String>): String {
        var lastError: Throwable = CoreError(L("failedToUploadEncryptedMedia"))
        for (server in servers) {
            try {
                return upload(data, sha256, privateKey, server)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                lastError = error
            }
        }
        throw lastError
    }

    suspend fun upload(data: ByteArray, sha256: String, privateKey: String, server: String): String = withContext(Dispatchers.IO) {
        val expiration = System.currentTimeMillis() / 1000 + 600
        val auth = createBlossomAuthEvent("Upload $sha256", sha256, expiration, privateKey)
        val token = Base64.encodeToString(auth.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        val base = server.trimEnd('/')
        val request = runCatching {
            Request.Builder()
                .url("$base/upload")
                .put(data.toRequestBody("application/octet-stream".toMediaType()))
                .header("Authorization", "Nostr $token")
                .build()
        }.getOrNull() ?: throw CoreError(L("failedToUploadEncryptedMedia"))
        client.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) throw CoreError(L("uploadFailed", "message" to "${response.code} ${body.take(200)}"))
            val json = Json.obj(body)
            val link = json?.str("url")?.trimEnd('.')
            if (!link.isNullOrEmpty()) return@withContext link
            val hash = json?.str("sha256")
            if (!hash.isNullOrEmpty()) return@withContext "$base/$hash"
            "$base/$sha256"
        }
    }

    suspend fun download(source: String): ByteArray = withContext(Dispatchers.IO) {
        val url = httpsUrl(source) ?: throw CoreError(L("failedToDecryptMedia"))
        val limit = 50L * 1024 * 1024 + 1024
        val request = Request.Builder().url(url).get().build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw CoreError(L("failedToDecryptMedia"))
            val body = response.body ?: throw CoreError(L("failedToDecryptMedia"))
            if (body.contentLength() > limit) throw CoreError(L("fileTooLarge"))
            val stream = body.byteStream()
            val output = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(64 * 1024)
            var total = 0L
            while (true) {
                val read = stream.read(buffer)
                if (read < 0) break
                total += read
                if (total > limit) throw CoreError(L("fileTooLarge"))
                output.write(buffer, 0, read)
            }
            output.toByteArray()
        }
    }

    private fun httpsUrl(source: String): String? {
        val uri = runCatching { java.net.URI(source) }.getOrNull() ?: return null
        if (uri.scheme?.lowercase() != "https" || uri.host.isNullOrEmpty()) return null
        return source
    }

    fun cacheDirectory(): File = File(App.context.cacheDir, "decrypted_media")

    fun cacheFile(hash: String, ext: String): File? {
        val normalized = hash.lowercase()
        if (normalized.length != 64 || !normalized.all { it in '0'..'9' || it in 'a'..'f' }) return null
        if (ext.length !in 1..10 || !ext.all { it.code < 128 && it.isLetterOrDigit() }) return null
        return File(cacheDirectory(), "decrypted_$normalized.${ext.lowercase()}")
    }

    fun fileExtension(mimeType: String): String {
        val normalized = mimeType.split(";").firstOrNull()?.trim()?.lowercase().orEmpty()
        val map = mapOf(
            "image/jpeg" to "jpg", "image/png" to "png", "image/gif" to "gif", "image/webp" to "webp", "image/heic" to "heic",
            "video/mp4" to "mp4", "video/quicktime" to "mov", "video/x-msvideo" to "avi", "video/webm" to "webm",
            "audio/mpeg" to "mp3", "audio/wav" to "wav", "audio/ogg" to "ogg", "audio/mp4" to "m4a",
        )
        return map[normalized] ?: "bin"
    }
}
