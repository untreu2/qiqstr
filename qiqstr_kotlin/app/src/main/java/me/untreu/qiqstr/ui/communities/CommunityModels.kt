package me.untreu.qiqstr.ui.communities

import java.net.URI
import me.untreu.qiqstr.core.*
import org.json.JSONObject

object CommunitySafety {
    private val minorTerms = listOf("under 18", "under18", "underage", "under age", "minor", "minors", "teen", "teens", "preteen", "kid", "kids", "child", "children", "loli", "lolis", "shota", "jailbait", "young girl", "young boy", "little girl", "little boy", "little kids", "schoolgirl", "schoolboy", "cp")
    private val adultTerms = listOf("sex", "sexy", "nude", "nudes", "naked", "porn", "nsfw", "xxx", "horny", "hot pics", "pics", "fetish", "slave", "onlyfans", "erotic", "cum", "dick", "pussy", "boobs", "hentai", "kink", "18+", "video call", "sexting")
    fun allows(vararg fields: String, sensitive: Boolean): Boolean {
        val text = " " + fields.joinToString(" ").lowercase().map { if (it.isLetterOrDigit() || it == '+') it else ' ' }.joinToString("") + " "
        val adult = adultTerms.any { " $it " in text }
        if (adult && minorTerms.any { " $it " in text }) return false
        return !adult || sensitive
    }
    fun isTrusted(pubkey: String, me: String?, follows: Set<String>, ready: Boolean, trusted: Boolean): Boolean = pubkey == me || pubkey in follows || (ready && trusted)
}

fun normalizedRelay(raw: String): String? {
    var value = raw.trim()
    if (value.isEmpty()) return null
    if (!value.contains("://")) value = "wss://$value"
    value = value.trimEnd('/')
    val uri = runCatching { URI(value) }.getOrNull() ?: return null
    return value.takeIf { uri.scheme?.lowercase() in setOf("wss", "ws") && uri.host?.contains('.') == true && uri.userInfo == null }
}

private fun List<List<String>>.value(key: String): String = firstOrNull { it.size > 1 && it[0] == key }?.get(1).orEmpty()

data class RelayGroup(val groupId: String, val relay: String, val name: String = "", val about: String = "", val picture: String = "", val isPrivate: Boolean = false, val isClosed: Boolean = false) {
    val id: String get() = "$relay'$groupId"
    val displayName: String get() = name.ifEmpty { groupId }
    val relayHost: String get() = runCatching { URI(relay).host }.getOrNull() ?: relay
    companion object {
        fun from(event: JSONObject, relay: String): RelayGroup? {
            if (event.int("kind") != 39000) return null
            val tags = event.tags()
            val id = tags.value("d").ifEmpty { return null }
            return RelayGroup(id, normalizedRelay(relay) ?: return null, tags.value("name"), tags.value("about"), tags.value("picture"), tags.any { it.firstOrNull() == "private" }, tags.any { it.firstOrNull() == "closed" })
        }
        fun link(raw: String): RelayGroup? {
            val parts = raw.trim().split("'", limit = 2)
            if (parts.size != 2 || parts[1].isEmpty()) return null
            return RelayGroup(parts[1], normalizedRelay(parts[0]) ?: return null)
        }
    }
}

data class Community(val pubkey: String, val dTag: String, val name: String = "", val summary: String = "", val image: String = "", val rules: String = "", val moderators: List<String> = emptyList(), val relays: List<String> = emptyList(), val createdAt: Long = 0) {
    val coordinate: String get() = "34550:$pubkey:$dTag"
    val id: String get() = coordinate
    val displayName: String get() = name.ifEmpty { dTag }
    val team: List<String> get() = (listOf(pubkey) + moderators).distinct()
    companion object {
        fun parse(coordinate: String): Pair<String, String>? {
            val parts = coordinate.split(":", limit = 3)
            return if (parts.size == 3 && parts[0] == "34550" && parts[1].length == 64) parts[1] to parts[2] else null
        }
        fun from(event: JSONObject): Community? {
            if (event.int("kind") != 34550) return null
            val pubkey = event.str("pubkey") ?: return null
            val tags = event.tags()
            val identifier = tags.firstOrNull { it.size > 1 && it[0] == "d" }?.get(1) ?: return null
            return Community(pubkey, identifier, tags.value("name"), tags.value("description"), tags.value("image"), tags.value("rules"), tags.filter { it.size > 1 && it[0] == "moderator" && it[1].length == 64 }.map { it[1] }.distinct(), tags.filter { it.size > 1 && it[0] == "relay" }.mapNotNull { normalizedRelay(it[1]) }.distinct(), event.long("created_at"))
        }
    }
}

data class PublicChannel(val id: String, val creator: String, val name: String = "", val about: String = "", val picture: String = "", val relays: List<String> = emptyList(), val createdAt: Long = 0, val updatedAt: Long = 0) {
    val displayName: String get() = name.ifEmpty { L("channelUntitled") }
    private fun content(raw: String?): PublicChannel {
        val meta = Json.obj(raw) ?: return this
        return copy(name = meta.str("name") ?: name, about = meta.str("about") ?: about, picture = meta.str("picture") ?: picture, relays = if (meta.optJSONArray("relays") != null) meta.strings("relays").mapNotNull(::normalizedRelay) else relays)
    }
    fun metadata(event: JSONObject): PublicChannel {
        if (event.int("kind") != 41 || event.str("pubkey") != creator || event.long("created_at") <= updatedAt || channelRoot(event) != id) return this
        return content(event.str("content")).copy(updatedAt = event.long("created_at"))
    }
    companion object {
        fun from(event: JSONObject): PublicChannel? {
            if (event.int("kind") != 40) return null
            return PublicChannel(event.str("id") ?: return null, event.str("pubkey") ?: return null, createdAt = event.long("created_at")).content(event.str("content"))
        }
    }
}

fun channelRoot(event: JSONObject): String? {
    val tags = event.tags().filter { it.size > 1 && it[0] == "e" }
    return (tags.firstOrNull { it.size > 3 && it[3] == "root" } ?: tags.firstOrNull())?.get(1)
}

data class CommunityChatMessage(val id: String, val pubkey: String, val content: String, val createdAt: Long) {
    companion object {
        fun from(event: JSONObject, kind: Int): CommunityChatMessage? {
            if (event.int("kind") != kind) return null
            val content = event.text("content").trim().ifEmpty { return null }
            return CommunityChatMessage(event.str("id") ?: return null, event.str("pubkey") ?: return null, content, event.long("created_at"))
        }
        fun list(events: List<JSONObject>, kind: Int) = events.mapNotNull { from(it, kind) }.distinctBy { it.id }.sortedWith(compareBy({ it.createdAt }, { it.id }))
    }
}

fun isCommunityPost(event: JSONObject, coordinate: String): Boolean = when (event.int("kind")) {
    1111 -> event.tags().any { it.size > 1 && it[0] == "A" && it[1] == coordinate } && event.tags().any { it.size > 1 && it[0] == "k" && it[1] == "34550" }
    1 -> event.tags().any { it.size > 1 && it[0] == "a" && it[1] == coordinate } && event.tags().none { it.firstOrNull() == "e" }
    else -> false
}
