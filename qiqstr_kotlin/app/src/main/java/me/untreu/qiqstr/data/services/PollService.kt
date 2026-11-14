package me.untreu.qiqstr.data.services

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.qiqstr.core.dbGetEvent
import com.qiqstr.core.dbQueryEvents
import com.qiqstr.core.dbSaveEvents
import com.qiqstr.core.fetchEventsFromRelays
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import org.json.JSONArray
import org.json.JSONObject

@Immutable
data class NotePoll(
    val id: String,
    val options: List<Option>,
    val multiple: Boolean,
    val endsAt: Long?,
    val relays: List<String>,
) {
    @Immutable
    data class Option(val id: String, val label: String)

    fun isEnded(now: Long = TimeFormat.now): Boolean = endsAt?.let { now >= it } ?: false

    companion object {
        const val KIND = 1068
        const val RESPONSE_KIND = 1018

        fun from(id: String, tags: List<List<String>>): NotePoll? {
            val options = mutableListOf<Option>()
            for (tag in tags) {
                if (tag.size > 2 && tag[0] == "option" && tag[1].isNotEmpty() && options.none { it.id == tag[1] }) {
                    options.add(Option(tag[1], tag[2]))
                }
            }
            if (options.size < 2) return null
            val type = tags.firstOrNull { it.size > 1 && it[0] == "polltype" }?.get(1)?.lowercase() ?: ""
            return NotePoll(
                id = id,
                options = options,
                multiple = type.startsWith("multiple"),
                endsAt = tags.firstOrNull { it.size > 1 && it[0] == "endsAt" }?.get(1)?.toLongOrNull(),
                relays = tags.filter { it.size > 1 && it[0] == "relay" && it[1].startsWith("wss://") }.map { it[1] },
            )
        }
    }
}

@Immutable
data class PollTally(
    val counts: Map<String, Int> = emptyMap(),
    val voters: Int = 0,
    val mine: Set<String> = emptySet(),
) {
    fun share(optionId: String): Double = if (voters <= 0) 0.0 else (counts[optionId] ?: 0).toDouble() / voters
}

object PollService {
    val tallies = mutableStateMapOf<String, PollTally>()
    var invalid by mutableStateOf<Set<String>>(emptySet())
        private set
    private val fetchedAt = HashMap<String, Long>()

    fun tally(pollId: String): PollTally? = tallies[pollId]

    fun reset() {
        tallies.clear()
        invalid = emptySet()
        fetchedAt.clear()
    }

    suspend fun load(poll: NotePoll, force: Boolean = false) {
        val stored = Json.obj(runCatching { dbGetEvent(poll.id) }.getOrNull())
        if (stored != null && stored.int("kind") != NotePoll.KIND) {
            invalid = invalid + poll.id
            return
        }
        recount(poll)
        val last = fetchedAt[poll.id]
        if (!force && last != null && System.currentTimeMillis() - last < 60_000) return
        fetchedAt[poll.id] = System.currentTimeMillis()
        val filter = mapOf("kinds" to listOf(NotePoll.RESPONSE_KIND), "#e" to listOf(poll.id), "limit" to 1000)
        val events = if (poll.relays.isEmpty()) {
            SyncService.fetchEvents(filter, timeout = 8)
        } else {
            coroutineScope {
                val hinted = async { Json.array(runCatching { fetchEventsFromRelays(Json.string(filter), poll.relays, 8u) }.getOrNull()) }
                val general = async { SyncService.fetchEvents(filter, timeout = 8) }
                hinted.await() + general.await()
            }
        }
        if (events.isNotEmpty()) runCatching { dbSaveEvents(JSONArray(events).toString()) }
        recount(poll)
    }

    private suspend fun recount(poll: NotePoll) {
        val filter = Json.string(mapOf("kinds" to listOf(NotePoll.RESPONSE_KIND), "#e" to listOf(poll.id)))
        val events = Json.array(runCatching { dbQueryEvents(filter, 5000u) }.getOrNull())
        tallies[poll.id] = count(events, poll, Session.pubkey)
    }

    suspend fun vote(poll: NotePoll, optionIds: List<String>) {
        val ids = if (poll.multiple) optionIds else optionIds.take(1)
        if (ids.isEmpty() || poll.isEnded()) return
        InteractionService.publishPollResponse(poll.id, ids, poll.relays)
        recount(poll)
    }

    fun count(events: List<JSONObject>, poll: NotePoll, me: String?): PollTally {
        val valid = poll.options.map { it.id }.toSet()
        val latest = HashMap<String, Pair<Long, List<String>>>()
        for (event in events) {
            if (event.int("kind") != NotePoll.RESPONSE_KIND) continue
            val author = event.str("pubkey") ?: continue
            val createdAt = event.long("created_at")
            if (poll.endsAt != null && createdAt > poll.endsAt) continue
            val existing = latest[author]
            if (existing != null && existing.first >= createdAt) continue
            var choices = mutableListOf<String>()
            for (tag in event.tags()) {
                if (tag.size > 1 && tag[0] == "response" && tag[1] in valid && tag[1] !in choices) choices.add(tag[1])
            }
            if (!poll.multiple) choices = choices.take(1).toMutableList()
            if (choices.isEmpty()) continue
            latest[author] = createdAt to choices
        }
        val counts = HashMap<String, Int>()
        var mine = emptySet<String>()
        for ((author, entry) in latest) {
            for (choice in entry.second) counts[choice] = (counts[choice] ?: 0) + 1
            if (author == me) mine = entry.second.toSet()
        }
        return PollTally(counts, latest.size, mine)
    }
}
