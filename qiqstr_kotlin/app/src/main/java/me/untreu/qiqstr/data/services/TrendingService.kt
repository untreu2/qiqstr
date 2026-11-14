package me.untreu.qiqstr.data.services

import com.qiqstr.core.dbSaveEvents
import com.qiqstr.core.fetchEventsFromRelays
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Note
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject

data class TrendingSnapshot(val noteIds: List<String>, val hashtags: List<String>)

object TrendingService {
    const val TTL = 600_000L
    private const val NOTE_LIMIT = 40
    private const val HASHTAG_LIMIT = 16
    private val fallbackRelays = listOf("wss://nostr.wine", "wss://relay.damus.io", "wss://relay.primal.net", "wss://nos.lol")
    private val httpClient by lazy { PrimalCache.client.newBuilder().callTimeout(10, TimeUnit.SECONDS).build() }

    private var noteIds: List<String> = emptyList()
    private var notesLoadedAt: Long? = null
    private var hashtags: List<String> = emptyList()
    private var hashtagsLoadedAt: Long? = null
    private var inflightNotes: Deferred<List<String>>? = null
    private var inflightHashtags: Deferred<List<String>>? = null
    private var poolIds: List<String> = emptyList()
    private var poolLoadedAt: Long? = null
    private var inflightPool: Deferred<List<String>>? = null

    fun cachedNoteIds(): List<String> = noteIds
    fun cachedHashtags(): List<String> = hashtags

    private fun fresh(loadedAt: Long?) = loadedAt != null && System.currentTimeMillis() - loadedAt < TTL

    suspend fun trendingNoteIds(force: Boolean = false): List<String> {
        if (!force && fresh(notesLoadedAt) && noteIds.isNotEmpty()) return noteIds
        inflightNotes?.let { return it.await() }
        val task = App.scope.async { fetchTrendingNotes() }
        inflightNotes = task
        val ids = task.await()
        inflightNotes = null
        if (ids.isNotEmpty()) {
            noteIds = ids
            notesLoadedAt = System.currentTimeMillis()
        }
        return noteIds
    }

    suspend fun explorePool(force: Boolean = false): List<String> {
        if (!force && fresh(poolLoadedAt) && poolIds.isNotEmpty()) return poolIds
        inflightPool?.let { return it.await() }
        val task = App.scope.async { fetchExplorePool() }
        inflightPool = task
        val ids = task.await()
        inflightPool = null
        if (ids.isNotEmpty()) {
            poolIds = ids
            poolLoadedAt = System.currentTimeMillis()
            extendPool()
        }
        return poolIds
    }

    private fun extendPool() {
        App.scope.launch {
            val extra = fetchExtendedPool()
            if (extra.isEmpty()) return@launch
            val seen = poolIds.toHashSet()
            val added = extra.filter { seen.add(it) }
            if (added.isEmpty()) return@launch
            poolIds = poolIds + added
            DataBus.feedChanged()
        }
    }

    suspend fun trendingHashtags(force: Boolean = false): List<String> {
        if (!force && fresh(hashtagsLoadedAt) && hashtags.isNotEmpty()) return hashtags
        inflightHashtags?.let { return it.await() }
        val task = App.scope.async { fetchTrendingHashtags() }
        inflightHashtags = task
        val tags = task.await().filter { !ExploreService.isAdultTag(it) }
        inflightHashtags = null
        if (tags.isNotEmpty()) {
            hashtags = tags
            hashtagsLoadedAt = System.currentTimeMillis()
        }
        return hashtags
    }

    suspend fun hydratedNotes(ids: List<String>): List<Note> = SearchService.notes(ids)

    private suspend fun fetchTrendingNotes(): List<String> {
        val primal = PrimalCache.request("explore_global_trending_24h", mapOf("limit" to NOTE_LIMIT), 10)
        val ids = storeTrending(primal)
        if (!ids.isNullOrEmpty()) return ids.take(NOTE_LIMIT)
        return nostrWineTrending()
    }

    private suspend fun fetchExplorePool(): List<String> = coroutineScope {
        val trending = async { primalPool("explore_global_trending_24h") }
        val zapped = async { primalPool("explore_global_mostzapped_4h") }
        val primary = merged(listOf(trending.await(), zapped.await()))
        primary.ifEmpty { nostrWineTrending() }
    }

    private suspend fun fetchExtendedPool(): List<String> = coroutineScope {
        val reactions = async { nostrWineTrending("reactions", 100) }
        val reposts = async { nostrWineTrending("reposts", 100) }
        val replies = async { nostrWineTrending("replies", 100) }
        merged(listOf(reactions.await(), reposts.await(), replies.await()))
    }

    private fun merged(sources: List<List<String>>): List<String> {
        val seen = HashSet<String>()
        return sources.flatten().filter { seen.add(it) }
    }

    private suspend fun primalPool(name: String): List<String> =
        storeTrending(PrimalCache.request(name, mapOf("limit" to 100), 10)) ?: emptyList()

    private suspend fun storeTrending(events: List<JSONObject>): List<String>? {
        val notes = events.filter { it.int("kind") == 1 && it.str("id") != null && it.str("sig") != null }
        if (notes.isEmpty()) return null
        val profiles = events.filter { it.int("kind") == 0 && it.str("sig") != null }
        runCatching { dbSaveEvents(JSONArray(notes + profiles).toString()) }
        val order = PrimalCache.order(events)
        val available = notes.mapNotNull { it.str("id") }.toSet()
        val ids = order.filter { it in available }.toMutableList()
        val seen = ids.toHashSet()
        ids += notes.mapNotNull { it.str("id") }.filter { seen.add(it) }
        fetchProfiles(notes)
        return ids
    }

    private suspend fun nostrWineTrending(order: String = "reactions", limit: Int = NOTE_LIMIT): List<String> {
        val url = "https://api.nostr.wine/trending?order=$order&hours=24&limit=$limit"
        val body = withContext(Dispatchers.IO) {
            runCatching {
                httpClient.newCall(Request.Builder().url(url).build()).execute().use { response ->
                    if (response.code == 200) response.body?.string() else null
                }
            }.getOrNull()
        } ?: return emptyList()
        val ids = Json.array(body).mapNotNull { it.str("event_id") }
        if (ids.isEmpty()) return emptyList()
        val raw = runCatching {
            fetchEventsFromRelays(Json.string(mapOf("ids" to ids, "kinds" to listOf(1))), fallbackRelays, 8u)
        }.getOrNull()
        val events = Json.array(raw)
        if (events.isEmpty()) return emptyList()
        runCatching { dbSaveEvents(JSONArray(events).toString()) }
        fetchProfiles(events)
        val found = events.mapNotNull { it.str("id") }.toSet()
        return ids.filter { it in found }
    }

    private suspend fun fetchTrendingHashtags(): List<String> {
        val events = PrimalCache.request("trending_hashtags_4h", emptyMap(), 12)
        val rows = events.firstOrNull { it.int("kind") == 10000116 }?.let { Json.any(it.text("content")) as? JSONArray } ?: return emptyList()
        val seen = HashSet<String>()
        return (0 until rows.length()).mapNotNull { index ->
            val tag = (rows.optJSONArray(index)?.opt(0) as? String)?.lowercase() ?: return@mapNotNull null
            if (SearchService.hashtag(tag) != tag || !seen.add(tag)) null else tag
        }.take(HASHTAG_LIMIT)
    }

    fun hashtags(notes: List<Note>, limit: Int = 12): List<String> {
        val counts = HashMap<String, Int>()
        for (note in notes) {
            for (tag in note.hashtags.map { it.lowercase() }.toSet()) {
                if (SearchService.hashtag(tag) == tag && !ExploreService.isAdultTag(tag)) counts[tag] = (counts[tag] ?: 0) + 1
            }
        }
        return counts.entries.sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key }).take(limit).map { it.key }
    }

    private fun fetchProfiles(events: List<JSONObject>) {
        val pubkeys = SearchService.pubkeys(events)
        if (pubkeys.isNotEmpty()) SyncService.fetchMissingProfiles(pubkeys)
    }
}
