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
import me.untreu.qiqstr.domain.Note
import org.json.JSONArray
import org.json.JSONObject

object MuteService {
    var mutedPubkeys by mutableStateOf<List<String>>(emptyList())
        private set
    var mutedWords by mutableStateOf<List<String>>(emptyList())
        private set
    var mutedHashtags by mutableStateOf<List<String>>(emptyList())
        private set
    var mutedThreads by mutableStateOf<List<String>>(emptyList())
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

    fun isHashtagMuted(tag: String) = normalizedHashtag(tag) in mutedHashtags

    fun isThreadMuted(rootId: String) = rootId in mutedThreads

    fun hides(note: Note): Boolean {
        if (mutedThreads.isNotEmpty() && ((note.rootId ?: note.id) in mutedThreads || note.id in mutedThreads)) return true
        if (mutedHashtags.isEmpty()) return false
        return note.hashtags.any { it.lowercase() in mutedHashtags }
    }

    fun hidesNotification(target: String?, root: String?): Boolean {
        if (mutedThreads.isEmpty()) return false
        return listOfNotNull(target, root).any { it in mutedThreads }
    }

    fun normalizedHashtag(tag: String): String = tag.trim().lowercase().trim('#')

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
        mutedHashtags = emptyList()
        mutedThreads = emptyList()
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
        perform(true, MuteEntry.PUBKEY, pubkey)
    }

    suspend fun unmute(pubkey: String) = perform(false, MuteEntry.PUBKEY, pubkey)

    suspend fun addWord(word: String) {
        val normalized = word.trim().lowercase()
        if (normalized.isEmpty()) return
        perform(true, MuteEntry.WORD, normalized)
    }

    suspend fun removeWord(word: String) = perform(false, MuteEntry.WORD, word.trim().lowercase())

    suspend fun muteHashtag(tag: String) {
        val normalized = normalizedHashtag(tag)
        if (normalized.isEmpty()) return
        perform(true, MuteEntry.HASHTAG, normalized)
    }

    suspend fun unmuteHashtag(tag: String) = perform(false, MuteEntry.HASHTAG, normalizedHashtag(tag))

    suspend fun muteThread(rootId: String) {
        if (rootId.length != 64) return
        perform(true, MuteEntry.THREAD, rootId)
    }

    suspend fun unmuteThread(rootId: String) = perform(false, MuteEntry.THREAD, rootId)

    private fun current(entry: MuteEntry): List<String> = when (entry) {
        MuteEntry.PUBKEY -> mutedPubkeys
        MuteEntry.WORD -> mutedWords
        MuteEntry.HASHTAG -> mutedHashtags
        MuteEntry.THREAD -> mutedThreads
    }

    private suspend fun perform(adding: Boolean, entry: MuteEntry, value: String) {
        val me = Session.pubkey ?: return
        if ((value in current(entry)) == adding) return
        if (adding) {
            pending.removed(entry).removeAll { it == value }
            pending.added(entry).add(value)
        } else {
            pending.added(entry).removeAll { it == value }
            pending.removed(entry).add(value)
        }
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
        val keep: (List<String>) -> Boolean = { tag ->
            val entry = if (tag.size > 1) MuteEntry.from(tag[0]) else null
            entry == null || entry.normalized(tag[1]) !in changes.removed[entry.raw].orEmpty()
        }
        val publicTags = base.publicTags.filter(keep)
        val privateTags = base.privateTags.filter(keep).toMutableList()
        val known = RemoteMuteList(publicTags, privateTags.toList())
        for (entry in MuteEntry.entries) {
            val existing = known.values(entry).toSet()
            privateTags += changes.added[entry.raw].orEmpty().filter { it !in existing }.map { listOf(entry.raw, it) }
        }
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

    private fun merged(entry: MuteEntry): List<String> {
        val removed = pending.removed[entry.raw].orEmpty().toSet()
        return (remote.values(entry) + pending.added[entry.raw].orEmpty()).distinct().filter { it !in removed }
    }

    private fun recompute() {
        val pubkeys = merged(MuteEntry.PUBKEY)
        val words = merged(MuteEntry.WORD)
        val hashtags = merged(MuteEntry.HASHTAG)
        val threads = merged(MuteEntry.THREAD)
        val changed = pubkeys != mutedPubkeys || words != mutedWords || hashtags != mutedHashtags || threads != mutedThreads
        mutedPubkeys = pubkeys
        mutedWords = words
        mutedHashtags = hashtags
        mutedThreads = threads
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

enum class MuteEntry(val raw: String) {
    PUBKEY("p"), WORD("word"), HASHTAG("t"), THREAD("e");

    fun normalized(value: String): String = when (this) {
        PUBKEY, THREAD -> value
        WORD, HASHTAG -> value.lowercase()
    }

    companion object {
        fun from(raw: String) = entries.firstOrNull { it.raw == raw }
    }
}

private data class RemoteMuteList(
    val publicTags: List<List<String>> = emptyList(),
    val privateTags: List<List<String>> = emptyList(),
    val isReadable: Boolean = true,
) {
    fun values(entry: MuteEntry): List<String> =
        (publicTags + privateTags).filter { it.size > 1 && it[0] == entry.raw && it[1].isNotEmpty() }.map { entry.normalized(it[1]) }
}

private class PendingMutes(
    val added: MutableMap<String, MutableList<String>> = mutableMapOf(),
    val removed: MutableMap<String, MutableList<String>> = mutableMapOf(),
) {
    val isEmpty: Boolean get() = added.values.all { it.isEmpty() } && removed.values.all { it.isEmpty() }

    fun added(entry: MuteEntry): MutableList<String> = added.getOrPut(entry.raw) { mutableListOf() }

    fun removed(entry: MuteEntry): MutableList<String> = removed.getOrPut(entry.raw) { mutableListOf() }

    fun copy() = PendingMutes(
        added.mapValuesTo(mutableMapOf()) { it.value.toMutableList() },
        removed.mapValuesTo(mutableMapOf()) { it.value.toMutableList() },
    )

    fun subtract(published: PendingMutes) {
        for ((key, values) in published.added) added[key]?.removeAll(values)
        for ((key, values) in published.removed) removed[key]?.removeAll(values)
    }

    fun store(pubkey: String) {
        if (isEmpty) { Prefs.remove(key(pubkey)); return }
        Prefs.set(key(pubkey), JSONObject().put("added", encoded(added)).put("removed", encoded(removed)).toString())
    }

    companion object {
        private val legacy = listOf(
            Triple("addedPubkeys", MuteEntry.PUBKEY, true), Triple("removedPubkeys", MuteEntry.PUBKEY, false),
            Triple("addedWords", MuteEntry.WORD, true), Triple("removedWords", MuteEntry.WORD, false),
        )

        private fun key(pubkey: String) = "mute_pending_$pubkey"

        private fun encoded(map: Map<String, List<String>>) = JSONObject().apply { map.forEach { (name, values) -> put(name, JSONArray(values)) } }

        private fun decoded(json: JSONObject?): MutableMap<String, MutableList<String>> {
            val result = mutableMapOf<String, MutableList<String>>()
            if (json != null) for (name in json.keys()) result[name] = json.strings(name).toMutableList()
            return result
        }

        fun stored(pubkey: String): PendingMutes {
            val json = Json.obj(Prefs.string(key(pubkey))) ?: return PendingMutes()
            val pending = PendingMutes(decoded(json.optJSONObject("added")), decoded(json.optJSONObject("removed")))
            for ((name, entry, isAdded) in legacy) {
                val values = json.strings(name)
                if (values.isEmpty()) continue
                (if (isAdded) pending.added(entry) else pending.removed(entry)).addAll(values)
            }
            return pending
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
