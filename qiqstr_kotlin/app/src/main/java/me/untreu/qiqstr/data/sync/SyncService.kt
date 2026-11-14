package me.untreu.qiqstr.data.sync

import com.qiqstr.core.dbEventExists
import com.qiqstr.core.dbGetFollowingList
import com.qiqstr.core.dbGetNotificationsMissingProfiles
import com.qiqstr.core.dbProcessDeletionEvents
import com.qiqstr.core.dbQueryEvents
import com.qiqstr.core.dbSaveEvents
import com.qiqstr.core.dbSaveFollowingListFromEvent
import com.qiqstr.core.extractPubkeysFromEvents
import com.qiqstr.core.extractRepostOriginalIds
import com.qiqstr.core.fetchEventById
import com.qiqstr.core.fetchEventsFromRelays
import com.qiqstr.core.fetchMissingProfilesForEvents
import com.qiqstr.core.fetchProfileEvents
import com.qiqstr.core.fetchThreadAncestors
import com.qiqstr.core.filterReplyEventIds
import com.qiqstr.core.getConnectedRelayCount
import com.qiqstr.core.isEventNewAndTrack
import com.qiqstr.core.sendEvent
import com.qiqstr.core.sendEventTo
import com.qiqstr.core.subscribeToEvents
import com.qiqstr.core.syncEvents
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.data.accounts.AccountStore
import me.untreu.qiqstr.data.bridge.EventStream
import me.untreu.qiqstr.data.services.ListConfirmation
import me.untreu.qiqstr.data.services.ListError
import me.untreu.qiqstr.data.services.RelayConfig
import org.json.JSONArray
import org.json.JSONObject

interface RealtimeNotificationHandler {
    fun shouldBadge(event: JSONObject, me: String): Boolean = true
    fun handleRealtime(event: JSONObject, me: String) {}
}

object SyncService {
    private val lastSync = HashMap<String, Long>()
    private val profileRequests = HashMap<String, Long>()
    private var feedJob: Job? = null
    private var notificationJob: Job? = null
    private var realtimeGeneration = 0
    private var feedLastEventTs: Long? = null
    private var notificationLastEventTs: Long? = null
    private const val MIN_INTERVAL = 30_000L
    var notificationHandler: RealtimeNotificationHandler = object : RealtimeNotificationHandler {}

    fun reset() {
        lastSync.clear()
        stopRealtime()
        feedLastEventTs = null
        notificationLastEventTs = null
    }

    private fun shouldSync(key: String): Boolean {
        val last = lastSync[key] ?: return true
        return System.currentTimeMillis() - last > MIN_INTERVAL
    }

    private fun since(key: String): Long? = lastSync[key]?.let { it / 1000 - 60 }

    private fun mark(key: String) {
        App.scope.launch { if (hasConnectedRelays()) lastSync[key] = System.currentTimeMillis() }
    }

    suspend fun fetchEvents(filter: Map<String, Any?>, timeout: Int = 10): List<JSONObject> =
        Json.array(runCatching { com.qiqstr.core.fetchEvents(Json.string(filter), timeout.toUInt()) }.getOrNull())

    private suspend fun fetchAndStore(filter: Map<String, Any?>): List<JSONObject> {
        val now = TimeFormat.now
        val sinceSecs = (filter["since"] as? Number)?.toLong() ?: (now - 86400 * 2)
        if (now - sinceSecs <= 86400) {
            val syncFilter = filter - "limit"
            val result = Json.obj(runCatching { syncEvents(Json.string(syncFilter)) }.getOrNull())
            if (result != null && result.long("received") > 0) return emptyList()
        }
        return fetchEvents(filter)
    }

    suspend fun followingList(pubkey: String): List<String> = runCatching { dbGetFollowingList(pubkey) }.getOrDefault(emptyList())

    suspend fun syncFeed(force: Boolean = false) {
        val me = Session.pubkey ?: return
        val follows = (followingList(me) + me).distinct().sorted()
        val key = "feed_${me}_${follows.joinToString("").hashCode()}"
        if (!force && !shouldSync(key)) return
        val since = since(key) ?: (TimeFormat.now - 86400 * 2)
        val noteEvents = coroutineScope {
            val notes = async { fetchAndStore(mapOf("authors" to follows, "kinds" to listOf(1, 5, 6, 1068), "since" to since, "limit" to 100)) }
            val articles = async { fetchAndStore(mapOf("kinds" to listOf(30023), "authors" to follows, "since" to since, "limit" to 30)) }
            articles.await()
            notes.await()
        }
        runCatching { dbProcessDeletionEvents() }
        DataBus.feedChanged()
        queueMissingRepostOriginals(since)
        if (noteEvents.isNotEmpty()) backgroundFollowUps(noteEvents)
        mark(key)
    }

    suspend fun syncListFeed(pubkeys: List<String>, force: Boolean = false) {
        if (pubkeys.isEmpty()) return
        val key = "list_feed_${pubkeys.sorted().joinToString("").hashCode()}"
        if (!force && !shouldSync(key)) return
        val since = since(key) ?: (TimeFormat.now - 86400 * 2)
        val events = fetchAndStore(mapOf("authors" to pubkeys, "kinds" to listOf(1, 5, 6, 1068), "since" to since, "limit" to 100))
        runCatching { dbProcessDeletionEvents() }
        DataBus.feedChanged()
        queueMissingRepostOriginals(since)
        if (events.isNotEmpty()) backgroundFollowUps(events)
        mark(key)
    }

    suspend fun syncProfile(pubkey: String, force: Boolean = false) {
        val key = "profile_$pubkey"
        if (!force && !shouldSync(key)) return
        fetchEvents(mapOf("kinds" to listOf(0), "authors" to listOf(pubkey), "limit" to 1))
        DataBus.profileChanged()
        mark(key)
    }

    suspend fun syncProfiles(pubkeys: List<String>) {
        if (pubkeys.isEmpty()) return
        fetchEvents(mapOf("kinds" to listOf(0), "authors" to pubkeys, "limit" to pubkeys.size))
        DataBus.profileChanged()
    }

    suspend fun syncProfileNotes(pubkey: String, force: Boolean = false) {
        val key = "profile_notes_$pubkey"
        if (!force && !shouldSync(key)) return
        val sinceValue = since(key) ?: -1L
        val pubkeys = mutableSetOf(pubkey)
        val repostIds = mutableListOf<String>()
        var count = 0
        runCatching {
            EventStream.make { sink -> fetchProfileEvents(pubkey, "1,5,6", sinceValue, sink) }.collect { raw ->
                val event = Json.obj(raw) ?: return@collect
                event.str("pubkey")?.let(pubkeys::add)
                if (event.int("kind") == 6) {
                    for (tag in event.tags()) {
                        if (tag.size <= 1) continue
                        if (tag[0] == "e") repostIds.add(tag[1])
                        if (tag[0] == "p") pubkeys.add(tag[1])
                    }
                }
                count += 1
                if (count == 1 || count % 50 == 0) DataBus.feedChanged()
            }
        }
        runCatching { dbProcessDeletionEvents() }
        DataBus.feedChanged()
        fetchMissingProfiles(pubkeys.toList())
        fetchRepostOriginals(repostIds)
        mark(key)
    }

    suspend fun syncProfileReactions(pubkey: String) {
        val key = "profile_reactions_$pubkey"
        if (!shouldSync(key)) return
        val filter = mutableMapOf<String, Any?>("authors" to listOf(pubkey), "kinds" to listOf(7), "limit" to 50)
        since(key)?.let { filter["since"] = it }
        fetchEvents(filter)
        DataBus.interactionsChanged()
        mark(key)
    }

    suspend fun syncNotifications(force: Boolean = false) {
        val me = Session.pubkey ?: return
        val key = "notifications_$me"
        if (!force && !shouldSync(key)) return
        val first = lastSync[key] == null
        val sinceValue = since(key) ?: (TimeFormat.now - 86400 * 30)
        fetchAndStore(mapOf("#p" to listOf(me), "kinds" to listOf(1, 6, 7, 9735), "since" to sinceValue, "limit" to if (first) 300 else 150))
        DataBus.notificationsChanged()
        val missing = runCatching { dbGetNotificationsMissingProfiles(me, 200u) }.getOrDefault(emptyList())
        if (missing.isNotEmpty()) {
            syncProfiles(missing)
            DataBus.notificationsChanged()
        }
        mark(key)
    }

    suspend fun syncOlderNotifications(before: Long): Int {
        val me = Session.pubkey ?: return 0
        if (before <= 0) return 0
        val sinceValue = maxOf(0, before - 86400 * 90)
        val events = fetchEvents(mapOf("#p" to listOf(me), "kinds" to listOf(1, 6, 7, 9735), "until" to before - 1, "since" to sinceValue, "limit" to 100), timeout = 12)
        if (events.isNotEmpty()) {
            runCatching { dbSaveEvents(JSONArray(events).toString()) }
            DataBus.notificationsChanged()
            fetchMissingProfiles(events.mapNotNull { it.str("pubkey") }.distinct())
        }
        return events.size
    }

    suspend fun syncFollowingList(pubkey: String, force: Boolean = false) {
        val key = "following_$pubkey"
        if (!force && !shouldSync(key)) return
        var events = fetchEvents(mapOf("kinds" to listOf(3), "authors" to listOf(pubkey), "limit" to 1))
        if (events.isEmpty()) events = fetchIndexedContactLists(pubkey)
        events.maxByOrNull { it.long("created_at") }?.let { event ->
            runCatching { dbSaveFollowingListFromEvent(event.toString(), pubkey) }
        }
        if (pubkey == Session.pubkey) DataBus.feedChanged()
        mark(key)
    }

    suspend fun hasConnectedRelays(): Boolean = runCatching { getConnectedRelayCount() }.getOrDefault(0u) > 0u

    suspend fun fetchContactLists(pubkey: String): List<JSONObject> = fetchReplaceable(3, pubkey)

    suspend fun latestEditableEvent(kind: Int, author: String, dTag: String? = null, allowingNew: Boolean = false): JSONObject? {
        val filter = mutableMapOf<String, Any?>("kinds" to listOf(kind), "authors" to listOf(author))
        if (dTag != null) filter["#d"] = listOf(dTag)
        val cached = Json.array(runCatching { dbQueryEvents(Json.string(filter), 5u) }.getOrNull())
        val remote = fetchReplaceable(kind, author, dTag)
        val matches: (JSONObject) -> Boolean = { event ->
            event.int("kind") == kind && event.str("pubkey")?.lowercase() == author.lowercase() &&
                (dTag == null || event.tags().any { it.size > 1 && it[0] == "d" && it[1] == dTag })
        }
        if (remote.isEmpty()) {
            if (cached.any(matches)) throw CoreError(L("noRelayConnection"))
            if (!hasConnectedRelays()) throw CoreError(L("noRelayConnection"))
            if (allowingNew || Session.isNewAccount || AccountStore.wasCreatedHere(author)) return null
            if (!ListConfirmation.startNewList(kind)) throw ListError()
            return null
        }
        val newest = (cached + remote).filter(matches)
            .maxWithOrNull(compareBy<JSONObject>({ it.long("created_at") }, { it.str("id") ?: "" }))
        if (newest != null) runCatching { dbSaveEvents(JSONArray(listOf(newest)).toString()) }
        return newest
    }

    suspend fun fetchReplaceable(kind: Int, author: String, dTag: String? = null): List<JSONObject> = coroutineScope {
        val query = mutableMapOf<String, Any?>("kinds" to listOf(kind), "authors" to listOf(author), "limit" to 1)
        if (dTag != null) query["#d"] = listOf(dTag)
        val filterJson = Json.string(query)
        val pooled = async { Json.array(runCatching { com.qiqstr.core.fetchEvents(filterJson, 6u) }.getOrNull()) }
        val indexed = async { Json.array(runCatching { fetchEventsFromRelays(filterJson, RelayConfig.indexerRelays, 6u) }.getOrNull()) }
        (pooled.await() + indexed.await()).filter { it.int("kind") == kind && it.str("pubkey")?.lowercase() == author.lowercase() }
    }

    private suspend fun fetchIndexedContactLists(pubkey: String): List<JSONObject> {
        val filter = Json.string(mapOf("kinds" to listOf(3), "authors" to listOf(pubkey), "limit" to 1))
        return Json.array(runCatching { fetchEventsFromRelays(filter, RelayConfig.indexerRelays, 6u) }.getOrNull())
    }

    suspend fun syncHashtag(tag: String, force: Boolean = false) {
        val key = "hashtag_$tag"
        if (!force && !shouldSync(key)) return
        val events = fetchEvents(mapOf("kinds" to listOf(1), "#t" to listOf(tag.lowercase()), "limit" to 100))
        if (events.isNotEmpty()) backgroundFollowUps(events)
        DataBus.feedChanged()
        mark(key)
    }

    suspend fun syncArticles(authors: List<String>? = null, force: Boolean = false) {
        val key = "articles_${authors?.size ?: 0}"
        if (!force && !shouldSync(key)) return
        val filter = mutableMapOf<String, Any?>("kinds" to listOf(30023), "limit" to 50)
        if (authors != null) filter["authors"] = authors
        val events = fetchEvents(filter)
        fetchMissingProfiles(events.mapNotNull { it.str("pubkey") }.distinct())
        DataBus.feedChanged()
        mark(key)
    }

    suspend fun syncNote(id: String) {
        if (runCatching { dbEventExists(id) }.getOrDefault(false)) return
        runCatching { fetchEventById(id, 8u) }
        DataBus.feedChanged(listOf(id))
    }

    suspend fun syncInteractions(noteIds: List<String>) {
        if (noteIds.isEmpty()) return
        fetchEvents(mapOf("#e" to noteIds, "kinds" to listOf(1, 6, 7, 9735), "limit" to 500), timeout = 8)
        DataBus.interactionsChanged()
    }

    fun backgroundFollowUps(events: List<JSONObject>) {
        val json = JSONArray(events).toString()
        App.scope.launch {
            runCatching { extractPubkeysFromEvents(json) }.getOrNull()?.let { fetchMissingProfiles(it) }
            runCatching { extractRepostOriginalIds(json) }.getOrNull()?.let { fetchRepostOriginals(it) }
            val replyIds = runCatching { filterReplyEventIds(json) }.getOrNull()?.take(40).orEmpty()
            if (replyIds.isNotEmpty()) {
                val fetched = runCatching { fetchThreadAncestors(replyIds) }.getOrDefault(0u)
                if (fetched > 0u) DataBus.feedChanged()
            }
        }
    }

    fun fetchMissingProfiles(pubkeys: List<String>) {
        val now = System.currentTimeMillis()
        if (profileRequests.size > 5_000) profileRequests.entries.removeAll { now - it.value >= 600_000 }
        val wanted = pubkeys.filter { it.isNotEmpty() && (profileRequests[it]?.let { t -> now - t >= 600_000 } ?: true) }.distinct()
        if (wanted.isEmpty()) return
        wanted.forEach { profileRequests[it] = now }
        val json = Json.string(wanted.map { mapOf("pubkey" to it) })
        App.scope.launch {
            val found = runCatching { fetchMissingProfilesForEvents(json) }.getOrDefault(0u)
            if (found > 0u) {
                ProfileCache.load(wanted, fetchMissing = false)
                DataBus.profileChanged()
                DataBus.feedChanged()
            }
        }
    }

    fun fetchRepostOriginals(ids: List<String>) {
        if (ids.isEmpty()) return
        val json = Json.string(ids.take(50))
        App.scope.launch {
            val n = runCatching { com.qiqstr.core.fetchRepostOriginals(json) }.getOrDefault(0u)
            if (n > 0u) DataBus.feedChanged()
        }
    }

    private fun queueMissingRepostOriginals(since: Long) {
        App.scope.launch {
            runCatching { com.qiqstr.core.queueMissingRepostOriginals(since) }.getOrNull()?.let { fetchRepostOriginals(it) }
        }
    }

    suspend fun publish(eventJson: String, relays: List<String>? = null): JSONObject {
        val event = Json.obj(eventJson) ?: throw CoreError("Invalid event")
        val me = Session.pubkey
        if (me != null && event.str("pubkey") != me) throw CoreError("Event signer does not match the active account")
        val raw = try {
            if (relays != null) sendEventTo(eventJson, relays) else sendEvent(eventJson)
        } catch (error: Throwable) {
            val message = coreErrorMessage(error)
            if (message.contains("No relay accepted") || message.contains("No publication relays")) throw CoreError(L("publishNoRelayAccepted"))
            throw error
        }
        val result = Json.obj(raw) ?: JSONObject()
        val success = result.optJSONArray("success")
        if (success == null || success.length() == 0) throw CoreError(L("publishNoRelayAccepted"))
        runCatching { dbSaveEvents("[$eventJson]") }
        DataBus.feedChanged(listOf(event.str("id") ?: ""))
        DataBus.interactionsChanged()
        return event
    }

    fun startRealtime() {
        val me = Session.pubkey ?: return
        stopRealtime()
        realtimeGeneration += 1
        val generation = realtimeGeneration
        feedJob = App.scope.launch { runFeedSubscription(me, generation) }
        notificationJob = App.scope.launch { runNotificationSubscription(me, generation) }
    }

    fun stopRealtime() {
        realtimeGeneration += 1
        feedJob?.cancel(); feedJob = null
        notificationJob?.cancel(); notificationJob = null
    }

    private suspend fun runFeedSubscription(me: String, generation: Int) = coroutineScope {
        var attempts = 0
        while (isActive && generation == realtimeGeneration) {
            val follows = (followingList(me) + me).distinct()
            val since = feedLastEventTs?.let { it - 1 } ?: (TimeFormat.now - 60)
            val filter = Json.string(mapOf("kinds" to listOf(1, 5, 6, 1068), "authors" to follows, "since" to since))
            runCatching {
                EventStream.make { sink -> subscribeToEvents(filter, sink) }.collect { raw ->
                    if (generation != realtimeGeneration) throw kotlinx.coroutines.CancellationException()
                    val event = Json.obj(raw) ?: return@collect
                    attempts = 0
                    val created = event.long("created_at")
                    if (created > (feedLastEventTs ?: 0)) feedLastEventTs = created
                    val id = event.str("id") ?: ""
                    if (id.isNotEmpty() && !isEventNewAndTrack(id)) return@collect
                    runCatching { dbSaveEvents("[$raw]") }
                    if (event.int("kind") == 5) runCatching { dbProcessDeletionEvents() }
                    DataBus.feedChanged(listOf(id))
                    backgroundFollowUps(listOf(event))
                }
            }
            attempts += 1
            delay(minOf(30, 2 * attempts) * 1000L)
        }
    }

    private suspend fun runNotificationSubscription(me: String, generation: Int) = coroutineScope {
        var attempts = 0
        while (isActive && generation == realtimeGeneration) {
            val since = notificationLastEventTs?.let { it - 1 } ?: (TimeFormat.now - 60)
            val filter = Json.string(mapOf("kinds" to listOf(1, 6, 7, 9735), "#p" to listOf(me), "since" to since))
            runCatching {
                EventStream.make { sink -> subscribeToEvents(filter, sink) }.collect { raw ->
                    if (generation != realtimeGeneration) throw kotlinx.coroutines.CancellationException()
                    val event = Json.obj(raw) ?: return@collect
                    attempts = 0
                    val created = event.long("created_at")
                    if (created > (notificationLastEventTs ?: 0)) notificationLastEventTs = created
                    runCatching { dbSaveEvents("[$raw]") }
                    val from = event.str("pubkey")
                    if (from != null && from != me && notificationHandler.shouldBadge(event, me)) {
                        NotificationBadge.markUnread(ProfileCache.profile(from)?.bestName)
                    }
                    notificationHandler.handleRealtime(event, me)
                    DataBus.notificationsChanged()
                    if (from != null) fetchMissingProfiles(listOf(from))
                }
            }
            attempts += 1
            delay(minOf(30, 2 * attempts) * 1000L)
        }
    }
}
