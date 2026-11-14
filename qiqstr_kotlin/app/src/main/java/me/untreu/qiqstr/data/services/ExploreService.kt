package me.untreu.qiqstr.data.services

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.qiqstr.core.dbGetHydratedArticle
import com.qiqstr.core.dbSaveEvents
import com.qiqstr.core.parseNoteContent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Article
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.ParsedContent
import org.json.JSONArray
import org.json.JSONObject

enum class DiscoverFeedContent(val raw: String) {
    NOTES("notes"), READS("reads");

    companion object {
        fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: NOTES
    }
}

@Immutable
data class DiscoverFeed(
    val pubkey: String,
    val dTag: String,
    val name: String,
    val about: String,
    val image: String?,
    val content: DiscoverFeedContent,
) {
    val id: String get() = "$pubkey:$dTag"

    fun toJson(): JSONObject = JSONObject()
        .put("pubkey", pubkey)
        .put("dTag", dTag)
        .put("name", name)
        .put("about", about)
        .put("image", image ?: JSONObject.NULL)
        .put("content", content.raw)

    companion object {
        fun from(j: JSONObject): DiscoverFeed? {
            val pubkey = j.str("pubkey") ?: return null
            val dTag = j.str("dTag") ?: return null
            return DiscoverFeed(pubkey, dTag, j.text("name"), j.text("about"), j.str("image"), DiscoverFeedContent.from(j.str("content")))
        }
    }
}

@Immutable
data class RisingPerson(val pubkey: String, val increase: Long, val followers: Long)

@Immutable
data class TopZap(
    val id: String,
    val sender: String,
    val receiver: String,
    val sats: Long,
    val comment: String,
    val noteId: String?,
    val createdAt: Long,
)

@Immutable
data class TrendingTopic(val tag: String, val count: Int)

@Immutable
data class ExploreMediaEntry(val url: String, val noteId: String, val author: String?, val isVideo: Boolean) {
    val id: String get() = "$noteId|$url"

    companion object {
        private val videoExtensions = setOf("mp4", "mov", "m4v", "webm", "m3u8", "mkv")

        fun isVideoUrl(url: String): Boolean {
            val path = url.substringBefore('?').substringBefore('#')
            return path.substringAfterLast('.', "").lowercase() in videoExtensions
        }
    }
}

object ExploreService {
    private const val TTL = 600_000L
    private const val MEDIA_PAGE = 30
    private const val PINNED_KEY = "explore_pinned_feeds"
    private val storedKinds = setOf(0, 1, 6, 30023)

    var feeds by mutableStateOf<List<DiscoverFeed>>(emptyList())
        private set
    var people by mutableStateOf<List<RisingPerson>>(emptyList())
        private set
    var zaps by mutableStateOf<List<TopZap>>(emptyList())
        private set
    var topics by mutableStateOf<List<TrendingTopic>>(emptyList())
        private set
    var media by mutableStateOf<List<ExploreMediaEntry>>(emptyList())
        private set
    var zapNotes by mutableStateOf<Map<String, Note>>(emptyMap())
        private set
    var loading by mutableStateOf<Set<String>>(emptySet())
        private set
    var failed by mutableStateOf<Set<String>>(emptySet())
        private set
    var mediaExhausted by mutableStateOf(false)
        private set
    var isLoadingMoreMedia by mutableStateOf(false)
        private set
    private var pinned by mutableStateOf<List<DiscoverFeed>>(emptyList())

    private val loadedAt = HashMap<String, Long>()
    private var mediaCursor: Long? = null
    private val mediaIds = HashSet<String>()
    private var pinnedOwner: String? = null
    private var pinnedLoaded = false

    fun isLoading(key: String) = key in loading

    val visibleMedia: List<ExploreMediaEntry>
        get() {
            val muted = Session.mutedPubkeys.toSet()
            return media.filter { (it.author ?: "") !in muted }
        }

    val visiblePeople: List<RisingPerson>
        get() {
            val muted = Session.mutedPubkeys.toSet()
            return people.filter { it.pubkey !in muted }
        }

    val visibleZaps: List<TopZap>
        get() {
            val muted = Session.mutedPubkeys.toSet()
            return zaps.filter { it.sender !in muted && it.receiver !in muted }
        }

    fun reset() {
        feeds = emptyList()
        people = emptyList()
        zaps = emptyList()
        topics = emptyList()
        media = emptyList()
        zapNotes = emptyMap()
        loading = emptySet()
        failed = emptySet()
        mediaExhausted = false
        pinned = emptyList()
        loadedAt.clear()
        mediaCursor = null
        mediaIds.clear()
        pinnedOwner = null
        pinnedLoaded = false
    }

    suspend fun loadAll(force: Boolean = false) = coroutineScope {
        launch { loadFeeds(force) }
        launch { loadPeople(force) }
        launch { loadZaps(force) }
        launch { loadTopics(force) }
        launch { loadMedia(force) }
    }

    private fun begin(key: String, force: Boolean, isEmpty: Boolean): Boolean {
        if (key in loading) return false
        val at = loadedAt[key]
        if (!force && !isEmpty && at != null && System.currentTimeMillis() - at < TTL) return false
        loading = loading + key
        return true
    }

    private fun finish(key: String, ok: Boolean) {
        loading = loading - key
        if (ok) {
            failed = failed - key
            loadedAt[key] = System.currentTimeMillis()
        } else {
            failed = failed + key
        }
    }

    private suspend fun store(events: List<JSONObject>) {
        val keep = PrimalCache.signed(events, storedKinds)
        if (keep.isEmpty()) return
        runCatching { dbSaveEvents(JSONArray(keep).toString()) }
    }

    suspend fun loadFeeds(force: Boolean = false) {
        if (!begin("feeds", force, feeds.isEmpty())) return
        val events = PrimalCache.request("get_featured_dvm_feeds", emptyMap(), 12)
        store(events)
        val kinds = HashMap<String, String>()
        for (info in PrimalCache.contents(events, 10000159)) {
            val id = info.str("event_id") ?: continue
            val kind = info.str("kind") ?: continue
            kinds.putIfAbsent(id, kind)
        }
        val seen = HashSet<String>()
        val parsed = events.filter { it.int("kind") == 31990 }.mapNotNull { event ->
            val pubkey = event.str("pubkey") ?: return@mapNotNull null
            val dTag = event.tags().firstOrNull { it.size > 1 && it[0] == "d" }?.get(1) ?: return@mapNotNull null
            val info = Json.obj(event.text("content")) ?: return@mapNotNull null
            val name = info.str("name") ?: return@mapNotNull null
            val amount = info.str("amount") ?: "free"
            if (amount != "free" && amount != "0") return@mapNotNull null
            val content = if (kinds[event.str("id") ?: ""] == "reads") DiscoverFeedContent.READS else DiscoverFeedContent.NOTES
            val feed = DiscoverFeed(pubkey, dTag, name, info.str("about") ?: "", info.str("picture") ?: info.str("image"), content)
            if (seen.add(feed.id)) feed else null
        }
        if (parsed.isNotEmpty()) {
            feeds = parsed.filter { it.content == DiscoverFeedContent.NOTES } + parsed.filter { it.content == DiscoverFeedContent.READS }
        }
        finish("feeds", parsed.isNotEmpty())
    }

    fun feed(id: String): DiscoverFeed? = feeds.firstOrNull { it.id == id } ?: pinnedFeeds.firstOrNull { it.id == id }

    private fun feedArgs(feed: DiscoverFeed, limit: Int): Map<String, Any?> {
        val args = mutableMapOf<String, Any?>("dvm_pubkey" to feed.pubkey, "dvm_id" to feed.dTag, "limit" to limit)
        Session.pubkey?.let { args["user_pubkey"] = it }
        return args
    }

    suspend fun feedNotes(feed: DiscoverFeed, limit: Int = 40): List<Note>? {
        val events = PrimalCache.request("dvm_feed", feedArgs(feed, limit), 15)
        if (events.isEmpty()) return null
        store(events)
        val notes = PrimalCache.signed(events, setOf(1))
        val available = notes.mapNotNull { it.str("id") }.toSet()
        var ids = PrimalCache.order(events).filter { it in available }
        if (ids.isEmpty()) ids = notes.mapNotNull { it.str("id") }
        SyncService.fetchMissingProfiles(SearchService.pubkeys(notes))
        return SearchService.notes(ids)
    }

    suspend fun feedArticles(feed: DiscoverFeed, limit: Int = 30): List<Article>? {
        val events = PrimalCache.request("dvm_feed", feedArgs(feed, limit), 15)
        if (events.isEmpty()) return null
        store(events)
        val raw = PrimalCache.signed(events, setOf(30023))
        val available = raw.mapNotNull { it.str("id") }.toSet()
        var ids = PrimalCache.order(events).filter { it in available }
        if (ids.isEmpty()) ids = raw.mapNotNull { it.str("id") }
        SyncService.fetchMissingProfiles(SearchService.pubkeys(raw))
        return ids.mapNotNull { id ->
            val json = Json.obj(runCatching { dbGetHydratedArticle(id) }.getOrNull()) ?: return@mapNotNull null
            Article.from(json).takeIf { it.id.isNotEmpty() }
        }
    }

    suspend fun loadPeople(force: Boolean = false) {
        if (!begin("people", force, people.isEmpty())) return
        val events = PrimalCache.request("explore_people", mapOf("limit" to 40), 12)
        store(events)
        val stats = PrimalCache.content(events, 10000157) as? JSONObject ?: JSONObject()
        val followers = PrimalCache.content(events, 10000133) as? JSONObject ?: JSONObject()
        var order = PrimalCache.order(events)
        if (order.isEmpty()) order = stats.keys().asSequence().toList()
        val me = Session.pubkey
        val muted = Session.mutedPubkeys.toSet()
        val parsed = order.mapNotNull { pubkey ->
            if (pubkey == me || pubkey in muted) return@mapNotNull null
            val info = stats.optJSONObject(pubkey) ?: return@mapNotNull null
            val total = (followers.opt(pubkey) as? Number)?.toLong() ?: info.long("count")
            RisingPerson(pubkey, info.long("increase"), total)
        }
        if (parsed.isNotEmpty()) {
            people = parsed
            ProfileCache.load(parsed.map { it.pubkey })
        }
        finish("people", parsed.isNotEmpty())
    }

    suspend fun loadZaps(force: Boolean = false) {
        if (!begin("zaps", force, zaps.isEmpty())) return
        val events = PrimalCache.request("explore_zaps", mapOf("limit" to 30), 12)
        store(events)
        val receipts = HashMap<String, JSONObject>()
        events.filter { it.int("kind") == 9735 }.forEach { e -> e.str("id")?.let { receipts.putIfAbsent(it, e) } }
        val muted = Session.mutedPubkeys.toSet()
        val parsed = PrimalCache.contents(events, 10000129).mapNotNull { info ->
            val id = info.str("zap_receipt_id") ?: return@mapNotNull null
            val sender = info.str("sender") ?: return@mapNotNull null
            val receiver = info.str("receiver") ?: return@mapNotNull null
            if (sender in muted || receiver in muted) return@mapNotNull null
            var comment = ""
            val description = receipts[id]?.tags()?.firstOrNull { it.size > 1 && it[0] == "description" }?.get(1)
            Json.obj(description)?.let { comment = it.text("content").trim() }
            TopZap(id, sender, receiver, info.long("amount_sats"), comment, info.str("event_id"), info.long("created_at"))
        }.sortedByDescending { it.sats }
        if (parsed.isNotEmpty()) {
            val noteIds = parsed.mapNotNull { it.noteId }.distinct()
            val notes = ExploreSafety.screen(SearchService.notes(noteIds))
            val byId = LinkedHashMap<String, Note>()
            notes.forEach { byId.putIfAbsent(it.id, it) }
            zapNotes = byId
            zaps = parsed.filter { zap -> zap.noteId?.let { byId.containsKey(it) } ?: true }
            ProfileCache.load(parsed.flatMap { listOf(it.sender, it.receiver) }.distinct())
        }
        finish("zaps", parsed.isNotEmpty())
    }

    suspend fun loadTopics(force: Boolean = false) {
        if (!begin("topics", force, topics.isEmpty())) return
        val events = PrimalCache.request("explore_topics", emptyMap(), 12)
        val counts = PrimalCache.content(events, 10000160) as? JSONObject ?: JSONObject()
        val parsed = counts.keys().asSequence().mapNotNull { key ->
            val tag = key.lowercase()
            val count = (counts.opt(key) as? Number)?.toInt() ?: return@mapNotNull null
            if (SearchService.hashtag(tag) != tag || isAdultTag(tag) || count <= 0) return@mapNotNull null
            TrendingTopic(tag, count)
        }.toList().sortedWith(compareByDescending<TrendingTopic> { it.count }.thenBy { it.tag })
        if (parsed.isNotEmpty()) topics = parsed.take(60)
        finish("topics", parsed.isNotEmpty())
    }

    suspend fun loadMedia(force: Boolean = false) {
        if (!begin("media", force, media.isEmpty())) return
        val (entries, cursor) = fetchMedia(null)
        if (entries.isNotEmpty()) {
            media = entries
            mediaIds.clear()
            mediaIds.addAll(entries.map { it.id })
            mediaCursor = cursor
            mediaExhausted = cursor == null
        }
        finish("media", entries.isNotEmpty())
    }

    suspend fun loadMoreMedia() {
        val cursor = mediaCursor
        if (isLoadingMoreMedia || mediaExhausted || cursor == null) return
        isLoadingMoreMedia = true
        try {
            val (entries, next) = fetchMedia(cursor)
            val fresh = entries.filter { mediaIds.add(it.id) }
            media = media + fresh
            mediaCursor = next
            if (fresh.isEmpty() || next == null) mediaExhausted = true
        } finally {
            isLoadingMoreMedia = false
        }
    }

    private suspend fun fetchMedia(until: Long?): Pair<List<ExploreMediaEntry>, Long?> {
        val args = mutableMapOf<String, Any?>("limit" to MEDIA_PAGE)
        if (until != null) args["until"] = until
        val events = PrimalCache.request("explore_media", args, 12)
        store(events)
        val raw = PrimalCache.signed(events, setOf(1))
        val available = raw.mapNotNull { it.str("id") }.toSet()
        var ids = PrimalCache.order(events).filter { it in available }
        if (ids.isEmpty()) ids = raw.sortedByDescending { it.long("created_at") }.mapNotNull { it.str("id") }
        val notes = ExploreSafety.screen(SearchService.notes(ids))
        val entries = withContext(Dispatchers.Default) {
            val seen = HashSet<String>()
            val result = mutableListOf<ExploreMediaEntry>()
            for (note in notes) {
                if (note.isRepost || isSensitive(note)) continue
                val parsed = Json.obj(runCatching { parseNoteContent(note.content) }.getOrNull())?.let(ParsedContent::from) ?: continue
                for (url in parsed.mediaUrls) {
                    if (seen.add(url)) result.add(ExploreMediaEntry(url, note.id, note.pubkey, ExploreMediaEntry.isVideoUrl(url)))
                }
            }
            result
        }
        val cursor = PrimalCache.page(events)?.first?.takeIf { it > 0 && it != until }
        return entries to (if (raw.isEmpty()) null else cursor)
    }

    private val adultTags = setOf(
        "nsfw", "nude", "nudes", "nudity", "naked", "porn", "porno", "adult", "18plus", "18", "xxx", "sexy", "sex",
        "boobs", "tits", "ass", "lewd", "hentai", "erotic", "erotica", "onlyfans", "nsfwart", "milf", "fetish", "lingerie",
    )
    private val sensitivePattern = Regex("""#(nsfw|nude|nudes|porn|xxx|lewd|onlyfans)(?![\p{L}\p{N}_])""")

    fun isAdultTag(tag: String): Boolean = !WebOfTrustService.showsSensitiveContent && tag.lowercase() in adultTags

    fun isSensitive(note: Note): Boolean {
        if (note.contentWarning != null) return true
        if (note.hashtags.any { it.lowercase() in adultTags }) return true
        val text = note.content.lowercase()
        if (text.contains("🔞")) return true
        return sensitivePattern.containsMatchIn(text)
    }

    private val pinnedStorageKey: String get() = "${PINNED_KEY}_${Session.pubkey ?: "anon"}"

    val pinnedFeeds: List<DiscoverFeed>
        get() {
            refreshPinnedIfNeeded()
            return pinned
        }

    fun refreshPinnedIfNeeded() {
        val owner = Session.pubkey
        if (pinnedLoaded && owner == pinnedOwner) return
        pinnedLoaded = true
        pinnedOwner = owner
        pinned = Json.array(Prefs.string(pinnedStorageKey)).mapNotNull(DiscoverFeed::from)
    }

    fun isPinned(feed: DiscoverFeed): Boolean = pinnedFeeds.any { it.id == feed.id }

    fun togglePin(feed: DiscoverFeed) {
        refreshPinnedIfNeeded()
        pinned = if (pinned.any { it.id == feed.id }) pinned.filter { it.id != feed.id } else pinned + feed
        Prefs.set(pinnedStorageKey, JSONArray(pinned.map { it.toJson() }).toString())
    }
}
