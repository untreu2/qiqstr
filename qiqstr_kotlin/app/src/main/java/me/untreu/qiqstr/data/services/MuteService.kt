package me.untreu.qiqstr.data.services

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.qiqstr.core.createSignedEvent
import com.qiqstr.core.dbQueryEvents
import com.qiqstr.core.getConnectedRelayCount
import com.qiqstr.core.nip04Decrypt
import com.qiqstr.core.nip44Decrypt
import com.qiqstr.core.nip44Encrypt
import com.qiqstr.core.setActiveMuteList
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.strings
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.accounts.AccountStore
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import org.json.JSONArray
import org.json.JSONObject

object MuteService {
    var mutedPubkeys by mutableStateOf<List<String>>(emptyList())
        private set
    var mutedWords by mutableStateOf<List<String>>(emptyList())
        private set
    var isLoaded by mutableStateOf(false)
        private set
    var hasSyncedRemote by mutableStateOf(false)
        private set
    private var generation = 0
    private val queue = Mutex()
    private var remote = RemoteMuteList()
    private var pending = PendingMutes()
    private val listeners = mutableListOf<() -> Unit>()

    fun onChange(listener: () -> Unit) { listeners.add(listener) }

    fun isMuted(pubkey: String) = pubkey in mutedPubkeys

    fun containsMutedWord(content: String): Boolean {
        if (mutedWords.isEmpty()) return false
        val lower = content.lowercase()
        return mutedWords.any { lower.contains(it) }
    }

    fun reset() {
        generation += 1
        remote = RemoteMuteList()
        pending = PendingMutes()
        mutedPubkeys = emptyList()
        mutedWords = emptyList()
        isLoaded = false
        hasSyncedRemote = false
        syncToRust()
    }

    suspend fun load() {
        val me = Session.pubkey ?: return
        val generation = this.generation
        pending = PendingMutes.stored(me)
        readCachedList(me, generation)
        SyncService.fetchEvents(filter(me))
        if (generation != this.generation) return
        readCachedList(me, generation)
        if (generation != this.generation) return
        hasSyncedRemote = true
        if (!pending.isEmpty) App.scope.launch { enqueue { publishPending() } }
    }

    suspend fun mute(pubkey: String) {
        if (pubkey.isEmpty() || pubkey == Session.pubkey) return
        perform { if (pubkey in mutedPubkeys) false else { pending.removedPubkeys.remove(pubkey); pending.addedPubkeys.add(pubkey); true } }
    }

    suspend fun unmute(pubkey: String) =
        perform { if (pubkey !in mutedPubkeys) false else { pending.addedPubkeys.remove(pubkey); pending.removedPubkeys.add(pubkey); true } }

    suspend fun addWord(word: String) {
        val normalized = word.trim().lowercase()
        if (normalized.isEmpty()) return
        perform { if (normalized in mutedWords) false else { pending.removedWords.remove(normalized); pending.addedWords.add(normalized); true } }
    }

    suspend fun removeWord(word: String) {
        val normalized = word.trim().lowercase()
        perform { if (normalized !in mutedWords) false else { pending.addedWords.remove(normalized); pending.removedWords.add(normalized); true } }
    }

    private suspend fun perform(change: () -> Boolean) {
        val me = Session.pubkey ?: return
        if (!change()) return
        pending.store(me)
        recompute()
        enqueue { publishPending() }
    }

    private suspend fun enqueue(work: suspend () -> Unit) {
        val generation = this.generation
        queue.withLock { if (generation == this.generation) work() }
    }

    private suspend fun publishPending() {
        if (pending.isEmpty) return
        val me = Session.pubkey ?: return
        val key = Session.privateKey ?: return
        val generation = this.generation
        val base = latestList(me, key) ?: return
        if (generation != this.generation || !base.isReadable) return
        val changes = pending.copy()
        val removedPubkeys = changes.removedPubkeys.toSet()
        val removedWords = changes.removedWords.toSet()
        val keep: (List<String>) -> Boolean = { tag ->
            if (tag.size <= 1) true else when (tag[0]) {
                "p" -> tag[1] !in removedPubkeys
                "word" -> tag[1].lowercase() !in removedWords
                else -> true
            }
        }
        val publicTags = base.publicTags.filter(keep)
        val privateTags = base.privateTags.filter(keep).toMutableList()
        val known = RemoteMuteList(publicTags, privateTags.toList())
        val knownPubkeys = known.pubkeys.toSet()
        val knownWords = known.words.toSet()
        privateTags += changes.addedPubkeys.filter { it !in knownPubkeys }.map { listOf("p", it) }
        privateTags += changes.addedWords.filter { it !in knownWords }.map { listOf("word", it) }
        runCatching {
            val content = if (privateTags.isEmpty()) "" else nip44Encrypt(Json.string(privateTags), key, me)
            val event = createSignedEvent(10000u.toUShort(), content, publicTags, key)
            SyncService.publish(event)
            if (generation != this.generation) return
            remote = RemoteMuteList(publicTags, privateTags)
            pending.subtract(changes)
            pending.store(me)
            recompute()
        }
    }

    private suspend fun latestList(me: String, key: String): RemoteMuteList? {
        val cached = cachedEvents(me)
        val fetched = SyncService.fetchReplaceable(10000, me)
        if (fetched.isEmpty() && cached.isNotEmpty()) return null
        newest(cached + fetched, me)?.let { return parse(it, me, key) }
        if (!Session.isNewAccount && !AccountStore.wasCreatedHere(me)) return null
        if (runCatching { getConnectedRelayCount() }.getOrDefault(0u) == 0u) return null
        return RemoteMuteList()
    }

    private suspend fun readCachedList(me: String, generation: Int) {
        val events = cachedEvents(me)
        if (generation != this.generation) return
        remote = newest(events, me)?.let { parse(it, me, Session.privateKey) } ?: RemoteMuteList()
        recompute()
    }

    private suspend fun cachedEvents(me: String): List<JSONObject> =
        Json.array(runCatching { dbQueryEvents(Json.string(filter(me)), 1u) }.getOrNull())

    private fun filter(me: String) = mapOf("kinds" to listOf(10000), "authors" to listOf(me), "limit" to 1)

    private fun newest(events: List<JSONObject>, author: String): JSONObject? =
        events.filter { it.int("kind") == 10000 && it.str("pubkey")?.lowercase() == author.lowercase() }
            .maxWithOrNull(compareBy<JSONObject>({ it.long("created_at") }, { it.str("id") ?: "" }))

    private fun parse(event: JSONObject, pubkey: String, privateKey: String?): RemoteMuteList {
        val publicTags = event.tags()
        val content = event.text("content")
        if (content.isEmpty()) return RemoteMuteList(publicTags)
        val plain = privateKey?.let { decrypt(content, it, pubkey) }
        val array = plain?.let { runCatching { JSONArray(it) }.getOrNull() } ?: return RemoteMuteList(publicTags, isReadable = false)
        val privateTags = (0 until array.length()).mapNotNull { index ->
            val tag = array.optJSONArray(index) ?: return@mapNotNull null
            (0 until tag.length()).mapNotNull { tag.opt(it) as? String }
        }
        return RemoteMuteList(publicTags, privateTags)
    }

    private fun decrypt(content: String, privateKey: String, pubkey: String): String? = runCatching {
        if (content.contains("?iv=")) nip04Decrypt(content, privateKey, pubkey) else nip44Decrypt(content, privateKey, pubkey)
    }.getOrNull()

    private fun recompute() {
        val removedPubkeys = pending.removedPubkeys.toSet()
        val removedWords = pending.removedWords.toSet()
        val pubkeys = (remote.pubkeys + pending.addedPubkeys).distinct().filter { it !in removedPubkeys }
        val words = (remote.words + pending.addedWords).distinct().filter { it !in removedWords }
        val changed = pubkeys != mutedPubkeys || words != mutedWords
        mutedPubkeys = pubkeys
        mutedWords = words
        isLoaded = true
        Session.mutedPubkeys = pubkeys
        Session.mutedWords = words
        syncToRust()
        if (changed) {
            DataBus.feedChanged()
            DataBus.notificationsChanged()
            listeners.forEach { it() }
        }
    }

    private fun syncToRust() = setActiveMuteList(mutedPubkeys, mutedWords)
}

private data class RemoteMuteList(
    val publicTags: List<List<String>> = emptyList(),
    val privateTags: List<List<String>> = emptyList(),
    val isReadable: Boolean = true,
) {
    val pubkeys: List<String> get() = values("p")
    val words: List<String> get() = values("word").map { it.lowercase() }

    private fun values(name: String) = (publicTags + privateTags).filter { it.size > 1 && it[0] == name && it[1].isNotEmpty() }.map { it[1] }
}

private data class PendingMutes(
    val addedPubkeys: MutableList<String> = mutableListOf(),
    val removedPubkeys: MutableList<String> = mutableListOf(),
    val addedWords: MutableList<String> = mutableListOf(),
    val removedWords: MutableList<String> = mutableListOf(),
) {
    val isEmpty: Boolean get() = addedPubkeys.isEmpty() && removedPubkeys.isEmpty() && addedWords.isEmpty() && removedWords.isEmpty()

    fun copy() = PendingMutes(addedPubkeys.toMutableList(), removedPubkeys.toMutableList(), addedWords.toMutableList(), removedWords.toMutableList())

    fun subtract(published: PendingMutes) {
        addedPubkeys.removeAll(published.addedPubkeys)
        removedPubkeys.removeAll(published.removedPubkeys)
        addedWords.removeAll(published.addedWords)
        removedWords.removeAll(published.removedWords)
    }

    fun store(pubkey: String) {
        if (isEmpty) { Prefs.remove(key(pubkey)); return }
        val json = JSONObject()
            .put("addedPubkeys", JSONArray(addedPubkeys)).put("removedPubkeys", JSONArray(removedPubkeys))
            .put("addedWords", JSONArray(addedWords)).put("removedWords", JSONArray(removedWords))
        Prefs.set(key(pubkey), json.toString())
    }

    companion object {
        private fun key(pubkey: String) = "mute_pending_$pubkey"

        fun stored(pubkey: String): PendingMutes {
            val json = Json.obj(Prefs.string(key(pubkey))) ?: return PendingMutes()
            return PendingMutes(
                json.strings("addedPubkeys").toMutableList(), json.strings("removedPubkeys").toMutableList(),
                json.strings("addedWords").toMutableList(), json.strings("removedWords").toMutableList(),
            )
        }
    }
}

object HiddenNotesStore {
    private const val LIMIT = 2000

    fun ids(pubkey: String?): Set<String> = pubkey?.let { Prefs.stringList(key(it))?.toSet() } ?: emptySet()

    fun add(id: String, pubkey: String?) {
        if (pubkey == null || id.isEmpty()) return
        val list = Prefs.stringList(key(pubkey)).orEmpty().toMutableList()
        if (id in list) return
        list.add(id)
        Prefs.setStringList(key(pubkey), list.takeLast(LIMIT))
    }

    fun clear(pubkey: String) = Prefs.remove(key(pubkey))

    private fun key(pubkey: String) = "hidden_notes_$pubkey"
}
