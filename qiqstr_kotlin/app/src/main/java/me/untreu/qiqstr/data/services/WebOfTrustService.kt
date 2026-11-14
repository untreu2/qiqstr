package me.untreu.qiqstr.data.services

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.qiqstr.core.dbGetFollowingList
import com.qiqstr.core.dbQueryEvents
import com.qiqstr.core.dbSaveEvents
import com.qiqstr.core.fetchEvents
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.strings
import org.json.JSONArray
import org.json.JSONObject

data class WebOfTrustSnapshot(
    val owner: String,
    val follows: Set<String>,
    val scores: Map<String, Int>,
    val trustedCount: Int,
    val updatedAt: Long,
)

object WebOfTrustService {
    const val FILTER_NOTIFICATIONS_KEY = "wot_filter_notifications"
    const val FILTER_REPLIES_KEY = "wot_filter_replies"
    const val SHOW_SENSITIVE_CONTENT_KEY = "show_sensitive_content"
    const val ALLOWS_SENSITIVE_CONTENT_TOGGLE = false
    const val MINIMUM_MUTUAL_FOLLOWS = 2
    const val MAX_SAMPLED_FOLLOWS = 1000
    private const val REFRESH_INTERVAL = 6 * 3600 * 1000L

    val filtersNotifications: Boolean get() = Prefs.bool(FILTER_NOTIFICATIONS_KEY, true)
    val filtersReplies: Boolean get() = Prefs.bool(FILTER_REPLIES_KEY, true)
    val showsSensitiveContent: Boolean get() = ALLOWS_SENSITIVE_CONTENT_TOGGLE && Prefs.bool(SHOW_SENSITIVE_CONTENT_KEY)

    var follows by mutableStateOf<Set<String>>(emptySet())
        private set
    var scores by mutableStateOf<Map<String, Int>>(emptyMap())
        private set
    var trustedCount by mutableIntStateOf(0)
        private set
    var isBuilding by mutableStateOf(false)
        private set
    var progress by mutableDoubleStateOf(0.0)
        private set
    var updatedAt by mutableStateOf<Long?>(null)
        private set

    private var owner by mutableStateOf<String?>(null)
    private var generation = 0
    private var buildJob: Job? = null

    val isReady: Boolean get() = owner != null && follows.isNotEmpty() && (updatedAt != null || scores.isNotEmpty())

    fun isTrusted(pubkey: String): Boolean {
        val owner = owner ?: return true
        if (!isReady) return true
        if (pubkey == owner || pubkey in follows || FollowService.isFollowing(pubkey)) return true
        return (scores[pubkey] ?: 0) >= MINIMUM_MUTUAL_FOLLOWS
    }

    fun score(pubkey: String): Int = scores[pubkey] ?: 0

    fun reset() {
        generation += 1
        buildJob?.cancel()
        buildJob = null
        owner = null
        follows = emptySet()
        scores = emptyMap()
        trustedCount = 0
        isBuilding = false
        progress = 0.0
        updatedAt = null
    }

    suspend fun load(pubkey: String) {
        if (owner == pubkey) return
        reset()
        owner = pubkey
        val generation = this.generation
        val cached = WebOfTrustGraph.readCache(pubkey)
        if (cached != null) {
            if (generation != this.generation) return
            apply(cached)
            if (System.currentTimeMillis() - cached.updatedAt < REFRESH_INTERVAL) return
        }
        rebuild()
    }

    fun rebuild() {
        val owner = owner ?: return
        if (isBuilding) return
        val generation = this.generation
        isBuilding = true
        progress = 0.0
        buildJob = App.scope.launch { build(owner, generation) }
    }

    private suspend fun build(owner: String, generation: Int) = coroutineScope {
        var followList = FollowService.following
        if (followList.isEmpty()) followList = runCatching { dbGetFollowingList(owner) }.getOrDefault(emptyList()).toSet()
        followList = followList - owner
        if (generation != this@WebOfTrustService.generation) return@coroutineScope
        follows = followList
        val sample = followList.shuffled().take(MAX_SAMPLED_FOLLOWS)
        val graph = WebOfTrustGraph(owner, followList, MINIMUM_MUTUAL_FOLLOWS)
        val chunks = sample.chunked(100)
        for (chunk in chunks) graph.ingestLocal(chunk)
        if (generation != this@WebOfTrustService.generation || !isActive) return@coroutineScope
        if (chunks.isNotEmpty()) apply(graph.snapshot(), finished = false)
        var done = 0
        for (wave in chunks.chunked(3)) {
            coroutineScope { wave.forEach { chunk -> launch { graph.ingestRemote(chunk) } } }
            if (generation != this@WebOfTrustService.generation || !isActive) return@coroutineScope
            done += wave.size
            progress = done.toDouble() / chunks.size
            apply(graph.snapshot(), finished = false)
        }
        val final = graph.snapshot()
        if (generation != this@WebOfTrustService.generation) return@coroutineScope
        apply(final, finished = true)
        graph.writeCache(final)
    }

    private fun apply(snapshot: WebOfTrustSnapshot, finished: Boolean = true) {
        if (!finished && updatedAt != null && snapshot.trustedCount < trustedCount) return
        if (snapshot.follows.isNotEmpty() || follows.isEmpty()) follows = snapshot.follows
        scores = snapshot.scores
        trustedCount = snapshot.trustedCount
        if (finished) {
            updatedAt = snapshot.updatedAt
            isBuilding = false
            progress = 1.0
        }
    }
}

private class WebOfTrustGraph(private val owner: String, private val follows: Set<String>, private val minimum: Int) {
    private val lock = Any()
    private val index = HashMap<String, Int>()
    private val keys = ArrayList<String>()
    private val latest = HashMap<String, Pair<Long, IntArray>>()

    suspend fun ingestLocal(authors: List<String>) {
        val filter = Json.string(mapOf("kinds" to listOf(3), "authors" to authors))
        val raw = runCatching { dbQueryEvents(filter, (authors.size * 2).toUInt()) }.getOrNull() ?: return
        withContext(Dispatchers.Default) { ingest(Json.array(raw)) }
    }

    suspend fun ingestRemote(authors: List<String>) {
        val filter = Json.string(mapOf("kinds" to listOf(3), "authors" to authors, "limit" to authors.size * 2))
        val raw = runCatching { fetchEvents(filter, 8u) }.getOrNull() ?: return
        val fresh = withContext(Dispatchers.Default) {
            val events = Json.array(raw)
            val fresh = synchronized(lock) {
                events.filter { event ->
                    val author = event.str("pubkey") ?: return@filter false
                    event.long("created_at") > (latest[author]?.first ?: -1)
                }
            }
            ingest(fresh)
            fresh
        }
        if (fresh.isNotEmpty()) runCatching { dbSaveEvents(JSONArray(fresh).toString()) }
    }

    private fun ingest(events: List<JSONObject>) = synchronized(lock) {
        for (event in events) {
            if (event.int("kind") != 3) continue
            val author = event.str("pubkey") ?: continue
            val createdAt = event.long("created_at")
            val existing = latest[author]
            if (existing != null && existing.first >= createdAt) continue
            val seen = HashSet<Int>()
            val contacts = ArrayList<Int>()
            val tags = event.optJSONArray("tags") ?: JSONArray()
            for (i in 0 until tags.length()) {
                val tag = tags.optJSONArray(i) ?: continue
                if (tag.length() <= 1 || tag.opt(0) != "p") continue
                val pubkey = tag.opt(1) as? String ?: continue
                if (pubkey.length != 64 || pubkey == author) continue
                val id = intern(pubkey.lowercase())
                if (seen.add(id)) contacts.add(id)
            }
            latest[author] = createdAt to contacts.toIntArray()
        }
    }

    private fun intern(pubkey: String): Int = index.getOrPut(pubkey) {
        keys.add(pubkey)
        keys.size - 1
    }

    suspend fun snapshot(): WebOfTrustSnapshot = withContext(Dispatchers.Default) {
        synchronized(lock) {
            val counts = IntArray(keys.size)
            for (entry in latest.values) for (id in entry.second) counts[id] += 1
            val scores = HashMap<String, Int>()
            val trusted = HashSet(follows)
            trusted.add(owner)
            for (i in counts.indices) {
                if (counts[i] >= minimum) {
                    scores[keys[i]] = counts[i]
                    trusted.add(keys[i])
                }
            }
            WebOfTrustSnapshot(owner, follows, scores, trusted.size, System.currentTimeMillis())
        }
    }

    suspend fun writeCache(snapshot: WebOfTrustSnapshot) = withContext(Dispatchers.IO) {
        val file = cacheFile(snapshot.owner) ?: return@withContext
        val payload = JSONObject()
            .put("updatedAt", snapshot.updatedAt / 1000.0)
            .put("follows", JSONArray(snapshot.follows.toList()))
            .put("scores", JSONObject(snapshot.scores as Map<*, *>))
            .put("trustedCount", snapshot.trustedCount)
        runCatching {
            file.parentFile?.mkdirs()
            val temp = File(file.parentFile, "${file.name}.tmp")
            temp.writeText(payload.toString())
            temp.renameTo(file)
        }
    }

    companion object {
        suspend fun readCache(owner: String): WebOfTrustSnapshot? = withContext(Dispatchers.IO) {
            val file = cacheFile(owner) ?: return@withContext null
            val json = runCatching { JSONObject(file.readText()) }.getOrNull() ?: return@withContext null
            val scoresJson = json.optJSONObject("scores") ?: JSONObject()
            val scores = scoresJson.keys().asSequence().associateWith { scoresJson.optInt(it) }
            WebOfTrustSnapshot(
                owner = owner,
                follows = json.strings("follows").toSet(),
                scores = scores,
                trustedCount = json.int("trustedCount"),
                updatedAt = (json.optDouble("updatedAt", 0.0) * 1000).toLong(),
            )
        }

        fun cacheFile(owner: String): File? {
            if (owner.length != 64 || !owner.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) return null
            return File(File(App.context.filesDir, "WebOfTrust"), "$owner.json")
        }
    }
}
