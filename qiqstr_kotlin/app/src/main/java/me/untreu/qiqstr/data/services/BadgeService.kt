package me.untreu.qiqstr.data.services

import androidx.compose.runtime.Immutable
import com.qiqstr.core.dbQueryEvents
import com.qiqstr.core.dbSaveEvents
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.data.sync.SyncService
import org.json.JSONArray
import org.json.JSONObject

@Immutable
data class ProfileBadge(
    val issuer: String,
    val dTag: String,
    val name: String,
    val description: String,
    val image: String,
    val thumb: String,
) {
    val id: String get() = "$issuer:$dTag"
    val displayName: String get() = name.ifEmpty { dTag }
    val thumbURL: String? get() = thumb.ifEmpty { null } ?: image.ifEmpty { null }
    val imageURL: String? get() = image.ifEmpty { null } ?: thumb.ifEmpty { null }

    companion object {
        fun fromDefinition(event: JSONObject): ProfileBadge? {
            if (event.int("kind") != 30009) return null
            val issuer = event.str("pubkey") ?: return null
            var dTag = ""
            var name = ""
            var description = ""
            var image = ""
            var thumb = ""
            var thumbWidth = Int.MAX_VALUE
            for (tag in event.tags()) {
                if (tag.size <= 1) continue
                when (tag[0]) {
                    "d" -> dTag = tag[1]
                    "name" -> name = tag[1]
                    "description" -> description = tag[1]
                    "image" -> image = tag[1]
                    "thumb" -> {
                        val width = if (tag.size > 2) tag[2].split("x").firstOrNull()?.toIntOrNull() ?: Int.MAX_VALUE else Int.MAX_VALUE
                        if (thumb.isEmpty() || (width >= 64 && width < thumbWidth)) {
                            thumb = tag[1]
                            thumbWidth = width
                        }
                    }
                }
            }
            if (dTag.isEmpty()) return null
            return ProfileBadge(issuer, dTag, name, description, image, thumb)
        }
    }
}

object BadgeService {
    private val cache = HashMap<String, List<ProfileBadge>>()
    private val listKinds = listOf(10008, 30008)
    private const val MAX_BADGES = 40

    private data class Reference(val issuer: String, val dTag: String) {
        val id: String get() = "$issuer:$dTag"
    }

    fun cached(pubkey: String): List<ProfileBadge>? = cache[pubkey]

    fun reset() = cache.clear()

    suspend fun local(pubkey: String): List<ProfileBadge> {
        val list = newestList(queryLocal(mapOf("kinds" to listKinds, "authors" to listOf(pubkey)), 10), pubkey) ?: return emptyList()
        val refs = references(list)
        if (refs.isEmpty()) return emptyList()
        val definitions = queryLocal(definitionFilter(refs), refs.size * 2 + 4)
        val badges = resolve(refs, definitions)
        if (badges.isNotEmpty()) cache[pubkey] = badges
        return badges
    }

    suspend fun refresh(pubkey: String): List<ProfileBadge> {
        val local = newestList(queryLocal(mapOf("kinds" to listKinds, "authors" to listOf(pubkey)), 10), pubkey)
        val remoteLists = SyncService.fetchEvents(mapOf("kinds" to listKinds, "authors" to listOf(pubkey), "limit" to 4), timeout = 8)
        val remote = newestList(remoteLists, pubkey)
        if (remote != null && remote.long("created_at") > (local?.long("created_at") ?: -1)) {
            runCatching { dbSaveEvents(JSONArray(listOf(remote)).toString()) }
        }
        val list = listOfNotNull(local, remote).maxByOrNull { it.long("created_at") }
        if (list == null) {
            cache[pubkey] = emptyList()
            return emptyList()
        }
        val refs = references(list)
        if (refs.isEmpty()) {
            cache[pubkey] = emptyList()
            return emptyList()
        }
        var definitions = queryLocal(definitionFilter(refs), refs.size * 2 + 4)
        val known = definitions.mapNotNull { ProfileBadge.fromDefinition(it)?.id }.toSet()
        val missing = refs.filter { it.id !in known }
        if (missing.isNotEmpty()) {
            val filter = definitionFilter(missing) + ("limit" to missing.size * 2 + 4)
            val fetched = SyncService.fetchEvents(filter, timeout = 8).filter { it.int("kind") == 30009 }
            if (fetched.isNotEmpty()) {
                runCatching { dbSaveEvents(JSONArray(fetched).toString()) }
                definitions = definitions + fetched
            }
        }
        val badges = resolve(refs, definitions)
        cache[pubkey] = badges
        return badges
    }

    private suspend fun queryLocal(filter: Map<String, Any?>, limit: Int): List<JSONObject> =
        Json.array(runCatching { dbQueryEvents(Json.string(filter), limit.toUInt()) }.getOrNull())

    private fun newestList(events: List<JSONObject>, pubkey: String): JSONObject? =
        events.filter { event ->
            if (event.str("pubkey") != pubkey) return@filter false
            when (event.int("kind")) {
                10008 -> true
                30008 -> event.tags().any { it.size > 1 && it[0] == "d" && it[1] == "profile_badges" }
                else -> false
            }
        }.maxByOrNull { it.long("created_at") }

    private fun references(event: JSONObject): List<Reference> {
        val seen = HashSet<String>()
        val result = mutableListOf<Reference>()
        for (tag in event.tags()) {
            if (tag.size <= 1 || tag[0] != "a") continue
            val parts = tag[1].split(":", limit = 3)
            if (parts.size != 3 || parts[0] != "30009" || parts[1].length != 64 || parts[2].isEmpty()) continue
            val ref = Reference(parts[1], parts[2])
            if (seen.add(ref.id)) result.add(ref)
            if (result.size >= MAX_BADGES) break
        }
        return result
    }

    private fun definitionFilter(refs: List<Reference>): Map<String, Any?> =
        mapOf("kinds" to listOf(30009), "authors" to refs.map { it.issuer }.distinct(), "#d" to refs.map { it.dTag }.distinct())

    private fun resolve(refs: List<Reference>, definitions: List<JSONObject>): List<ProfileBadge> {
        val byId = HashMap<String, Pair<ProfileBadge, Long>>()
        for (event in definitions) {
            val badge = ProfileBadge.fromDefinition(event) ?: continue
            val created = event.long("created_at")
            val existing = byId[badge.id]
            if (existing != null && existing.second >= created) continue
            byId[badge.id] = badge to created
        }
        return refs.mapNotNull { byId[it.id]?.first }
    }
}
