package me.untreu.qiqstr.ui.note

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.data.services.CustomEmoji
import me.untreu.qiqstr.App
import me.untreu.qiqstr.data.services.HiddenNotesStore
import me.untreu.qiqstr.data.services.InteractionCounts
import me.untreu.qiqstr.data.services.InteractionService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Note

@Stable
class NoteCountsModel(val noteId: String, counts: InteractionCounts) {
    var counts by mutableStateOf(counts)
    var isReacting by mutableStateOf(false)
    var isReposting by mutableStateOf(false)
    var myReaction by mutableStateOf<String?>(null)
    var myReactionEmoji by mutableStateOf<CustomEmoji?>(null)
    var lastUserAction: Long? = null

    val userActionActive: Boolean
        get() = lastUserAction?.let { System.currentTimeMillis() - it < 30_000 } ?: false
}

object NoteInteractionStore {
    var deletedIds by mutableStateOf<Set<String>>(emptySet())
        private set
    private val models = LinkedHashMap<String, NoteCountsModel>()
    private val pendingLocal = HashSet<String>()
    private val pendingRelay = HashSet<String>()
    private val relayFetchedAt = HashMap<String, Long>()
    private var localJob: Job? = null
    private var relayJob: Job? = null
    private var owner: String? = null
    private var ownerInitialized = false
    private const val CAPACITY = 3000

    fun model(note: Note): NoteCountsModel {
        resetIfAccountChanged()
        models[note.id]?.let { return it }
        val model = NoteCountsModel(note.id, InteractionCounts.from(note))
        models[note.id] = model
        evict()
        return model
    }

    fun seed(notes: List<Note>) {
        resetIfAccountChanged()
        for (note in notes) {
            val existing = models[note.id]
            if (existing != null) {
                if (!existing.userActionActive) apply(InteractionCounts.from(note), existing, authoritative = false)
            } else {
                model(note)
            }
        }
    }

    fun requestCounts(noteIds: List<String>, relays: Boolean = true) {
        val ids = noteIds.filter { it.isNotEmpty() }
        if (ids.isEmpty()) return
        pendingLocal.addAll(ids)
        scheduleLocal()
        if (!relays) return
        val now = System.currentTimeMillis()
        val due = ids.filter { id -> relayFetchedAt[id]?.let { now - it > 300_000 } ?: true }
        if (due.isEmpty()) return
        pendingRelay.addAll(due)
        scheduleRelay()
    }

    fun refreshAll() = requestCounts(models.keys.toList().takeLast(400), relays = false)

    fun applyLive(map: Map<String, InteractionCounts>) {
        for ((id, counts) in map) models[id]?.let { apply(counts, it, authoritative = false) }
    }

    private fun scheduleLocal() {
        localJob?.cancel()
        localJob = App.scope.launch {
            delay(40)
            val batch = pendingLocal.toList()
            pendingLocal.clear()
            for (chunk in batch.chunked(60)) {
                val result = InteractionService.localCounts(chunk)
                for ((id, counts) in result) models[id]?.let { apply(counts, it, authoritative = false) }
            }
        }
    }

    private fun scheduleRelay() {
        relayJob?.cancel()
        relayJob = App.scope.launch {
            delay(350)
            val batch = pendingRelay.toList()
            pendingRelay.clear()
            val now = System.currentTimeMillis()
            batch.forEach { relayFetchedAt[it] = now }
            coroutineScope {
                batch.chunked(40).map { chunk ->
                    async {
                        val result = InteractionService.relayCounts(chunk)
                        for ((id, counts) in result) models[id]?.let { apply(counts, it, authoritative = false) }
                    }
                }.awaitAll()
            }
        }
    }

    private fun apply(fresh: InteractionCounts, model: NoteCountsModel, authoritative: Boolean) {
        if (model.userActionActive) return
        val old = model.counts
        val next = if (!authoritative) {
            InteractionCounts(
                reactions = maxOf(fresh.reactions, old.reactions),
                reposts = maxOf(fresh.reposts, old.reposts),
                replies = maxOf(fresh.replies, old.replies),
                zapAmount = maxOf(fresh.zapAmount, old.zapAmount),
                hasReacted = fresh.hasReacted || old.hasReacted,
                hasReposted = fresh.hasReposted || old.hasReposted,
                hasZapped = fresh.hasZapped || old.hasZapped,
            )
        } else {
            fresh.copy(reactions = maxOf(fresh.reactions, if (fresh.hasReacted) 1 else 0))
        }
        if (next != old) model.counts = next
    }

    suspend fun toggleReaction(note: Note, content: String = "+", emoji: CustomEmoji? = null) {
        val model = model(note)
        if (model.isReacting) return
        model.isReacting = true
        try {
            val wasReacted = model.counts.hasReacted
            val previousReaction = model.myReaction
            val previousEmoji = model.myReactionEmoji
            model.lastUserAction = System.currentTimeMillis()
            model.counts = model.counts.copy(hasReacted = !wasReacted, reactions = maxOf(0, model.counts.reactions + if (wasReacted) -1 else 1))
            model.myReaction = if (wasReacted) null else content
            model.myReactionEmoji = if (wasReacted) null else emoji
            try {
                if (wasReacted) InteractionService.unreact(note) else InteractionService.react(note, content, emoji)
            } catch (error: Throwable) {
                model.counts = model.counts.copy(hasReacted = wasReacted, reactions = maxOf(0, model.counts.reactions + if (wasReacted) 1 else -1))
                model.myReaction = previousReaction
                model.myReactionEmoji = previousEmoji
                model.lastUserAction = null
                ToastCenter.error(error)
            }
        } finally {
            model.isReacting = false
        }
    }

    suspend fun react(note: Note, content: String, emoji: CustomEmoji? = null) {
        val model = model(note)
        if (model.counts.hasReacted) {
            if (model.myReaction == content) return
            toggleReaction(note)
            if (model.counts.hasReacted) return
        }
        toggleReaction(note, content, emoji)
    }

    suspend fun toggleRepost(note: Note) {
        val model = model(note)
        if (model.isReposting) return
        model.isReposting = true
        try {
            val wasReposted = model.counts.hasReposted
            model.lastUserAction = System.currentTimeMillis()
            model.counts = model.counts.copy(hasReposted = !wasReposted, reposts = maxOf(0, model.counts.reposts + if (wasReposted) -1 else 1))
            try {
                if (wasReposted) InteractionService.undoRepost(note) else InteractionService.repost(note)
            } catch (error: Throwable) {
                model.counts = model.counts.copy(hasReposted = wasReposted, reposts = maxOf(0, model.counts.reposts + if (wasReposted) 1 else -1))
                model.lastUserAction = null
                ToastCenter.error(error)
            }
        } finally {
            model.isReposting = false
        }
    }

    suspend fun repostAgain(note: Note) {
        val model = model(note)
        model.lastUserAction = System.currentTimeMillis()
        model.counts = model.counts.copy(reposts = model.counts.reposts + 1)
        try {
            InteractionService.repost(note)
        } catch (error: Throwable) {
            model.counts = model.counts.copy(reposts = maxOf(0, model.counts.reposts - 1))
            ToastCenter.error(error)
        }
    }

    suspend fun markReplied(noteId: String) {
        val model = models[noteId] ?: return
        val local = InteractionService.localCounts(listOf(noteId))[noteId]?.replies ?: 0
        model.lastUserAction = System.currentTimeMillis()
        model.counts = model.counts.copy(replies = maxOf(local, model.counts.replies, 1))
    }

    fun markDeleted(noteId: String, parent: String? = null) {
        deletedIds = deletedIds + noteId
        adjustReplies(parent, -1)
    }

    fun unmarkDeleted(noteId: String, parent: String? = null) {
        deletedIds = deletedIds - noteId
        adjustReplies(parent, 1)
    }

    private fun adjustReplies(parent: String?, delta: Int) {
        val model = parent?.let { models[it] } ?: return
        model.lastUserAction = System.currentTimeMillis()
        model.counts = model.counts.copy(replies = maxOf(0, model.counts.replies + delta))
    }

    fun isDeleted(noteId: String) = noteId in deletedIds

    fun hide(noteId: String, parent: String? = null) {
        if (noteId.isEmpty()) return
        resetIfAccountChanged()
        HiddenNotesStore.add(noteId, owner)
        if (noteId in deletedIds) return
        markDeleted(noteId, parent)
    }

    fun prepareForAccount() = resetIfAccountChanged()

    private fun resetIfAccountChanged() {
        val me = Session.pubkey
        if (ownerInitialized && me == owner) return
        ownerInitialized = true
        owner = me
        models.clear()
        pendingLocal.clear()
        pendingRelay.clear()
        relayFetchedAt.clear()
        val hidden = HiddenNotesStore.ids(me)
        if (deletedIds != hidden) deletedIds = hidden
    }

    private fun evict() {
        while (models.size > CAPACITY) models.remove(models.keys.first())
    }
}
