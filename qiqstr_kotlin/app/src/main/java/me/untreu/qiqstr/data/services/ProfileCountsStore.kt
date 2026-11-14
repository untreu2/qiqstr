package me.untreu.qiqstr.data.services

import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.strings
import org.json.JSONArray
import org.json.JSONObject

data class ProfileCounts(val following: Int? = null, val followers: Int? = null)

object ProfileCountsStore {
    private const val STORAGE_KEY = "profile_counts_cache_v1"
    private const val CAPACITY = 400

    private val entries = HashMap<String, ProfileCounts>()
    private val order = mutableListOf<String>()
    private var saveJob: Job? = null

    init {
        Json.obj(Prefs.string(STORAGE_KEY))?.let { stored ->
            val map = stored.optJSONObject("entries") ?: JSONObject()
            for (key in map.keys()) {
                val entry = map.optJSONObject(key) ?: continue
                entries[key] = ProfileCounts(
                    following = if (entry.has("following")) entry.optInt("following") else null,
                    followers = if (entry.has("followers")) entry.optInt("followers") else null,
                )
            }
            order.addAll(stored.strings("order").filter { it in entries })
        }
    }

    fun counts(pubkey: String): ProfileCounts? = entries[pubkey]

    fun update(pubkey: String, following: Int? = null, followers: Int? = null) {
        val existing = entries[pubkey]
        var current = existing ?: ProfileCounts()
        if (following != null) current = current.copy(following = following)
        if (followers != null) current = current.copy(followers = followers)
        if (current == existing) return
        entries[pubkey] = current
        order.remove(pubkey)
        order.add(pubkey)
        if (order.size > CAPACITY) {
            val overflow = order.size - CAPACITY
            order.take(overflow).forEach { entries.remove(it) }
            repeat(overflow) { order.removeAt(0) }
        }
        scheduleSave()
    }

    private fun scheduleSave() {
        saveJob?.cancel()
        saveJob = App.scope.launch {
            delay(1000)
            val map = JSONObject()
            for ((key, value) in entries) {
                val entry = JSONObject()
                value.following?.let { entry.put("following", it) }
                value.followers?.let { entry.put("followers", it) }
                map.put(key, entry)
            }
            Prefs.set(STORAGE_KEY, JSONObject().put("entries", map).put("order", JSONArray(order)).toString())
        }
    }
}
