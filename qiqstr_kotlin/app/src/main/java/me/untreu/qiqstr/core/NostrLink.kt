package me.untreu.qiqstr.core

import android.net.Uri

sealed class NostrLink(val entity: String) {
    class Profile(entity: String) : NostrLink(entity)
    class Event(entity: String) : NostrLink(entity)
    class Address(entity: String) : NostrLink(entity)

    override fun equals(other: Any?) = other is NostrLink && other::class == this::class && other.entity == entity
    override fun hashCode() = entity.hashCode()

    companion object {
        val webHosts = setOf(
            "njump.me", "primal.net", "damus.io", "snort.social", "iris.to", "nostr.com", "nostr.band",
            "coracle.social", "nostrudel.ninja", "yakihonne.com", "habla.news", "highlighter.com", "zap.stream", "nostter.app",
        )
        private val prefixes = listOf("npub1", "nprofile1", "note1", "nevent1", "naddr1")
        private val charset = "023456789acdefghjklmnpqrstuvwxyz".toSet()

        fun fromUri(uri: Uri): NostrLink? {
            val scheme = uri.scheme?.lowercase() ?: return null
            if (scheme == "nostr") return fromEntity(uri.toString().removePrefix("nostr:").removePrefix("NOSTR:"))
            if (scheme != "https" && scheme != "http") return null
            val host = uri.host?.lowercase()?.removePrefix("www.") ?: return null
            if (host !in webHosts) return null
            return uri.pathSegments.reversed().firstNotNullOfOrNull { fromEntity(it) }
        }

        fun fromText(text: String): NostrLink? {
            val trimmed = text.trim()
            return fromEntity(trimmed) ?: runCatching { fromUri(Uri.parse(trimmed)) }.getOrNull()
        }

        fun fromEntity(raw: String): NostrLink? {
            var value = raw.trim().lowercase()
            if (value.startsWith("nostr:")) value = value.removePrefix("nostr:")
            if (value.startsWith("//")) value = value.removePrefix("//")
            val prefix = prefixes.firstOrNull { value.startsWith(it) } ?: return null
            val body = value.removePrefix(prefix)
            if (body.length < 20 || !body.all { it in charset }) return null
            return when (prefix) {
                "npub1", "nprofile1" -> Profile(value)
                "naddr1" -> Address(value)
                else -> Event(value)
            }
        }
    }
}
