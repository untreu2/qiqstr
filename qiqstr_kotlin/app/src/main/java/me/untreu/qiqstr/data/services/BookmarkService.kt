package me.untreu.qiqstr.data.services

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.qiqstr.core.signEvent
import com.qiqstr.core.sessionNip44Encrypt
import com.qiqstr.core.sessionNip44Decrypt
import com.qiqstr.core.sessionNip04Decrypt
import com.qiqstr.core.dbGetHydratedNotesByIds
import com.qiqstr.core.dbQueryEvents
import com.qiqstr.core.dbSaveEvents
import com.qiqstr.core.fetchEventsByIds
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Note
import org.json.JSONArray
import org.json.JSONObject

object BookmarkService {
    var bookmarkedIds by mutableStateOf<List<String>>(emptyList())
        private set
    var isLoaded by mutableStateOf(false)
        private set
    var isSyncing by mutableStateOf(false)
        private set

    private var generation = 0
    private val publishQueue = Mutex()
    private var pendingPublishes = 0
    private const val D_TAG = "bookmark"

    fun isBookmarked(noteId: String) = noteId in bookmarkedIds

    fun reset() {
        generation += 1
        bookmarkedIds = emptyList()
        isLoaded = false
        isSyncing = false
        pendingPublishes = 0
    }

    suspend fun load() {
        val current = generation
        loadFromDatabase(current)
        sync(current)
    }

    suspend fun refresh() = sync(generation)

    suspend fun toggle(noteId: String) {
        if (isBookmarked(noteId)) remove(noteId) else add(noteId)
    }

    suspend fun add(noteId: String) {
        if (noteId.isEmpty()) return
        if (!isLoaded) loadFromDatabase(generation)
        if (isBookmarked(noteId)) return
        val current = generation
        bookmarkedIds = bookmarkedIds + noteId
        DataBus.listsChanged()
        try {
            enqueuePublish(noteId, adding = true)
        } catch (error: Throwable) {
            if (current != generation) throw error
            bookmarkedIds = bookmarkedIds - noteId
            DataBus.listsChanged()
            throw error
        }
    }

    suspend fun remove(noteId: String) {
        if (!isLoaded) loadFromDatabase(generation)
        val index = bookmarkedIds.indexOf(noteId)
        if (index < 0) return
        val current = generation
        bookmarkedIds = bookmarkedIds.filterIndexed { i, _ -> i != index }
        DataBus.listsChanged()
        try {
            enqueuePublish(noteId, adding = false)
        } catch (error: Throwable) {
            if (current != generation) throw error
            if (noteId !in bookmarkedIds) {
                bookmarkedIds = bookmarkedIds.toMutableList().apply { add(minOf(index, size), noteId) }
            }
            DataBus.listsChanged()
            throw error
        }
    }

    suspend fun notes(): List<Note> {
        val ids = bookmarkedIds
        if (ids.isEmpty()) return emptyList()
        val notes = hydrated(ids).toMutableList()
        val found = notes.map { it.id }.toSet()
        val missing = ids.filter { it !in found }
        if (missing.isNotEmpty()) {
            val events = Json.array(runCatching { fetchEventsByIds(missing, 6u) }.getOrNull())
            if (events.isNotEmpty()) {
                runCatching { dbSaveEvents(JSONArray(events).toString()) }
                SyncService.backgroundFollowUps(events)
            }
            notes += hydrated(missing).filter { it.id !in found }
        }
        return notes.sortedByDescending { it.createdAt }
    }

    private suspend fun hydrated(ids: List<String>): List<Note> {
        val raw = runCatching { dbGetHydratedNotesByIds(ids, Session.mutedPubkeys, Session.mutedWords, Session.pubkey) }.getOrNull()
        return Note.parsed(raw)
    }

    private suspend fun sync(current: Int) {
        val me = Session.pubkey ?: return
        isSyncing = true
        try {
            val events = SyncService.fetchEvents(mapOf("kinds" to listOf(30001), "authors" to listOf(me), "#d" to listOf(D_TAG), "limit" to 1), timeout = 8)
            if (events.isNotEmpty()) runCatching { dbSaveEvents(JSONArray(events).toString()) }
            if (current != generation || pendingPublishes > 0) return
            loadFromDatabase(current)
        } finally {
            if (current == generation) isSyncing = false
        }
    }

    private suspend fun loadFromDatabase(current: Int) {
        val me = Session.pubkey ?: return
        if (!Session.canSign) return
        val filter = Json.string(mapOf("kinds" to listOf(30001), "authors" to listOf(me), "#d" to listOf(D_TAG)))
        val events = Json.array(runCatching { dbQueryEvents(filter, 5u) }.getOrNull())
        if (current != generation) return
        val event = events.maxByOrNull { it.long("created_at") }
        if (event == null) {
            isLoaded = true
            return
        }
        val ids = eventIds(event.tags()).toMutableList()
        val content = event.text("content")
        if (content.isNotEmpty()) {
            decrypt(content, me)?.let(::parseTags)?.let { ids += eventIds(it) }
        }
        bookmarkedIds = ids.distinct()
        isLoaded = true
        DataBus.listsChanged()
    }

    private fun parseTags(raw: String): List<List<String>>? {
        val array = runCatching { JSONArray(raw) }.getOrNull() ?: return null
        return (0 until array.length()).mapNotNull { index ->
            val tag = array.optJSONArray(index) ?: return@mapNotNull null
            (0 until tag.length()).mapNotNull { tag.opt(it) as? String }
        }
    }

    private fun decrypt(content: String, me: String): String? = runCatching {
        if (content.contains("?iv=")) sessionNip04Decrypt(content, me) else sessionNip44Decrypt(content, me)
    }.getOrNull()

    private fun eventIds(tags: List<List<String>>): List<String> =
        tags.filter { it.size > 1 && it[0] == "e" && it[1].isNotEmpty() }.map { it[1] }

    private suspend fun enqueuePublish(noteId: String, adding: Boolean) {
        pendingPublishes += 1
        try {
            publishQueue.withLock { publish(noteId, adding) }
        } finally {
            pendingPublishes = maxOf(0, pendingPublishes - 1)
        }
    }

    private suspend fun publish(noteId: String, adding: Boolean) {
        Session.requireSigner()
        val me = Session.pubkey ?: throw CoreError("Not signed in")
        val base: JSONObject? = SyncService.latestEditableEvent(30001, me, D_TAG)
        val publicTags = (base?.tags() ?: emptyList()).filter { it.firstOrNull() != "d" }.toMutableList()
        var privateTags = mutableListOf<List<String>>()
        val content = base?.text("content") ?: ""
        if (content.isNotEmpty()) {
            val decrypted = decrypt(content, me)?.let(::parseTags) ?: throw CoreError(L("bookmarksUnreadable"))
            privateTags = decrypted.toMutableList()
        }
        val isE: (List<String>) -> Boolean = { it.size > 1 && it[0] == "e" && it[1] == noteId }
        if (adding) {
            if (publicTags.none(isE) && privateTags.none(isE)) privateTags.add(listOf("e", noteId))
        } else {
            publicTags.removeAll(isE)
            privateTags.removeAll(isE)
        }
        if (publicTags.none { it.firstOrNull() == "alt" }) publicTags.add(listOf("alt", "List of bookmarks"))
        val encrypted = sessionNip44Encrypt(Json.string(privateTags), me)
        val json = signEvent(30001u.toUShort(), encrypted, listOf(listOf("d", D_TAG)) + publicTags)
        SyncService.publish(json)
        bookmarkedIds = (eventIds(publicTags) + eventIds(privateTags)).distinct()
        DataBus.listsChanged()
    }
}
