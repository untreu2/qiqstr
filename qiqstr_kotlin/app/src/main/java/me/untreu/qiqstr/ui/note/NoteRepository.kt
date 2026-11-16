package me.untreu.qiqstr.ui.note

import androidx.compose.runtime.Immutable
import com.qiqstr.core.dbCountEvents
import com.qiqstr.core.dbEventsExistBatch
import com.qiqstr.core.dbGetFollowSets
import com.qiqstr.core.dbGetHydratedArticleByNaddr
import com.qiqstr.core.dbGetHydratedFeedNotesSorted
import com.qiqstr.core.dbGetHydratedHashtagNotes
import com.qiqstr.core.dbGetHydratedNote
import com.qiqstr.core.dbGetHydratedNotesByIds
import com.qiqstr.core.dbQueryEvents
import com.qiqstr.core.dbSaveEvents
import com.qiqstr.core.dbSearchProfiles
import com.qiqstr.core.extractEmbeddedIdsBatchTyped
import com.qiqstr.core.fetchEventsByIds
import com.qiqstr.core.fetchFullThread
import com.qiqstr.core.fetchFullThreadLocal
import com.qiqstr.core.parseNoteContent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.objects
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.strings
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Article
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.ParsedContent
import me.untreu.qiqstr.domain.Profile
import org.json.JSONArray
import org.json.JSONObject

enum class FeedSortMode(val raw: String) {
    LATEST("latest"), MOST_INTERACTED("most_interacted");

    val title: String get() = if (this == LATEST) L("feedSortLatest") else L("feedSortMostInteracted")

    companion object {
        fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: LATEST
    }
}

@Immutable
data class FeedFollowSet(val pubkey: String, val dTag: String, val title: String, val pubkeys: List<String>) {
    val id: String get() = "$pubkey:$dTag"

    companion object {
        fun from(j: JSONObject): FeedFollowSet? {
            val pubkey = j.str("pubkey") ?: return null
            val dTag = j.str("dTag") ?: return null
            return FeedFollowSet(pubkey, dTag, j.str("title") ?: dTag, j.strings("pubkeys"))
        }
    }
}

@Immutable
data class NoteThreadData(
    val rootNote: Note,
    val chain: List<Note>,
    val children: Map<String, List<Note>>,
    val totalReplies: Int,
) {
    val focused: Note get() = chain.lastOrNull() ?: rootNote
    val allNotes: List<Note> get() = chain + children.values.flatten()

    companion object {
        fun from(j: JSONObject): NoteThreadData? {
            val root = j.optJSONObject("rootNote") ?: return null
            val rootNote = Note.from(root)
            if (rootNote.id.isEmpty()) return null
            val chain = j.objects("chainNotes").map(Note::from).filter { it.id.isNotEmpty() }
            val children = HashMap<String, List<Note>>()
            j.optJSONObject("childrenMap")?.let { map ->
                for (key in map.keys()) {
                    val array = map.optJSONArray(key) ?: continue
                    children[key] = (0 until array.length()).mapNotNull { array.optJSONObject(it) }
                        .map(Note::from).filter { it.id.isNotEmpty() && !it.isRepost }
                }
            }
            return NoteThreadData(rootNote, chain.ifEmpty { listOf(rootNote) }, children, j.int("totalReplies"))
        }
    }
}

object NoteRepository {
    private val me: String? get() = Session.pubkey
    private val mutedPubkeys: List<String> get() = Session.mutedPubkeys
    private val mutedWords: List<String> get() = Session.mutedWords

    suspend fun feed(authors: List<String>?, limit: Int, sort: FeedSortMode, showReplies: Boolean = false): List<Note> {
        val me = me ?: return emptyList()
        val raw = runCatching { dbGetHydratedFeedNotesSorted(me, authors, limit.toUInt(), !showReplies, me, sort.raw) }.getOrNull()
        return Note.parsed(raw)
    }

    suspend fun hashtag(tag: String, limit: Int): List<Note> {
        val raw = runCatching { dbGetHydratedHashtagNotes(tag.lowercase(), limit.toUInt(), mutedPubkeys, mutedWords, me) }.getOrNull()
        return Note.parsed(raw)
    }

    suspend fun note(id: String): Note? {
        val obj = Json.obj(runCatching { dbGetHydratedNote(id, me) }.getOrNull()) ?: return null
        return Note.from(obj).takeIf { it.id.isNotEmpty() }
    }

    suspend fun notes(ids: List<String>): List<Note> {
        if (ids.isEmpty()) return emptyList()
        return Note.parsed(runCatching { dbGetHydratedNotesByIds(ids, mutedPubkeys, mutedWords, me) }.getOrNull())
    }

    suspend fun ensureNote(id: String): Note? {
        note(id)?.let { return it }
        SyncService.syncNote(id)
        return note(id)
    }

    suspend fun threadLocal(noteId: String): NoteThreadData? {
        val raw = runCatching { fetchFullThreadLocal(noteId, me, mutedPubkeys, mutedWords) }.getOrNull() ?: return null
        return withContext(Dispatchers.Default) { Json.obj(raw)?.let(NoteThreadData::from) }
    }

    suspend fun threadNetwork(noteId: String): NoteThreadData? {
        val raw = fetchFullThread(noteId, me, mutedPubkeys, mutedWords)
        return withContext(Dispatchers.Default) { Json.obj(raw)?.let(NoteThreadData::from) }
    }

    suspend fun quoteCount(noteId: String): Int =
        runCatching { dbCountEvents(Json.string(mapOf("kinds" to listOf(1), "#q" to listOf(noteId)))).toInt() }.getOrDefault(0)

    suspend fun quotes(noteId: String): List<Note> = coroutineScope {
        val tagged = async { Json.array(runCatching { dbQueryEvents(Json.string(mapOf("kinds" to listOf(1), "#q" to listOf(noteId))), 300u) }.getOrNull()) }
        val referenced = async { Json.array(runCatching { dbQueryEvents(Json.string(mapOf("kinds" to listOf(1), "#e" to listOf(noteId))), 500u) }.getOrNull()) }
        val mentionEvents = referenced.await().filter { event ->
            event.tags().any { it.size >= 4 && it[0] == "e" && it[1] == noteId && it[3] == "mention" }
        }
        val ids = (tagged.await() + mentionEvents).mapNotNull { it.str("id") }.distinct()
        notes(ids).sortedByDescending { it.createdAt }
    }

    suspend fun fetchQuotesFromRelays(noteId: String) {
        val events = coroutineScope {
            val q = async { SyncService.fetchEvents(mapOf("kinds" to listOf(1), "#q" to listOf(noteId), "limit" to 200)) }
            val e = async { SyncService.fetchEvents(mapOf("kinds" to listOf(1), "#e" to listOf(noteId), "limit" to 300)) }
            q.await() + e.await()
        }
        if (events.isNotEmpty()) {
            runCatching { dbSaveEvents(JSONArray(events).toString()) }
            SyncService.fetchMissingProfiles(events.mapNotNull { it.str("pubkey") }.distinct())
        }
    }

    suspend fun fetchOlder(authors: List<String>, until: Long): Int {
        if (authors.isEmpty() || until <= 0) return 0
        val events = SyncService.fetchEvents(mapOf("authors" to authors, "kinds" to listOf(1, 6), "until" to until, "limit" to 100), timeout = 10)
        if (events.isNotEmpty()) {
            runCatching { dbSaveEvents(JSONArray(events).toString()) }
            SyncService.backgroundFollowUps(events)
        }
        return events.size
    }

    suspend fun fetchOlderHashtag(tag: String, until: Long): Int {
        if (until <= 0) return 0
        val events = SyncService.fetchEvents(mapOf("kinds" to listOf(1), "#t" to listOf(tag.lowercase()), "until" to until, "limit" to 100), timeout = 10)
        if (events.isNotEmpty()) {
            runCatching { dbSaveEvents(JSONArray(events).toString()) }
            SyncService.backgroundFollowUps(events)
        }
        return events.size
    }

    suspend fun following(): List<String> {
        val me = me ?: return emptyList()
        return SyncService.followingList(me)
    }

    suspend fun followSets(authors: List<String>, limit: Int): List<FeedFollowSet> {
        if (authors.isEmpty()) return emptyList()
        val raw = runCatching { dbGetFollowSets(authors, limit.toUInt(), listOf("mute", "Chat-Friends")) }.getOrNull()
        return Json.array(raw).mapNotNull(FeedFollowSet::from)
    }

    suspend fun searchProfiles(query: String, limit: Int = 8): List<Profile> =
        Json.array(runCatching { dbSearchProfiles(query, limit.toUInt()) }.getOrNull()).map { Profile.from(it) }.filter { it.pubkey.isNotEmpty() }

    suspend fun article(naddr: String): Article? {
        val tlv = Nip19.decodeTLV(naddr) ?: return null
        val pubkey = tlv.str("pubkey") ?: return null
        val identifier = tlv.text("identifier")
        Json.obj(runCatching { dbGetHydratedArticleByNaddr(pubkey, identifier) }.getOrNull())?.let { return Article.from(it) }
        val events = SyncService.fetchEvents(mapOf("kinds" to listOf(30023), "authors" to listOf(pubkey), "#d" to listOf(identifier), "limit" to 1), timeout = 6)
        if (events.isEmpty()) return null
        runCatching { dbSaveEvents(JSONArray(events).toString()) }
        return Json.obj(runCatching { dbGetHydratedArticleByNaddr(pubkey, identifier) }.getOrNull())?.let { Article.from(it) }
    }

    fun prefetchEmbedded(notes: List<Note>) {
        val contents = notes.map { it.content }.filter { it.contains("nostr:") || it.contains("note1") || it.contains("naddr1") }
        if (contents.isEmpty()) return
        App.scope.launch(Dispatchers.Default) {
            val embedded = runCatching { extractEmbeddedIdsBatchTyped(contents) }.getOrNull() ?: return@launch
            if (embedded.eventIds.isNotEmpty()) {
                val ids = embedded.eventIds
                val exists = runCatching { dbEventsExistBatch(ids) }.getOrDefault(emptyList())
                val missing = ids.filterIndexed { index, _ -> exists.getOrNull(index) != true }
                if (missing.isNotEmpty()) {
                    runCatching { fetchEventsByIds(missing.take(60), 8u) }
                    withContext(Dispatchers.Main) { DataBus.feedChanged() }
                }
            }
            if (embedded.addresses.isNotEmpty()) {
                val filter = mapOf("kinds" to listOf(30023), "authors" to embedded.addresses, "limit" to 50)
                runCatching { com.qiqstr.core.fetchEvents(Json.string(filter), 8u) }
            }
        }
    }

    fun parse(content: String): ParsedContent =
        ParsedContent.from(Json.obj(runCatching { parseNoteContent(content) }.getOrNull()) ?: JSONObject())
}
