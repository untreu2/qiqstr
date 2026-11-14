package me.untreu.qiqstr.app

import android.net.Uri
import com.qiqstr.core.dbGetEvent
import com.qiqstr.core.dbGetProfile
import com.qiqstr.core.dbSaveEvents
import com.qiqstr.core.fetchEventsFromRelays
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.NostrLink
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.strings
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache

object NostrLinkResolver {
    fun open(link: NostrLink) {
        when (link) {
            is NostrLink.Profile -> {
                val pubkey = Nip19.pubkeyHex(link.entity) ?: return
                Router.push(Route.Profile(pubkey))
                val relays = hintRelays(link.entity)
                if (relays.isNotEmpty()) App.scope.launch { prefetchProfile(pubkey, relays) }
            }
            is NostrLink.Event -> {
                val id = Nip19.decode(link.entity) ?: return
                val relays = hintRelays(link.entity)
                App.scope.launch {
                    val kind = locateEvent(id, relays)
                    Router.push(if (kind == 30023) Route.Article(id) else Route.Thread(id))
                }
            }
            is NostrLink.Address -> {
                val tlv = Nip19.decodeTLV(link.entity)
                val kind = tlv?.opt("kind") as? Number
                val pubkey = tlv?.str("pubkey")
                val identifier = tlv?.optString("identifier")
                when {
                    kind?.toInt() == 30311 && pubkey != null && identifier != null -> Router.push(Route.LiveStream("30311:$pubkey:$identifier"))
                    kind == null || kind.toInt() == 30023 || kind.toInt() == 30024 -> Router.push(Route.ArticleAddress(link.entity))
                    else -> Router.browse(Uri.parse("https://njump.me/${link.entity}"))
                }
            }
        }
    }

    private fun hintRelays(entity: String): List<String> =
        Nip19.decodeTLV(entity)?.strings("relays").orEmpty().filter { it.startsWith("wss://") || it.startsWith("ws://") }.distinct().take(5)

    private suspend fun locateEvent(id: String, relays: List<String>): Int? {
        runCatching { dbGetEvent(id) }.getOrNull()?.let { raw -> Json.obj(raw)?.let { return it.int("kind") } }
        if (relays.isEmpty()) return null
        val filter = Json.string(mapOf("ids" to listOf(id), "limit" to 1))
        val raw = runCatching { fetchEventsFromRelays(filter, relays, 4u) }.getOrNull() ?: return null
        runCatching { dbSaveEvents(raw) }
        return Json.array(raw).firstOrNull()?.int("kind")
    }

    private suspend fun prefetchProfile(pubkey: String, relays: List<String>) {
        if (runCatching { dbGetProfile(pubkey) }.getOrNull() != null) return
        val filter = Json.string(mapOf("kinds" to listOf(0), "authors" to listOf(pubkey), "limit" to 1))
        val raw = runCatching { fetchEventsFromRelays(filter, relays, 5u) }.getOrNull() ?: return
        val saved = runCatching { dbSaveEvents(raw) }.getOrDefault(0u)
        if (saved == 0u) return
        ProfileCache.refresh(pubkey)
        DataBus.profileChanged()
    }
}
