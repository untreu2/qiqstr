package me.untreu.qiqstr.ui.explore

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.qiqstr.core.dbGetRandomProfiles
import com.qiqstr.core.dbSearchProfiles
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.services.PrimalCache
import me.untreu.qiqstr.data.services.RelayConfig
import me.untreu.qiqstr.data.services.SearchService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Profile

object UserSearchService {
    fun pubkey(input: String): String? {
        val trimmed = input.trim()
        if (trimmed.isEmpty() || trimmed.contains(" ")) return null
        val stripped = trimmed.replace("https://njump.me/", "")
        Nip19.pubkeyHex(stripped)?.let { return it }
        val tlv = Nip19.decodeTLV(stripped)
        if (tlv?.str("type") == "nprofile") return tlv.str("pubkey")
        return null
    }

    suspend fun local(query: String, limit: Int = 30): List<Profile> =
        Json.array(runCatching { dbSearchProfiles(query, limit.toUInt()) }.getOrNull()).map { Profile.from(it) }.filter { it.pubkey.isNotEmpty() }

    suspend fun suggestions(limit: Int = 25): List<Profile> {
        val me = Session.pubkey
        return Json.array(runCatching { dbGetRandomProfiles(limit.toUInt()) }.getOrNull()).map { Profile.from(it) }
            .filter { it.pubkey.isNotEmpty() && it.pubkey != me }
    }

    suspend fun profile(pubkey: String): Profile {
        ProfileCache.refresh(pubkey)
        if (ProfileCache.profile(pubkey) == null) {
            SyncService.syncProfile(pubkey, force = true)
            ProfileCache.refresh(pubkey)
        }
        return ProfileCache.profile(pubkey) ?: Profile(pubkey)
    }

    suspend fun remote(query: String, limit: Int = 20): List<Profile> {
        val subscription = "qs_${System.currentTimeMillis()}"
        val request = listOf("REQ", subscription, mapOf("kinds" to listOf(0), "search" to query, "limit" to limit))
        val events = PrimalCache.relayRequest(RelayConfig.vertexRelayUrl, subscription, request, timeout = 9, limit = limit * 3)
        val seen = HashSet<String>()
        val results = mutableListOf<Profile>()
        for (event in events) {
            if (results.size >= limit) break
            if (event.int("kind") != 0) continue
            val pubkey = event.str("pubkey") ?: continue
            if (!seen.add(pubkey)) continue
            val metadata = Json.obj(event.text("content")) ?: continue
            results.add(Profile.from(metadata, pubkey).copy(pubkey = pubkey))
        }
        return results
    }
}

class UserSearchModel(private val scope: CoroutineScope, var resultLimit: Int = 40, var includesRemote: Boolean = true) {
    var query by mutableStateOf("")
        private set
    var results by mutableStateOf<List<Profile>>(emptyList())
        private set
    var suggestions by mutableStateOf<List<Profile>>(emptyList())
        private set
    var resolvedPubkey by mutableStateOf<String?>(null)
        private set
    var isSearching by mutableStateOf(false)
        private set
    var hasSearched by mutableStateOf(false)
        private set

    private var job: Job? = null

    val trimmedQuery: String get() = query.trim()

    fun updateQuery(value: String) {
        if (value == query) return
        query = value
        schedule()
    }

    suspend fun loadSuggestions() {
        if (suggestions.isNotEmpty()) return
        suggestions = UserSearchService.suggestions()
    }

    fun retry() = schedule(debounce = false)

    fun clear() {
        job?.cancel()
        query = ""
        results = emptyList()
        resolvedPubkey = null
        isSearching = false
        hasSearched = false
    }

    private fun schedule(debounce: Boolean = true) {
        job?.cancel()
        val text = trimmedQuery
        if (text.isEmpty()) {
            results = emptyList()
            resolvedPubkey = null
            isSearching = false
            hasSearched = false
            return
        }
        if (SearchService.looksSecret(text)) {
            results = emptyList()
            ToastCenter.show(L("searchSecretBlocked"), ToastStyle.ERROR)
            return
        }
        isSearching = true
        job = scope.launch {
            if (debounce) delay(300)
            run(text)
        }
    }

    private suspend fun run(text: String) {
        val pubkey = UserSearchService.pubkey(text)
        if (pubkey != null) {
            resolvedPubkey = pubkey
            val profile = UserSearchService.profile(pubkey)
            coroutineContext.ensureActive()
            results = listOf(profile)
            finish()
            return
        }
        resolvedPubkey = null
        val local = UserSearchService.local(text, resultLimit)
        coroutineContext.ensureActive()
        results = local
        hasSearched = true
        if (!includesRemote) {
            finish()
            return
        }
        val remote = UserSearchService.remote(text)
        coroutineContext.ensureActive()
        val seen = results.map { it.pubkey }.toHashSet()
        val extra = remote.filter { seen.add(it.pubkey) }
        for (profile in extra) if (ProfileCache.profile(profile.pubkey) == null) ProfileCache.set(profile)
        results = (results + extra).take(resultLimit)
        finish()
    }

    private fun finish() {
        isSearching = false
        hasSearched = true
    }
}
