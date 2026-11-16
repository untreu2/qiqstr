package me.untreu.qiqstr.data.accounts

import com.qiqstr.core.dbDeleteEventsByIds
import com.qiqstr.core.dbQueryEvents
import com.qiqstr.core.dbWipeDirectory
import java.io.File
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.SecureStore
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.services.RelayConfig

object AccountData {
    private val credentialKeys = mutableListOf<(String) -> String>()
    private val eraseHooks = mutableListOf<suspend (String) -> Unit>()

    fun registerCredential(key: (String) -> String) { credentialKeys.add(key) }
    fun onErase(hook: suspend (String) -> Unit) { eraseHooks.add(hook) }

    fun removeCredentials(pubkey: String) {
        if (pubkey.isEmpty()) return
        credentialKeys.forEach { SecureStore.set(it(pubkey), null) }
    }

    suspend fun erase(pubkey: String, isLastAccount: Boolean) {
        if (pubkey.isEmpty()) return
        removeCredentials(pubkey)
        eraseHooks.forEach { runCatching { it(pubkey) } }
        val support = RelayConfig.supportDir
        for (path in listOf("marmot/$pubkey", "Drafts/$pubkey.json", "Scheduled/$pubkey.json", "WebOfTrust/$pubkey.json")) File(support, path).deleteRecursively()
        File(App.context.cacheDir, "decrypted_media").deleteRecursively()
        val npub = Nip19.npub(pubkey) ?: pubkey
        Prefs.keys().filter { it.contains(pubkey) || it.contains(npub) }.forEach(Prefs::remove)
        if (isLastAccount) {
            runCatching { dbWipeDirectory() }
            RelayConfig.databaseDir.deleteRecursively()
        } else {
            eraseCachedEvents(pubkey)
        }
    }

    private suspend fun eraseCachedEvents(pubkey: String) {
        val filter = Json.string(mapOf("authors" to listOf(pubkey)))
        repeat(20) {
            val ids = Json.array(runCatching { dbQueryEvents(filter, 500u) }.getOrNull()).mapNotNull { it.str("id") }
            if (ids.isEmpty()) return
            val removed = runCatching { dbDeleteEventsByIds(ids) }.getOrDefault(0u)
            if (removed == 0u) return
        }
    }
}
