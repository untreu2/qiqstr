package me.untreu.qiqstr.data.services

import android.net.Uri
import java.io.File
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.Prefs

enum class GossipMode(val raw: String, val maxOutboxRelays: Int, val minRelayFrequency: Int) {
    NORMAL("normal", 30, 2), AGGRESSIVE("aggressive", 100, 1), PSYCHO("psycho", 1000, 0);

    companion object {
        fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: NORMAL
    }
}

object RelayConfig {
    val defaultMainRelays = listOf("wss://relay.damus.io", "wss://nos.lol", "wss://relay.primal.net", "wss://vitor.nostr1.com")
    val discoveryRelays = listOf("wss://relay.damus.io", "wss://nos.lol", "wss://relay.primal.net", "wss://vitor.nostr1.com", "wss://nostr.bitcoiner.social", "wss://nostr.mom")
    val indexerRelays = listOf("wss://purplepag.es", "wss://nostr.mom", "wss://relay.primal.net")
    const val primalCacheUrl = "wss://cache2.primal.net/v1"
    const val vertexRelayUrl = "wss://relay.vertexlab.io"
    const val defaultBlossomServer = "https://blossom.primal.net"
    val blossomServer: String get() = MediaServerStore.current
    val encryptedMediaServers: List<String> get() = listOf(blossomServer, defaultBlossomServer, "https://nostr.download").distinct()

    var mainRelays: List<String>
        get() {
            val stored = Prefs.stringList("custom_main_relays") ?: return defaultMainRelays
            val valid = stored.filter(::isUsableRelayURL)
            return valid.ifEmpty { defaultMainRelays }
        }
        set(value) = Prefs.setStringList("custom_main_relays", value.filter(::isUsableRelayURL))

    fun isUsableRelayURL(raw: String): Boolean {
        val value = raw.trim()
        if (value != raw || value.any { it.isWhitespace() }) return false
        if (value.split("://").size != 2) return false
        val uri = runCatching { Uri.parse(value) }.getOrNull() ?: return false
        val scheme = uri.scheme?.lowercase() ?: return false
        if (scheme != "wss" && scheme != "ws") return false
        if (uri.host.isNullOrEmpty()) return false
        val port = uri.port
        if (port != -1 && port !in 1..65535) return false
        return true
    }

    fun resetRelays() = Prefs.remove("custom_main_relays")

    var gossipMode: GossipMode
        get() = GossipMode.from(Prefs.string("gossip_mode"))
        set(value) = Prefs.set("gossip_mode", value.raw)

    val databaseDir: File get() = File(App.context.filesDir, "nostr-lmdb")
    val supportDir: File get() = App.context.filesDir
}
