package me.untreu.qiqstr.data.services

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.qiqstr.core.createSignedEvent
import com.qiqstr.core.dbDeleteEventsByIds
import com.qiqstr.core.dbGetFollowSets
import com.qiqstr.core.dbSaveEvents
import java.util.UUID
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.strings
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import org.json.JSONArray
import org.json.JSONObject

@Immutable
data class FollowSet(
    val eventId: String,
    val pubkey: String,
    val dTag: String,
    val title: String = "",
    val description: String = "",
    val image: String = "",
    val pubkeys: List<String> = emptyList(),
    val createdAt: Long = 0,
) {
    val id: String get() = "$pubkey:$dTag"
    val displayTitle: String get() = title.ifEmpty { dTag }
    val coordinate: String get() = "30000:$pubkey:$dTag"

    companion object {
        fun from(j: JSONObject) = FollowSet(
            eventId = j.str("id") ?: "",
            pubkey = j.str("pubkey") ?: "",
            dTag = j.str("dTag") ?: "",
            title = j.str("title") ?: "",
            description = j.str("description") ?: "",
            image = j.str("image") ?: "",
            pubkeys = j.strings("pubkeys"),
            createdAt = j.long("createdAt"),
        )

        fun fromEvent(event: JSONObject): FollowSet? {
            var dTag = ""
            var title = ""
            var description = ""
            var image = ""
            val members = mutableListOf<String>()
            for (tag in event.tags()) {
                if (tag.size <= 1) continue
                when (tag[0]) {
                    "d" -> dTag = tag[1]
                    "title" -> title = tag[1]
                    "description" -> description = tag[1]
                    "image" -> image = tag[1]
                    "p" -> if (tag[1].isNotEmpty() && tag[1] !in members) members.add(tag[1])
                }
            }
            val pubkey = event.str("pubkey") ?: return null
            if (dTag.isEmpty()) return null
            return FollowSet(event.str("id") ?: "", pubkey, dTag, title, description, image, members, event.long("created_at"))
        }

        fun memberCountText(count: Int): String = when (count) {
            0 -> L("exploreMembersZero")
            1 -> L("exploreMembersOne")
            else -> L("exploreMembersOther", "count" to count)
        }
    }
}

object FollowSetService {
    var sets by mutableStateOf<List<FollowSet>>(emptyList())
        private set
    var followedSets by mutableStateOf<List<FollowSet>>(emptyList())
        private set
    var favoriteIds by mutableStateOf(Prefs.stringList(FAVORITES_KEY) ?: emptyList())
        private set
    var isLoaded by mutableStateOf(false)
        private set
    var isSyncing by mutableStateOf(false)
        private set

    private var generation = 0
    private val publishQueue = Mutex()
    private var inflightPublishes = 0

    private val hiddenDTags = listOf("mute", "Chat-Friends")
    private const val FAVORITES_KEY = "favorite_follow_set_ids"
    private const val TOMBSTONES_KEY = "deleted_follow_set_ids"

    val allSets: List<FollowSet> get() = sets + followedSets
    val favoriteSets: List<FollowSet> get() = favoriteIds.mapNotNull { set(it) }

    fun set(withId: String): FollowSet? = allSets.firstOrNull { it.id == withId } ?: sets.firstOrNull { it.dTag == withId }

    fun isOwn(set: FollowSet) = set.pubkey == Session.pubkey
    fun isFavorite(id: String) = id in favoriteIds
    fun sets(containing: String): List<FollowSet> = sets.filter { containing in it.pubkeys }

    fun reset() {
        generation += 1
        sets = emptyList()
        followedSets = emptyList()
        isLoaded = false
        isSyncing = false
    }

    suspend fun load() {
        val me = Session.pubkey ?: return
        val current = generation
        loadFromDatabase(me, current)
        sync(me, current)
    }

    suspend fun refresh() {
        val me = Session.pubkey ?: return
        sync(me, generation)
    }

    fun toggleFavorite(id: String) {
        favoriteIds = if (id in favoriteIds) favoriteIds - id else favoriteIds + id
        Prefs.setStringList(FAVORITES_KEY, favoriteIds)
        DataBus.listsChanged()
    }

    suspend fun create(title: String, description: String = "", pubkeys: List<String>): FollowSet {
        val me = Session.pubkey ?: throw CoreError("Not signed in")
        val dTag = UUID.randomUUID().toString().replace("-", "").take(8).lowercase()
        val draft = FollowSet("", me, dTag, title.trim(), description.trim(), "", unique(pubkeys), TimeFormat.now)
        return commit(draft, null)
    }

    suspend fun update(id: String, title: String, description: String): FollowSet {
        val existing = ownSet(id) ?: throw CoreError(L("exploreListNotFound"))
        return commit(existing.copy(title = title.trim(), description = description.trim()), existing)
    }

    suspend fun setMembers(pubkeys: List<String>, id: String): FollowSet {
        val existing = ownSet(id) ?: throw CoreError(L("exploreListNotFound"))
        return commit(existing.copy(pubkeys = unique(pubkeys)), existing)
    }

    suspend fun addMember(pubkey: String, to: String) {
        val existing = ownSet(to) ?: return
        if (pubkey in existing.pubkeys) return
        setMembers(existing.pubkeys + pubkey, to)
    }

    suspend fun removeMember(pubkey: String, from: String) {
        val existing = ownSet(from) ?: return
        if (pubkey !in existing.pubkeys) return
        setMembers(existing.pubkeys.filter { it != pubkey }, from)
    }

    suspend fun delete(id: String) {
        val existing = ownSet(id) ?: return
        val key = Session.privateKey ?: return
        val current = generation
        val wasFavorite = isFavorite(existing.id)
        sets = sets.filter { it.id != existing.id }
        if (wasFavorite) toggleFavorite(existing.id)
        setTombstone(existing.id, maxOf(existing.createdAt, TimeFormat.now))
        DataBus.listsChanged()
        try {
            val tags = mutableListOf(listOf("a", existing.coordinate), listOf("k", "30000"))
            if (existing.eventId.isNotEmpty()) tags.add(0, listOf("e", existing.eventId))
            val json = createSignedEvent(5u.toUShort(), "User deleted list", tags, key)
            SyncService.publish(json)
            if (existing.eventId.isNotEmpty()) runCatching { dbDeleteEventsByIds(listOf(existing.eventId)) }
        } catch (error: Throwable) {
            if (current != generation) return
            setTombstone(existing.id, null)
            upsert(existing)
            if (wasFavorite) toggleFavorite(existing.id)
            DataBus.listsChanged()
            throw error
        }
    }

    private fun ownSet(id: String): FollowSet? = set(id)?.takeIf { isOwn(it) }

    private suspend fun commit(set: FollowSet, previous: FollowSet?): FollowSet {
        val current = generation
        upsert(set)
        DataBus.listsChanged()
        try {
            val published = enqueuePublish(set, previous)
            if (current != generation) return published
            upsert(published)
            DataBus.listsChanged()
            return published
        } catch (error: Throwable) {
            if (current == generation) {
                if (previous != null) upsert(previous) else sets = sets.filter { it.id != set.id }
                DataBus.listsChanged()
            }
            throw error
        }
    }

    private suspend fun enqueuePublish(set: FollowSet, previous: FollowSet?): FollowSet {
        inflightPublishes += 1
        try {
            return publishQueue.withLock { publish(set, previous) }
        } finally {
            inflightPublishes -= 1
        }
    }

    private suspend fun publish(set: FollowSet, previous: FollowSet?): FollowSet {
        val key = Session.requireSigner()
        val base = SyncService.latestEditableEvent(30000, set.pubkey, set.dTag, allowingNew = previous == null)
        val managed = setOf("d", "title", "description", "image", "p")
        val baseTags = base?.tags() ?: emptyList()
        val tags = mutableListOf(listOf("d", set.dTag))
        if (set.title.isNotEmpty()) tags.add(listOf("title", set.title))
        if (set.description.isNotEmpty()) tags.add(listOf("description", set.description))
        if (set.image.isNotEmpty()) tags.add(listOf("image", set.image))
        val remoteTags = baseTags.filter { it.size > 1 && it[0] == "p" }
        val original = LinkedHashMap<String, List<String>>()
        remoteTags.forEach { if (!original.containsKey(it[1])) original[it[1]] = it }
        var members = set.pubkeys
        if (base != null) {
            val before = previous?.pubkeys?.toSet() ?: emptySet()
            val removed = before - set.pubkeys.toSet()
            val added = set.pubkeys.filter { it !in before }
            val seen = HashSet<String>()
            members = (remoteTags.map { it[1] } + added).filter { it !in removed && seen.add(it) }
        }
        tags.addAll(members.map { original[it] ?: listOf("p", it) })
        tags.addAll(baseTags.filter { it.isNotEmpty() && it[0] !in managed })
        val content = base?.text("content") ?: ""
        val json = createSignedEvent(30000u.toUShort(), content, tags, key)
        val event = SyncService.publish(json)
        setTombstone(set.id, null)
        return FollowSet.fromEvent(event) ?: set
    }

    private fun upsert(set: FollowSet) {
        val index = sets.indexOfFirst { it.id == set.id }
        sets = if (index >= 0) sets.toMutableList().also { it[index] = set } else listOf(set) + sets
    }

    private suspend fun sync(me: String, current: Int) {
        isSyncing = true
        try {
            val follows = SyncService.followingList(me).filter { it != me }
            val events = SyncService.fetchEvents(mapOf("kinds" to listOf(30000), "authors" to listOf(me) + follows, "limit" to 500), timeout = 10)
            if (events.isNotEmpty()) runCatching { dbSaveEvents(JSONArray(events).toString()) }
            if (current != generation) return
            loadFromDatabase(me, current)
            if (current != generation) return
            val people = (sets.flatMap { it.pubkeys } + followedSets.map { it.pubkey }).toSet()
            if (people.isNotEmpty()) ProfileCache.load(people.toList())
        } finally {
            if (current == generation) isSyncing = false
        }
    }

    private suspend fun loadFromDatabase(me: String, current: Int) {
        val follows = SyncService.followingList(me).filter { it != me }
        val own = fetchSets(listOf(me), 100)
        val others = if (follows.isEmpty()) emptyList() else fetchSets(follows, 500)
        if (current != generation) return
        if (inflightPublishes == 0) sets = filterDeleted(own)
        followedSets = filterDeleted(others)
        isLoaded = true
        DataBus.listsChanged()
    }

    private suspend fun fetchSets(authors: List<String>, limit: Int): List<FollowSet> {
        if (authors.isEmpty()) return emptyList()
        val raw = runCatching { dbGetFollowSets(authors, limit.toUInt(), hiddenDTags) }.getOrNull()
        return Json.array(raw).map(FollowSet::from).filter { it.dTag.isNotEmpty() }
    }

    private val tombstones: Map<String, Long>
        get() {
            val json = Json.obj(Prefs.string(TOMBSTONES_KEY)) ?: return emptyMap()
            return json.keys().asSequence().associateWith { json.long(it) }
        }

    private fun setTombstone(id: String, timestamp: Long?) {
        val map = tombstones.toMutableMap()
        if (timestamp == null) map.remove(id) else map[id] = timestamp
        Prefs.set(TOMBSTONES_KEY, JSONObject(map as Map<*, *>).toString())
    }

    private fun filterDeleted(list: List<FollowSet>): List<FollowSet> {
        val map = tombstones
        if (map.isEmpty()) return list
        return list.filter { set -> map[set.id]?.let { set.createdAt > it } ?: true }
    }

    private fun unique(pubkeys: List<String>): List<String> {
        val seen = HashSet<String>()
        return pubkeys.filter { it.isNotEmpty() && seen.add(it) }
    }
}
