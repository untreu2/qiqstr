package me.untreu.qiqstr.data.services

import com.qiqstr.core.fetchEventsMultiFilter
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Note
import org.json.JSONObject

object ExploreSafety {
    private const val LIFETIME = 1800_000L
    private const val REPORT_WINDOW = 180 * 86_400L
    private const val CHUNK = 150

    private val noteReporters = HashMap<String, MutableSet<String>>()
    private val authorReporters = HashMap<String, MutableSet<String>>()
    private val checkedAt = HashMap<String, Long>()

    fun reset() {
        noteReporters.clear()
        authorReporters.clear()
        checkedAt.clear()
    }

    suspend fun screen(notes: List<Note>): List<Note> {
        val candidates = notes.filter { !ExploreService.isSensitive(it) }
        val trust = WebOfTrustService
        val trusted = if (trust.isReady) {
            candidates.filter { note -> trust.isTrusted(note.pubkey) && (note.repostedBy?.let(trust::isTrusted) ?: true) }
        } else {
            candidates
        }
        loadReports(trusted)
        val authorLimit = if (trust.isReady) 2 else 1
        return trusted.filter { note ->
            if (reporters(note = note.id) > 0) return@filter false
            if (reporters(author = note.pubkey) >= authorLimit) return@filter false
            val reposter = note.repostedBy
            !(reposter != null && reporters(author = reposter) >= authorLimit)
        }
    }

    private suspend fun loadReports(noteIds: List<String>, authors: List<String>) {
        val now = System.currentTimeMillis()
        val isFresh: (String) -> Boolean = { key -> checkedAt[key]?.let { now - it < LIFETIME } ?: false }
        val ids = noteIds.filter { !isFresh("e:$it") }.distinct()
        val keys = authors.filter { it.isNotEmpty() && !isFresh("p:$it") }.distinct()
        if (ids.isEmpty() && keys.isEmpty()) return
        val since = now / 1000 - REPORT_WINDOW
        val filters = mutableListOf<Map<String, Any?>>()
        ids.chunked(CHUNK).forEach { filters.add(mapOf("kinds" to listOf(1984), "#e" to it, "since" to since, "limit" to 500)) }
        keys.chunked(CHUNK).forEach { filters.add(mapOf("kinds" to listOf(1984), "#p" to it, "since" to since, "limit" to 500)) }
        val raw = runCatching { fetchEventsMultiFilter(Json.string(filters), 5u) }.getOrNull() ?: return
        ingest(Json.array(raw), ids.toSet(), keys.toSet())
        ids.forEach { checkedAt["e:$it"] = now }
        keys.forEach { checkedAt["p:$it"] = now }
    }

    private suspend fun loadReports(notes: List<Note>) {
        loadReports(notes.map { it.id }, notes.map { it.pubkey } + notes.mapNotNull { it.repostedBy })
    }

    private fun ingest(events: List<JSONObject>, ids: Set<String>, authors: Set<String>) {
        val me = Session.pubkey
        val muted = Session.mutedPubkeys.toSet()
        for (event in events) {
            if (event.int("kind") != 1984) continue
            val reporter = event.str("pubkey") ?: continue
            if (reporter == me || reporter in muted) continue
            for (tag in event.tags()) {
                if (tag.size <= 1) continue
                if (tag[0] == "e" && tag[1] in ids) {
                    noteReporters.getOrPut(tag[1]) { HashSet() }.add(reporter)
                } else if (tag[0] == "p" && tag[1] in authors && tag[1] != reporter) {
                    authorReporters.getOrPut(tag[1]) { HashSet() }.add(reporter)
                }
            }
        }
    }

    private fun reporters(note: String? = null, author: String? = null): Int = when {
        note != null -> noteReporters[note]?.size ?: 0
        author != null -> authorReporters[author]?.size ?: 0
        else -> 0
    }
}
