package me.untreu.qiqstr.data.services

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.qiqstr.core.signEvent
import com.qiqstr.core.dbQueryEvents
import com.qiqstr.core.dbSaveEvents
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import org.json.JSONArray
import org.json.JSONObject

object PinnedNotesService {
    var pinnedIds by mutableStateOf<List<String>>(emptyList())
        private set
    var version by mutableIntStateOf(0)
        private set
    private var owner: String? = null
    private var extraTags: List<List<String>> = emptyList()
    private var latestCreatedAt = 0L
    private var generation = 0
    private const val KIND = 10001

    fun isPinned(noteId: String) = noteId in pinnedIds

    fun reset() {
        generation += 1
        owner = null
        pinnedIds = emptyList()
        extraTags = emptyList()
        latestCreatedAt = 0
        version += 1
    }

    suspend fun cachedIds(pubkey: String): List<String> {
        val event = localEvent(pubkey) ?: return if (pubkey == owner) pinnedIds else emptyList()
        if (pubkey == Session.pubkey) adopt(event, pubkey)
        return noteIds(event)
    }

    suspend fun load(pubkey: String): List<String> {
        val generation = this.generation
        val local = localEvent(pubkey)
        val remote = SyncService.fetchEvents(mapOf("kinds" to listOf(KIND), "authors" to listOf(pubkey), "limit" to 1), timeout = 8)
            .filter { it.str("pubkey") == pubkey && it.int("kind") == KIND }
            .maxByOrNull { it.long("created_at") }
        if (remote != null && remote.long("created_at") > (local?.long("created_at") ?: -1)) {
            runCatching { dbSaveEvents(JSONArray(listOf(remote)).toString()) }
        }
        val newest = listOfNotNull(local, remote).maxByOrNull { it.long("created_at") }
        if (generation != this.generation) return newest?.let(::noteIds) ?: emptyList()
        if (pubkey == Session.pubkey) {
            if (newest != null) {
                adopt(newest, pubkey)
            } else if (owner != pubkey) {
                owner = pubkey
                pinnedIds = emptyList()
                version += 1
            }
        }
        return newest?.let(::noteIds) ?: emptyList()
    }

    suspend fun toggle(noteId: String) {
        Session.requireSigner()
        val me = Session.pubkey ?: throw CoreError("Not signed in")
        val base = SyncService.latestEditableEvent(KIND, me)
        if (base != null) {
            adopt(base, me)
        } else if (owner != me || latestCreatedAt == 0L) {
            owner = me
            pinnedIds = emptyList()
            extraTags = emptyList()
        }
        val previous = pinnedIds
        val updated = if (noteId in previous) previous.filter { it != noteId } else previous + noteId
        owner = me
        pinnedIds = updated
        version += 1
        val previousLatest = latestCreatedAt
        latestCreatedAt = maxOf(latestCreatedAt, TimeFormat.now)
        try {
            val tags = updated.map { listOf("e", it) } + extraTags
            val eventJson = signEvent(KIND.toUShort(), "", tags)
            val event = SyncService.publish(eventJson)
            latestCreatedAt = maxOf(latestCreatedAt, event.long("created_at"))
            DataBus.listsChanged()
        } catch (error: Throwable) {
            if (owner == me && pinnedIds == updated) {
                latestCreatedAt = previousLatest
                pinnedIds = previous
                version += 1
            }
            throw error
        }
    }

    private fun adopt(event: JSONObject, pubkey: String) {
        val created = event.long("created_at")
        if (owner == pubkey && created < latestCreatedAt) return
        owner = pubkey
        latestCreatedAt = created
        extraTags = event.tags().filter { !(it.firstOrNull() == "e" && it.size > 1) }
        val ids = noteIds(event)
        if (ids != pinnedIds) {
            pinnedIds = ids
            version += 1
        }
    }

    private suspend fun localEvent(pubkey: String): JSONObject? {
        val filter = Json.string(mapOf("kinds" to listOf(KIND), "authors" to listOf(pubkey)))
        return Json.array(runCatching { dbQueryEvents(filter, 1u) }.getOrNull()).maxByOrNull { it.long("created_at") }
    }

    private fun noteIds(event: JSONObject): List<String> {
        val seen = HashSet<String>()
        return event.tags().mapNotNull { tag ->
            if (tag.size > 1 && tag[0] == "e" && tag[1].length == 64 && seen.add(tag[1])) tag[1] else null
        }
    }
}
