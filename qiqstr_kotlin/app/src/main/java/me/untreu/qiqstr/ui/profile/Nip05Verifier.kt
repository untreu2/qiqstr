package me.untreu.qiqstr.ui.profile

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject

object Nip05Verifier {
    private data class Entry(val verified: Boolean, val checkedAt: Long)

    private val cache = HashMap<String, Entry>()
    private val inflight = HashMap<String, CompletableDeferred<Boolean>>()
    private val lock = Mutex()
    private const val TTL = 30 * 60 * 1000L
    private val http: OkHttpClient by lazy {
        OkHttpClient.Builder().callTimeout(8, TimeUnit.SECONDS).cache(null).build()
    }

    data class Parts(val name: String, val domain: String)

    fun parts(nip05: String): Parts? {
        val trimmed = nip05.trim().lowercase()
        val pieces = trimmed.split("@")
        if (pieces.size == 1 && isDomain(pieces[0])) return Parts("_", pieces[0])
        if (pieces.size != 2 || pieces[0].isEmpty() || !isDomain(pieces[1])) return null
        return Parts(pieces[0], pieces[1])
    }

    fun isValid(nip05: String): Boolean {
        val trimmed = nip05.trim()
        return trimmed.isEmpty() || (trimmed.contains("@") && parts(trimmed) != null)
    }

    fun display(nip05: String): String {
        val parts = parts(nip05) ?: return nip05
        return if (parts.name == "_") parts.domain else "${parts.name}@${parts.domain}"
    }

    private fun isDomain(s: String): Boolean =
        s.contains(".") && !s.startsWith(".") && !s.endsWith(".") && s.all { it.isLetterOrDigit() || it == '.' || it == '-' || it == ':' }

    suspend fun verify(nip05: String, pubkey: String): Boolean {
        val parts = parts(nip05) ?: return false
        val key = "${parts.name}@${parts.domain}#${pubkey.lowercase()}"
        val (deferred, owner) = lock.withLock {
            cache[key]?.let { if (System.currentTimeMillis() - it.checkedAt < TTL) return it.verified }
            inflight[key]?.let { return@withLock it to false }
            val created = CompletableDeferred<Boolean>()
            inflight[key] = created
            created to true
        }
        if (!owner) return deferred.await()
        val verified = lookup(parts.name, parts.domain, pubkey.lowercase())
        lock.withLock {
            inflight.remove(key)
            cache[key] = Entry(verified, System.currentTimeMillis())
        }
        deferred.complete(verified)
        return verified
    }

    private suspend fun lookup(name: String, domain: String, pubkey: String): Boolean = withContext(Dispatchers.IO) {
        val hostAndPort = domain.split(":")
        val url = runCatching {
            HttpUrl.Builder().scheme("https").host(hostAndPort[0]).apply {
                hostAndPort.getOrNull(1)?.toIntOrNull()?.let { port(it) }
            }.addPathSegments(".well-known/nostr.json").addQueryParameter("name", name).build()
        }.getOrNull() ?: return@withContext false
        runCatching {
            http.newCall(Request.Builder().url(url).header("Accept", "application/json").build()).execute().use { response ->
                if (response.code != 200) return@use false
                val names = JSONObject(response.body?.string() ?: return@use false).optJSONObject("names") ?: return@use false
                val match = names.keys().asSequence().firstOrNull { it.lowercase() == name }?.let { names.opt(it) as? String }
                match?.lowercase() == pubkey
            }
        }.getOrDefault(false)
    }
}
