package me.untreu.qiqstr.data.services

import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.data.sync.Session
import org.json.JSONObject

object ExploreSeenStore {
    private const val MAX_AGE = 7 * 86_400.0
    private const val CAPACITY = 3000
    private val unset = Any()

    private var owner: Any? = unset
    private var seen: Map<String, Double> = emptyMap()
    private var saveJob: Job? = null

    fun reset() {
        saveJob?.cancel()
        saveJob = null
        owner = unset
        seen = emptyMap()
    }

    fun snapshot(): Map<String, Double> {
        load()
        return seen
    }

    fun mark(id: String) {
        load()
        if (id.isEmpty() || seen.containsKey(id)) return
        seen = seen + (id to System.currentTimeMillis() / 1000.0)
        scheduleSave()
    }

    private fun key(pubkey: String) = "explore_seen_$pubkey"

    private fun load() {
        val me = Session.pubkey
        if (owner !== unset && owner == me) return
        saveJob?.cancel()
        owner = me
        if (me == null) {
            seen = emptyMap()
            return
        }
        val stored = Json.obj(Prefs.string(key(me)))
        val entries = stored?.keys()?.asSequence()?.associateWith { stored.optDouble(it, 0.0) } ?: emptyMap()
        seen = pruned(entries)
    }

    private fun scheduleSave() {
        val current = owner as? String ?: return
        saveJob?.cancel()
        saveJob = App.scope.launch {
            delay(1000)
            if (owner != current) return@launch
            seen = pruned(seen)
            Prefs.set(key(current), JSONObject(seen).toString())
        }
    }

    private fun pruned(entries: Map<String, Double>): Map<String, Double> {
        val cutoff = System.currentTimeMillis() / 1000.0 - MAX_AGE
        var fresh = entries.filterValues { it >= cutoff }
        if (fresh.size > CAPACITY) {
            fresh = fresh.entries.sortedByDescending { it.value }.take(CAPACITY).associate { it.key to it.value }
        }
        return fresh
    }
}
