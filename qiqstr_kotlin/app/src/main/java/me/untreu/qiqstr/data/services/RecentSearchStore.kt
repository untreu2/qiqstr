package me.untreu.qiqstr.data.services

import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.data.sync.Session

object RecentSearchStore {
    private const val LIMIT = 12

    private val key: String get() = "search_recents_${Session.pubkey ?: "guest"}"

    fun load(): List<String> = Prefs.stringList(key) ?: emptyList()

    fun add(term: String): List<String> {
        val trimmed = term.trim()
        if (trimmed.isEmpty() || trimmed.length > 120 || SearchService.looksSecret(trimmed)) return load()
        val items = (listOf(trimmed) + load().filter { !it.equals(trimmed, ignoreCase = true) }).take(LIMIT)
        Prefs.setStringList(key, items)
        return items
    }

    fun remove(term: String): List<String> {
        val items = load().filter { it != term }
        Prefs.setStringList(key, items)
        return items
    }

    fun clear() = Prefs.remove(key)
}
