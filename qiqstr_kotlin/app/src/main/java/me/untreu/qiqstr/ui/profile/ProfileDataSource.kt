package me.untreu.qiqstr.ui.profile

import com.qiqstr.core.createProfileEvent
import com.qiqstr.core.dbCalculateFollowScore
import com.qiqstr.core.dbGetFollowingList
import com.qiqstr.core.dbGetHydratedNotesByIds
import com.qiqstr.core.dbGetHydratedProfileNotes
import com.qiqstr.core.dbGetHydratedProfileReplies
import com.qiqstr.core.dbGetHydratedReactionNotes
import com.qiqstr.core.dbGetProfile
import com.qiqstr.core.dbQueryEvents
import com.qiqstr.core.dbSaveEvents
import com.qiqstr.core.fetchFollowerCounts
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.strings
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile
import org.json.JSONArray
import org.json.JSONObject

data class FollowScore(val count: Int, val avatarUrls: List<String>)

object ProfileDataSource {
    const val PAGE_SIZE = 30

    suspend fun profile(pubkey: String): Profile? {
        val obj = Json.obj(runCatching { dbGetProfile(pubkey) }.getOrNull()) ?: return null
        return Profile.from(obj, pubkey)
    }

    suspend fun rawMetadata(pubkey: String): JSONObject {
        val filter = Json.string(mapOf("kinds" to listOf(0), "authors" to listOf(pubkey)))
        val events = Json.array(runCatching { dbQueryEvents(filter, 1u) }.getOrNull())
        events.maxByOrNull { it.long("created_at") }?.let { newest -> Json.obj(newest.text("content"))?.let { return it } }
        return Json.obj(runCatching { dbGetProfile(pubkey) }.getOrNull()) ?: JSONObject()
    }

    suspend fun notes(pubkey: String, limit: Int, until: Long? = null): List<Note> = Note.parsed(runCatching {
        dbGetHydratedProfileNotes(pubkey, limit.toUInt(), mutedPubkeys(pubkey), Session.mutedWords, true, Session.pubkey, until)
    }.getOrNull())

    suspend fun replies(pubkey: String, limit: Int, until: Long? = null): List<Note> = Note.parsed(runCatching {
        dbGetHydratedProfileReplies(pubkey, limit.toUInt(), mutedPubkeys(pubkey), Session.mutedWords, Session.pubkey, until)
    }.getOrNull())

    suspend fun likes(pubkey: String, reactionLimit: Int): List<Note> = Note.parsed(runCatching {
        dbGetHydratedReactionNotes(pubkey, reactionLimit.toUInt(), Session.mutedPubkeys, Session.mutedWords, Session.pubkey)
    }.getOrNull())

    suspend fun notes(ids: List<String>, owner: String? = null): List<Note> {
        if (ids.isEmpty()) return emptyList()
        return Note.parsed(runCatching {
            dbGetHydratedNotesByIds(ids, Session.mutedPubkeys.filter { it != owner }, Session.mutedWords, Session.pubkey)
        }.getOrNull())
    }

    suspend fun fetchMissingNotes(ids: List<String>): Boolean {
        val wanted = ids.distinct().take(100)
        if (wanted.isEmpty()) return false
        val events = SyncService.fetchEvents(mapOf("ids" to wanted), timeout = 8)
        if (events.isEmpty()) return false
        runCatching { dbSaveEvents(JSONArray(events).toString()) }
        SyncService.fetchMissingProfiles(events.mapNotNull { it.str("pubkey") }.distinct())
        return true
    }

    suspend fun likedNoteIds(pubkey: String, reactionLimit: Int): List<String> {
        val filter = Json.string(mapOf("kinds" to listOf(7), "authors" to listOf(pubkey)))
        val reactions = Json.array(runCatching { dbQueryEvents(filter, reactionLimit.toUInt()) }.getOrNull())
        val seen = HashSet<String>()
        return reactions.mapNotNull { event ->
            val tag = event.tags().firstOrNull { it.firstOrNull() == "e" && it.size > 1 } ?: return@mapNotNull null
            if (seen.add(tag[1])) tag[1] else null
        }
    }

    suspend fun syncOlderReactions(pubkey: String, before: Long?): Int {
        val filter = mutableMapOf<String, Any?>("kinds" to listOf(7), "authors" to listOf(pubkey), "limit" to 100)
        if (before != null) filter["until"] = before - 1
        val events = SyncService.fetchEvents(filter, timeout = 8)
        if (events.isNotEmpty()) runCatching { dbSaveEvents(JSONArray(events).toString()) }
        return events.size
    }

    suspend fun oldestReactionTimestamp(pubkey: String, reactionLimit: Int): Long? {
        val filter = Json.string(mapOf("kinds" to listOf(7), "authors" to listOf(pubkey)))
        return Json.array(runCatching { dbQueryEvents(filter, reactionLimit.toUInt()) }.getOrNull())
            .map { it.long("created_at") }.filter { it > 0 }.minOrNull()
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

    suspend fun following(pubkey: String): List<String> = runCatching { dbGetFollowingList(pubkey) }.getOrDefault(emptyList())

    suspend fun followerCount(pubkey: String): Int? {
        val map = Json.obj(runCatching { fetchFollowerCounts(listOf(pubkey)) }.getOrNull()) ?: return null
        return (map.opt(pubkey) as? Number)?.toInt() ?: 0
    }

    suspend fun followScore(target: String): FollowScore? {
        val me = Session.pubkey ?: return null
        if (me == target) return null
        val obj = Json.obj(runCatching { dbCalculateFollowScore(me, target) }.getOrNull()) ?: return null
        val count = obj.int("count")
        if (count <= 0) return null
        return FollowScore(count, obj.strings("avatarUrls"))
    }

    suspend fun mutualFollowers(target: String): List<String> {
        val me = Session.pubkey ?: return emptyList()
        if (me == target) return emptyList()
        val mine = following(me).filter { it != me && it != target }
        if (mine.isEmpty()) return emptyList()
        val matched = HashSet<String>()
        for (chunk in mine.chunked(500)) {
            val filter = Json.string(mapOf("kinds" to listOf(3), "authors" to chunk, "#p" to listOf(target)))
            Json.array(runCatching { dbQueryEvents(filter, chunk.size.toUInt()) }.getOrNull()).forEach { event ->
                event.str("pubkey")?.let(matched::add)
            }
        }
        if (matched.isEmpty()) {
            for (pubkey in mine) if (target in following(pubkey)) matched.add(pubkey)
        }
        return mine.filter { it in matched }
    }

    suspend fun followers(pubkey: String): List<String> {
        val events = SyncService.fetchEvents(mapOf("kinds" to listOf(3), "#p" to listOf(pubkey), "limit" to 500), timeout = 12)
        val newestByAuthor = HashMap<String, Long>()
        for (event in events) {
            val author = event.str("pubkey") ?: continue
            if (author == pubkey) continue
            if (event.tags().none { it.size > 1 && it[0] == "p" && it[1] == pubkey }) continue
            newestByAuthor[author] = maxOf(newestByAuthor[author] ?: 0, event.long("created_at"))
        }
        return newestByAuthor.entries.sortedByDescending { it.value }.map { it.key }
    }

    suspend fun publishMetadata(metadata: JSONObject) {
        val key = Session.privateKey ?: throw CoreError("Not signed in")
        val eventJson = createProfileEvent(metadata.toString(), key)
        SyncService.publish(eventJson)
    }

    private fun mutedPubkeys(excluding: String): List<String> = Session.mutedPubkeys.filter { it != excluding }
}
