package me.untreu.qiqstr.data.services

import com.qiqstr.core.signEvent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import me.untreu.qiqstr.core.*
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import org.json.JSONObject

data class EmojiPack(val coordinate: String, val title: String, val author: String, val emojis: List<CustomEmoji>) {
    fun toJson() = mapOf("coordinate" to coordinate, "title" to title, "author" to author, "emojis" to emojis.map { mapOf("shortcode" to it.shortcode, "url" to it.url) })
    companion object {
        fun from(event: JSONObject): EmojiPack? {
            if (event.int("kind") != EmojiPackService.packKind) return null
            val author = event.str("pubkey") ?: return null
            val tags = event.tags()
            val name = tags.firstOrNull { it.size > 1 && it[0] == "d" }?.get(1)?.takeIf { it.isNotEmpty() } ?: return null
            val emojis = tags.mapNotNull(CustomEmoji::from).distinctBy { it.shortcode }
            if (emojis.isEmpty()) return null
            return EmojiPack("${EmojiPackService.packKind}:$author:$name", tags.firstOrNull { it.size > 1 && it[0] in listOf("title", "name") && it[1].isNotEmpty() }?.get(1) ?: name, author, emojis)
        }
        fun cached(j: JSONObject) = EmojiPack(j.optString("coordinate"), j.optString("title"), j.optString("author"), j.objects("emojis").map { CustomEmoji(it.optString("shortcode"), it.optString("url")) })
    }
}

object EmojiPackService {
    const val listKind = 10030
    const val packKind = 30030
    const val ownCoordinate = "own"
    var packs by mutableStateOf<List<EmojiPack>>(emptyList())
        private set
    var discovered by mutableStateOf<List<EmojiPack>>(emptyList())
        private set
    var isLoaded by mutableStateOf(false)
        private set
    var isDiscovering by mutableStateOf(false)
        private set
    var busy by mutableStateOf<Set<String>>(emptySet())
        private set
    private var owner: String? = null
    private var generation = 0
    val allEmojis: List<CustomEmoji> get() = packs.flatMap { it.emojis }.distinctBy { it.shortcode }
    fun contains(coordinate: String) = packs.any { it.coordinate == coordinate }
    fun reset() { generation++; owner = null; packs = emptyList(); discovered = emptyList(); isLoaded = false; busy = emptySet() }
    suspend fun load() {
        val me = Session.pubkey ?: return
        val gen = generation
        if (owner != me) { owner = me; packs = Json.array(Prefs.string("emoji_packs_$me")).map(EmojiPack::cached) }
        val newest = SyncService.fetchReplaceable(listKind, me).maxByOrNull { it.long("created_at") }
        if (gen != generation) return
        if (newest != null) {
            val tags = newest.tags()
            val own = tags.mapNotNull(CustomEmoji::from).distinctBy { it.shortcode }
            val coordinates = tags.filter { it.size > 1 && it[0] == "a" && it[1].startsWith("$packKind:") }.map { it[1] }
            val parts = coordinates.map { it.split(":", limit = 3) }.filter { it.size == 3 }
            val fetched = if (parts.isEmpty()) emptyList() else SyncService.fetchEvents(mapOf("kinds" to listOf(packKind), "authors" to parts.map { it[1] }.distinct(), "#d" to parts.map { it[2] }.distinct(), "limit" to 200), 8)
            if (gen != generation) return
            val resolved = fetched.sortedByDescending { it.long("created_at") }.mapNotNull(EmojiPack::from).distinctBy { it.coordinate }.associateBy { it.coordinate }
            packs = (if (own.isEmpty()) emptyList() else listOf(EmojiPack(ownCoordinate, L("emojiMyEmoji"), me, own))) + coordinates.mapNotNull { c -> resolved[c] ?: packs.firstOrNull { it.coordinate == c } }
            persist()
        }
        isLoaded = true
    }
    suspend fun discover() = coroutineScope {
        if (isDiscovering) return@coroutineScope
        val gen = generation
        isDiscovering = true
        try {
            val follows = FollowService.following
            val followed = async { if (follows.isEmpty()) emptyList() else SyncService.fetchEvents(mapOf("kinds" to listOf(packKind), "authors" to follows.take(400), "limit" to 150), 8) }
            val recent = async { SyncService.fetchEvents(mapOf("kinds" to listOf(packKind), "limit" to 150), 8) }
            val events = followed.await() + recent.await()
            if (gen != generation) return@coroutineScope
            discovered = events.sortedByDescending { it.long("created_at") }.mapNotNull(EmojiPack::from).filter { it.author !in Session.mutedPubkeys && it.emojis.size >= 2 && (!WebOfTrustService.isReady || WebOfTrustService.isTrusted(it.author)) }.distinctBy { it.coordinate }.sortedWith(compareByDescending<EmojiPack> { it.author in follows }.thenByDescending { it.emojis.size })
            ProfileCache.load(discovered.take(60).map { it.author }.distinct())
        } finally { isDiscovering = false }
    }
    suspend fun add(pack: EmojiPack) {
        if (contains(pack.coordinate) || pack.coordinate in busy) return
        edit(pack.coordinate) { it + listOf(listOf("a", pack.coordinate)) }
        packs = packs + pack
        persist()
    }
    suspend fun remove(pack: EmojiPack) {
        if (pack.coordinate == ownCoordinate || pack.coordinate in busy) return
        edit(pack.coordinate) { tags -> tags.filterNot { it.size > 1 && it[0] == "a" && it[1] == pack.coordinate } }
        packs = packs.filterNot { it.coordinate == pack.coordinate }
        persist()
    }
    private suspend fun edit(coordinate: String, change: (List<List<String>>) -> List<List<String>>) {
        val me = Session.pubkey ?: return
        Session.requireSigner()
        busy = busy + coordinate
        try {
            val base = SyncService.latestEditableEvent(listKind, me, allowingNew = true)
            SyncService.publish(signEvent(listKind.toUShort(), base?.str("content") ?: "", change(base?.tags() ?: emptyList())))
        } finally { busy = busy - coordinate }
    }
    private fun persist() { owner?.let { Prefs.set("emoji_packs_$it", Json.string(packs.map(EmojiPack::toJson))) } }
}
