package me.untreu.qiqstr.data.services

import android.net.Uri
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.qiqstr.core.signEvent
import com.qiqstr.core.fetchEventsFromRelays
import com.qiqstr.core.getRelayList
import com.qiqstr.core.sendEventTo
import com.qiqstr.core.subscribeToEvents
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.bridge.EventStream
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import org.json.JSONObject

enum class LiveStatus(val raw: String) {
    PLANNED("planned"), LIVE("live"), ENDED("ended");

    companion object {
        fun from(raw: String?) = entries.firstOrNull { it.raw == raw?.lowercase() } ?: ENDED
    }
}

@Immutable
data class LiveStream(
    val eventId: String,
    val pubkey: String,
    val identifier: String,
    val title: String,
    val summary: String,
    val image: String?,
    val streamingURL: String?,
    val recordingURL: String?,
    val status: LiveStatus,
    val starts: Long?,
    val ends: Long?,
    val participants: Long?,
    val hosts: List<String>,
    val relays: List<String>,
    val hashtags: List<String>,
    val createdAt: Long,
    val hasContentWarning: Boolean,
) {
    val id: String get() = coordinate
    val coordinate: String get() = "$KIND:$pubkey:$identifier"
    val host: String get() = hosts.firstOrNull() ?: pubkey
    val naddr: String? get() = Nip19.naddr(KIND, pubkey, identifier)
    val startedAt: Long get() = starts ?: createdAt
    val playbackURL: String? get() = if (isLive) streamingURL else recordingURL ?: streamingURL
    val canReplay: Boolean get() = status == LiveStatus.ENDED && recordingURL != null

    val isLive: Boolean
        get() {
            if (status != LiveStatus.LIVE || streamingURL == null) return false
            val now = TimeFormat.now
            return now - createdAt < 2 * 3600 || now - startedAt < 8 * 3600
        }

    companion object {
        const val KIND = 30311
        const val CHAT_KIND = 1311

        fun from(json: JSONObject): LiveStream? {
            if (json.int("kind") != KIND) return null
            val pubkey = json.str("pubkey") ?: return null
            val eventId = json.str("id") ?: return null
            val tags = json.tags()
            fun value(name: String): String? = tags.firstOrNull { it.size > 1 && it[0] == name }?.get(1)?.trim()?.ifEmpty { null }
            val title = value("title") ?: ""
            val summary = value("summary") ?: ""
            val people = tags.filter { it.size > 1 && it[0] == "p" && it[1].length == 64 }
            val hostTags = people.filter { it.size > 3 && it[3].lowercase() == "host" }.map { it[1].lowercase() }
            val hashtags = tags.filter { it.size > 1 && it[0] == "t" }.map { it[1].lowercase() }
            return LiveStream(
                eventId = eventId,
                pubkey = pubkey,
                identifier = value("d") ?: "",
                title = title,
                summary = summary,
                image = value("image")?.takeIf { it.startsWith("http") },
                streamingURL = playableURL(tags.filter { it.size > 1 && it[0] == "streaming" }.map { it[1] }),
                recordingURL = playableURL(tags.filter { it.size > 1 && it[0] == "recording" }.map { it[1] }),
                status = LiveStatus.from(value("status")),
                starts = value("starts")?.toLongOrNull(),
                ends = value("ends")?.toLongOrNull(),
                participants = value("current_participants")?.toLongOrNull(),
                hosts = hostTags.ifEmpty { listOf(pubkey) },
                relays = tags.filter { it.firstOrNull() == "relays" }.flatMap { it.drop(1) }.filter { it.startsWith("wss://") },
                hashtags = hashtags,
                createdAt = json.long("created_at"),
                hasContentWarning = tags.any { it.firstOrNull() == "content-warning" } ||
                    hashtags.any { it in setOf("nsfw", "adult", "18plus", "porn") } ||
                    listOf(title, summary).any { it.contains("🔞") || it.lowercase().contains("nsfw") },
            )
        }

        private fun playableURL(values: List<String>): String? {
            val urls = values.map { it.trim() }.filter {
                val scheme = runCatching { Uri.parse(it).scheme }.getOrNull()
                scheme == "https" || scheme == "http"
            }
            return urls.firstOrNull { runCatching { Uri.parse(it).lastPathSegment }.getOrNull()?.lowercase()?.endsWith(".m3u8") == true } ?: urls.firstOrNull()
        }
    }
}

@Immutable
data class LiveChatMessage(val id: String, val pubkey: String, val content: String, val createdAt: Long) {
    companion object {
        fun from(json: JSONObject): LiveChatMessage? {
            if (json.int("kind") != LiveStream.CHAT_KIND) return null
            val id = json.str("id") ?: return null
            val pubkey = json.str("pubkey") ?: return null
            val content = json.text("content").trim()
            if (content.isEmpty()) return null
            return LiveChatMessage(id, pubkey, content, json.long("created_at"))
        }
    }
}

@Immutable
data class LiveSnapshot(
    val following: List<LiveStream> = emptyList(),
    val popular: List<LiveStream> = emptyList(),
    val recordings: List<LiveStream> = emptyList(),
) {
    val live: List<LiveStream> get() = following + popular
    val isEmpty: Boolean get() = following.isEmpty() && popular.isEmpty() && recordings.isEmpty()
}

object LiveService {
    const val TTL = 90_000L
    val streamRelays = listOf(
        "wss://relay.damus.io", "wss://nos.lol", "wss://relay.primal.net",
        "wss://relay.zap.stream", "wss://relay.snort.social", "wss://relay.fountain.fm", "wss://nostr.wine",
    )

    var snapshot by mutableStateOf(LiveSnapshot())
        private set
    var isLoading by mutableStateOf(false)
        private set
    private var loadedAt: Long? = null
    private var inflight: Deferred<LiveSnapshot>? = null
    private val streams = HashMap<String, LiveStream>()

    fun reset() {
        snapshot = LiveSnapshot()
        loadedAt = null
        streams.clear()
    }

    fun cached(coordinate: String): LiveStream? = streams[coordinate]

    suspend fun load(force: Boolean = false): LiveSnapshot {
        val at = loadedAt
        if (!force && at != null && System.currentTimeMillis() - at < TTL) return snapshot
        inflight?.let { return it.await() }
        val me = Session.pubkey
        val follows = if (me == null) emptyList() else SyncService.followingList(me)
        val muted = Session.mutedPubkeys.toSet()
        val relays = relays()
        val task = App.scope.async { fetchSnapshot(relays, follows.toSet(), muted) }
        inflight = task
        isLoading = true
        val result = try { task.await() } finally {
            inflight = null
            isLoading = false
        }
        if (!result.isEmpty || snapshot.isEmpty) {
            snapshot = result
            loadedAt = System.currentTimeMillis()
            for (stream in result.live + result.recordings) streams[stream.coordinate] = stream
            SyncService.fetchMissingProfiles((result.live + result.recordings).map { it.host }.distinct())
        }
        return snapshot
    }

    suspend fun stream(coordinate: String): LiveStream? {
        val parts = coordinate.split(":", limit = 3)
        if (parts.size != 3) return streams[coordinate]
        val filter = mapOf("kinds" to listOf(LiveStream.KIND), "authors" to listOf(parts[1]), "#d" to listOf(parts[2]), "limit" to 5)
        val events = fetch(filter, relays(streams[coordinate]?.relays ?: emptyList()), 6)
        val latest = latest(events.mapNotNull(LiveStream::from)).firstOrNull()
        if (latest != null) {
            streams[coordinate] = latest
            return latest
        }
        return streams[coordinate]
    }

    suspend fun chatHistory(stream: LiveStream, limit: Int = 150): List<LiveChatMessage> {
        val filter = mapOf("kinds" to listOf(LiveStream.CHAT_KIND), "#a" to listOf(stream.coordinate), "limit" to limit)
        return messages(fetch(filter, relays(stream.relays), 6))
    }

    suspend fun chatSince(stream: LiveStream, since: Long): List<LiveChatMessage> {
        val filter = mapOf("kinds" to listOf(LiveStream.CHAT_KIND), "#a" to listOf(stream.coordinate), "since" to since, "limit" to 100)
        return messages(fetch(filter, relays(stream.relays), 5))
    }

    fun chatStream(stream: LiveStream): Flow<LiveChatMessage> {
        val filter = Json.string(mapOf("kinds" to listOf(LiveStream.CHAT_KIND), "#a" to listOf(stream.coordinate), "since" to TimeFormat.now - 10))
        return EventStream.make { sink -> subscribeToEvents(filter, sink) }.mapNotNull { raw -> Json.obj(raw)?.let(LiveChatMessage::from) }
    }

    suspend fun sendChat(text: String, stream: LiveStream): LiveChatMessage {
        Session.requireSigner()
        val content = text.trim()
        if (content.isEmpty()) throw CoreError(L("liveChatEmptyMessage"))
        val tags = listOf(listOf("a", stream.coordinate, stream.relays.firstOrNull() ?: "", "root"))
        val json = signEvent(LiveStream.CHAT_KIND.toUShort(), content, tags)
        val event = SyncService.publish(json)
        val extra = (stream.relays + streamRelays.take(3)).distinct()
        App.scope.launch { runCatching { sendEventTo(json, extra) } }
        return LiveChatMessage.from(event) ?: throw CoreError(L("liveSendFailed"))
    }

    private suspend fun relays(extra: List<String> = emptyList()): List<String> {
        val mine = runCatching { getRelayList() }.getOrNull() ?: RelayConfig.mainRelays
        return (mine + streamRelays + extra.take(6)).filter { it.startsWith("wss://") }.distinct()
    }

    private suspend fun fetch(filter: Map<String, Any?>, relays: List<String>, timeout: Int): List<JSONObject> =
        Json.array(runCatching { fetchEventsFromRelays(Json.string(filter), relays, timeout.toUInt()) }.getOrNull())

    private fun messages(events: List<JSONObject>): List<LiveChatMessage> {
        val seen = HashSet<String>()
        return events.mapNotNull(LiveChatMessage::from)
            .filter { seen.add(it.id) }
            .sortedWith(compareBy<LiveChatMessage> { it.createdAt }.thenBy { it.id })
    }

    private fun latest(streams: List<LiveStream>): List<LiveStream> {
        val byCoordinate = HashMap<String, LiveStream>()
        for (stream in streams) {
            val existing = byCoordinate[stream.coordinate]
            if (existing == null || existing.createdAt < stream.createdAt) byCoordinate[stream.coordinate] = stream
        }
        return byCoordinate.values.sortedByDescending { it.createdAt }
    }

    private suspend fun fetchSnapshot(relays: List<String>, follows: Set<String>, muted: Set<String>): LiveSnapshot = coroutineScope {
        val now = TimeFormat.now
        val general = mapOf("kinds" to listOf(LiveStream.KIND), "since" to now - 86400 * 3, "limit" to 300)
        val generalEvents = async { fetch(general, relays, 8) }
        val followedEvents = async {
            if (follows.isEmpty()) emptyList()
            else fetch(mapOf("kinds" to listOf(LiveStream.KIND), "#p" to follows.take(500), "since" to now - 86400 * 7, "limit" to 200), relays, 8)
        }
        val all = latest((generalEvents.await() + followedEvents.await()).mapNotNull(LiveStream::from))
            .filter { stream -> !stream.hasContentWarning && stream.hosts.none { it in muted } && stream.pubkey !in muted }
        val live = all.filter { it.isLive }
        fun followed(stream: LiveStream) = stream.pubkey in follows || stream.hosts.any { it in follows }
        val popularity = compareByDescending<LiveStream> { it.participants ?: 0L }.thenByDescending { it.startedAt }
        val recordings = all.filter { it.canReplay && now - it.startedAt < 86400 * 7 }
            .sortedWith(compareByDescending<LiveStream> { followed(it) }.thenByDescending { it.startedAt })
        LiveSnapshot(
            following = live.filter(::followed).sortedWith(popularity),
            popular = live.filter { !followed(it) }.sortedWith(popularity),
            recordings = recordings.take(30),
        )
    }
}
