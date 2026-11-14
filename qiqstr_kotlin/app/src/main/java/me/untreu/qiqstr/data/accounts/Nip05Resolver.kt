package me.untreu.qiqstr.data.accounts

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.data.bridge.isHex
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject

data class Nip05Identity(val pubkey: String, val relays: List<String>)

object Nip05Resolver {
    val http: OkHttpClient by lazy {
        OkHttpClient.Builder().callTimeout(10, TimeUnit.SECONDS).followRedirects(false).build()
    }

    fun looksLikeAddress(input: String): Boolean {
        val trimmed = input.trim()
        if (trimmed.any { it.isWhitespace() }) return false
        val at = trimmed.lastIndexOf('@')
        if (at < 0) return false
        val domain = trimmed.substring(at + 1)
        return domain.contains('.') && !domain.startsWith('.') && !domain.endsWith('.')
    }

    suspend fun resolve(address: String): Nip05Identity = withContext(Dispatchers.IO) {
        val trimmed = address.trim().lowercase()
        val parts = trimmed.split("@", limit = 2)
        if (parts.size != 2 || parts[1].isEmpty()) throw AuthError.Nip05NotFound(address)
        val name = parts[0].ifEmpty { "_" }
        val url = HttpUrl.Builder().scheme("https").host(parts[1]).addPathSegments(".well-known/nostr.json")
            .addQueryParameter("name", name).build()
        val body = runCatching {
            http.newCall(Request.Builder().url(url).header("Accept", "application/json").build()).execute().use { response ->
                if (response.code != 200) null else response.body?.string()
            }
        }.getOrNull() ?: throw AuthError.Nip05NotFound(address)
        val root = runCatching { JSONObject(body) }.getOrNull() ?: throw AuthError.Nip05NotFound(address)
        val names = root.optJSONObject("names") ?: throw AuthError.Nip05NotFound(address)
        val pubkey = (names.opt(name) as? String)
            ?: names.keys().asSequence().firstOrNull { it.lowercase() == name }?.let { names.opt(it) as? String }
        if (pubkey == null || pubkey.length != 64 || !pubkey.all { it.isHex() }) throw AuthError.Nip05NotFound(address)
        val relaysArray = root.optJSONObject("relays")?.optJSONArray(pubkey)
        val relays = relaysArray?.let { arr -> (0 until arr.length()).mapNotNull { arr.opt(it) as? String } } ?: emptyList()
        Nip05Identity(pubkey.lowercase(), relays)
    }
}
