package me.untreu.qiqstr.data.services

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.qiqstr.core.createSignedEvent
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import org.json.JSONObject

object MediaServerStore {
    const val KIND = 10063
    val presets = listOf("https://blossom.primal.net", "https://nostr.download", "https://blossom.band", "https://blossom.nostr.build")

    var servers by mutableStateOf<List<String>>(emptyList())
        private set
    var isSaving by mutableStateOf(false)
        private set
    private var owner: String? = null

    val current: String
        get() {
            ensureLoaded()
            return servers.firstOrNull() ?: RelayConfig.defaultBlossomServer
        }

    val options: List<String>
        get() {
            ensureLoaded()
            return (servers + presets).distinct()
        }

    fun reset() {
        owner = null
        servers = emptyList()
    }

    suspend fun load() {
        ensureLoaded()
        val me = Session.pubkey ?: return
        val events = SyncService.fetchReplaceable(KIND, me)
        if (me != Session.pubkey) return
        val newest = events.maxByOrNull { it.long("created_at") } ?: return
        val remote = servers(newest)
        if (remote.isEmpty() || remote == servers) return
        servers = remote
        persist()
    }

    suspend fun select(server: String) {
        val url = normalized(server) ?: throw CoreError(L("settingsMediaServerInvalid"))
        ensureLoaded()
        if (url == servers.firstOrNull()) return
        publish(listOf(url) + servers.filter { it != url })
    }

    suspend fun remove(server: String) {
        ensureLoaded()
        if (server !in servers) return
        publish(servers.filter { it != server })
    }

    private suspend fun publish(next: List<String>) {
        val me = Session.pubkey ?: return
        val key = Session.requireSigner()
        isSaving = true
        try {
            val base = SyncService.latestEditableEvent(KIND, me, allowingNew = true)
            val kept = base?.tags().orEmpty().filter { it.firstOrNull() != "server" }
            val event = createSignedEvent(KIND.toUShort(), base?.text("content") ?: "", next.map { listOf("server", it) } + kept, key)
            SyncService.publish(event)
            if (me != Session.pubkey) return
            servers = next
            persist()
        } finally {
            isSaving = false
        }
    }

    fun normalized(raw: String): String? {
        var value = raw.trim()
        if (!value.contains("://")) value = "https://$value"
        value = value.trimEnd('/')
        if (value.any { it.isWhitespace() }) return null
        val uri = runCatching { Uri.parse(value) }.getOrNull() ?: return null
        if (uri.scheme != "https" || uri.host?.contains(".") != true) return null
        return value
    }

    fun displayName(server: String): String = runCatching { Uri.parse(server).host }.getOrNull()?.ifEmpty { null } ?: server

    private fun servers(event: JSONObject): List<String> =
        event.tags().filter { it.size > 1 && it[0] == "server" }.mapNotNull { normalized(it[1]) }.distinct()

    @Synchronized
    private fun ensureLoaded() {
        val pubkey = Session.pubkey
        if (pubkey == owner) return
        owner = pubkey
        servers = pubkey?.let { Prefs.stringList(storageKey(it)) } ?: emptyList()
    }

    private fun persist() {
        val owner = owner ?: return
        Prefs.setStringList(storageKey(owner), servers)
    }

    private fun storageKey(pubkey: String) = "blossom_servers_$pubkey"
}
