package me.untreu.qiqstr.data.services

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.strings

data class EmojiEntry(val emoji: String, val name: String)
data class EmojiGroup(val id: String, val items: List<EmojiEntry>) {
    val title: String get() = L("emoji${id.replaceFirstChar { it.uppercase() }}")
    val symbol: String get() = when (id) {
        "smileys" -> "😀"
        "people" -> "👋"
        "nature" -> "🌿"
        "food" -> "🍴"
        "travel" -> "🚗"
        "activities" -> "⚽"
        "objects" -> "💡"
        "symbols" -> "❤️"
        else -> "🏳️"
    }
}

object EmojiCatalog {
    val groups: List<EmojiGroup> by lazy {
        Json.array(App.context.assets.open("emoji.json").bufferedReader().use { it.readText() }).map { group ->
            EmojiGroup(group.optString("id"), group.strings("items").mapNotNull { item ->
                val parts = item.split("|", limit = 2)
                if (parts.size == 2) EmojiEntry(parts[0], parts[1]) else null
            })
        }
    }
    fun search(query: String): List<EmojiEntry> {
        val terms = query.lowercase().split(" ").filter { it.isNotEmpty() }
        return if (terms.isEmpty()) emptyList() else groups.flatMap { it.items }.filter { entry -> terms.all { entry.name.lowercase().contains(it) } }
    }
}

data class CustomEmoji(val shortcode: String, val url: String) {
    val token: String get() = ":$shortcode:"
    companion object {
        fun isShortcode(value: String): Boolean = value.matches(Regex("[A-Za-z0-9_-]{1,64}"))
        fun from(tag: List<String>): CustomEmoji? = if (tag.size >= 3 && tag[0] == "emoji" && isShortcode(tag[1]) && tag[2].startsWith("https://")) CustomEmoji(tag[1], tag[2]) else null
        fun map(tags: List<List<String>>): Map<String, String> = tags.mapNotNull(::from).distinctBy { it.shortcode }.associate { it.shortcode to it.url }
        fun shortcode(content: String): String? = content.trim().takeIf { it.startsWith(":") && it.endsWith(":") && it.length > 2 }?.drop(1)?.dropLast(1)?.takeIf(::isShortcode)
    }
}

sealed interface EmojiChoice {
    data class Unicode(val emoji: String) : EmojiChoice
    data class Custom(val emoji: CustomEmoji) : EmojiChoice
    val content: String get() = when (this) { is Unicode -> emoji; is Custom -> emoji.token }
    val stored: String get() = when (this) { is Unicode -> emoji; is Custom -> "${emoji.shortcode}|${emoji.url}" }
    companion object {
        fun from(stored: String): EmojiChoice {
            val parts = stored.split("|", limit = 2)
            return if (parts.size == 2 && CustomEmoji.isShortcode(parts[0]) && parts[1].startsWith("https://")) Custom(CustomEmoji(parts[0], parts[1])) else Unicode(stored)
        }
    }
}

object RecentEmojiStore {
    var items by mutableStateOf((Prefs.stringList("emoji_recent") ?: emptyList()).map(EmojiChoice::from))
        private set
    fun record(choice: EmojiChoice) {
        items = (listOf(choice) + items.filter { it != choice }).take(24)
        Prefs.setStringList("emoji_recent", items.map { it.stored })
    }
}
