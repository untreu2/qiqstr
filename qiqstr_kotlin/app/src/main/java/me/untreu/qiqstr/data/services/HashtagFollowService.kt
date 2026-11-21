package me.untreu.qiqstr.data.services

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.qiqstr.core.signEvent
import com.qiqstr.core.dbCountEvents
import com.qiqstr.core.dbQueryEvents
import com.qiqstr.core.dbSaveEvents
import com.qiqstr.core.getConnectedRelayCount
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import org.json.JSONArray
import org.json.JSONObject

object HashtagFollowService {
    private const val KIND = 10015

    var tags by mutableStateOf<List<String>>(emptyList())
        private set
    var isLoaded by mutableStateOf(false)
        private set
    private var intents by mutableStateOf<Map<String, Boolean>>(emptyMap())

    private var confirmed: List<String> = emptyList()
    private var extraTags: List<List<String>> = emptyList()
    private var content = ""
    private var latestCreatedAt = -1L
    private var hasAuthoritative = false
    private var generation = 0
    private val queue = Mutex()

    fun isFollowing(tag: String): Boolean = normalize(tag)?.let { it in tags } ?: false

    fun isPending(tag: String): Boolean = normalize(tag)?.let { intents.containsKey(it) } ?: false

    fun normalize(raw: String): String? {
        val value = raw.trim().dropWhile { it == '#' }.lowercase()
        if (value.isEmpty() || value.length > 64) return null
        if (!value.all { it.isLetter() || it.isDigit() || it == '_' || it == '-' }) return null
        return value
    }

    fun reset() {
        generation += 1
        tags = emptyList()
        intents = emptyMap()
        confirmed = emptyList()
        extraTags = emptyList()
        content = ""
        latestCreatedAt = -1
        hasAuthoritative = false
        isLoaded = false
    }

    suspend fun load() {
        val me = Session.pubkey ?: return
        val generation = this.generation
        val local = localEvent(me)
        if (local != null && generation == this.generation) adopt(local)
        if (generation != this.generation) return
        fetchRemote(me, generation)
        if (generation != this.generation) return
        isLoaded = true
    }

    suspend fun follow(tag: String) = setFollowing(tag, true)

    suspend fun unfollow(tag: String) = setFollowing(tag, false)

    suspend fun toggle(tag: String) = setFollowing(tag, !isFollowing(tag))

    suspend fun recentCount(tag: String, window: Long = 86400): Int? {
        val normalized = normalize(tag) ?: return null
        val filter = mapOf("kinds" to listOf(1), "#t" to listOf(normalized), "since" to TimeFormat.now - window)
        return runCatching { dbCountEvents(Json.string(filter)).toInt() }.getOrNull()
    }

    private suspend fun setFollowing(raw: String, follow: Boolean) {
        val tag = normalize(raw) ?: throw CoreError(L("feedTopicInvalid"))
        Session.requireSigner()
        val me = Session.pubkey ?: throw CoreError(L("privateKeyNotFound"))
        val generation = this.generation
        intents = intents + (tag to follow)
        tags = projected()
        try {
            queue.withLock { commit(tag, follow, me, generation) }
        } catch (error: Throwable) {
            if (generation == this.generation) settle(tag, follow)
            throw error
        }
    }

    private suspend fun commit(tag: String, follow: Boolean, me: String, generation: Int) {
        if (generation != this.generation) return
        val base = SyncService.latestEditableEvent(KIND, me)
        if (generation != this.generation) return
        if (base != null) {
            adopt(base)
        } else {
            confirmed = emptyList()
            content = ""
            extraTags = emptyList()
        }
        hasAuthoritative = true
        val list = confirmed.toMutableList()
        if (follow) {
            if (tag in list) return settle(tag, follow)
            list.add(tag)
        } else {
            if (tag !in list) return settle(tag, follow)
            list.remove(tag)
        }
        val eventJson = signEvent(KIND.toUShort(), content, list.map { listOf("t", it) } + extraTags)
        val event = SyncService.publish(eventJson)
        if (generation != this.generation) return
        latestCreatedAt = maxOf(latestCreatedAt, event.long("created_at"))
        confirmed = list
        settle(tag, follow)
    }

    private fun settle(tag: String, follow: Boolean) {
        if (intents[tag] == follow) intents = intents - tag
        tags = projected()
    }

    private fun projected(): List<String> {
        val list = confirmed.toMutableList()
        for ((tag, follow) in intents.toSortedMap()) {
            if (follow && tag !in list) list.add(tag)
            if (!follow) list.remove(tag)
        }
        return list
    }

    private suspend fun fetchRemote(me: String, generation: Int) {
        val remote = SyncService.fetchEvents(mapOf("kinds" to listOf(KIND), "authors" to listOf(me), "limit" to 1), timeout = 8)
            .filter { it.str("pubkey") == me && it.int("kind") == KIND }
            .maxByOrNull { it.long("created_at") }
        if (generation != this.generation) return
        if (remote != null) {
            if (remote.long("created_at") > latestCreatedAt) {
                runCatching { dbSaveEvents(JSONArray(listOf(remote)).toString()) }
                if (generation != this.generation) return
            }
            adopt(remote)
            return
        }
        if (hasAuthoritative) return
        val connected = runCatching { getConnectedRelayCount() }.getOrDefault(0u)
        if (generation != this.generation) return
        if (connected > 0u) hasAuthoritative = true
    }

    private fun adopt(event: JSONObject) {
        val created = event.long("created_at")
        if (created < latestCreatedAt) return
        latestCreatedAt = created
        hasAuthoritative = true
        content = event.text("content")
        extraTags = event.tags().filter { !(it.firstOrNull() == "t" && it.size > 1 && normalize(it[1]) != null) }
        val seen = HashSet<String>()
        confirmed = event.tags().mapNotNull { tag ->
            if (tag.size <= 1 || tag[0] != "t") return@mapNotNull null
            val value = normalize(tag[1]) ?: return@mapNotNull null
            if (seen.add(value)) value else null
        }
        tags = projected()
    }

    private suspend fun localEvent(pubkey: String): JSONObject? {
        val filter = Json.string(mapOf("kinds" to listOf(KIND), "authors" to listOf(pubkey)))
        return Json.array(runCatching { dbQueryEvents(filter, 1u) }.getOrNull())
            .filter { it.str("pubkey") == pubkey }
            .maxByOrNull { it.long("created_at") }
    }
}
