package me.untreu.qiqstr.ui.thread

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.data.services.FollowService
import me.untreu.qiqstr.data.services.InteractionService
import me.untreu.qiqstr.data.services.WebOfTrustService
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.ui.note.NoteContentCache
import me.untreu.qiqstr.ui.note.NoteInteractionStore
import me.untreu.qiqstr.ui.note.NoteRepository
import me.untreu.qiqstr.ui.note.NoteThreadData

sealed interface NoteThreadRow {
    val id: String

    data class Reply(val note: Note, val depth: Int, val hasChildren: Boolean) : NoteThreadRow {
        override val id get() = "r-${note.id}"
    }

    data class MoreReplies(val parentId: String, val hidden: Int, val depth: Int) : NoteThreadRow {
        override val id get() = "m-$parentId"
    }

    data class ContinueThread(val noteId: String, val count: Int, val depth: Int) : NoteThreadRow {
        override val id get() = "c-$noteId"
    }

    data class LoadMore(val remaining: Int) : NoteThreadRow {
        override val id get() = "load-more"
    }

    data class HiddenReplies(val count: Int) : NoteThreadRow {
        override val id get() = "hidden-replies"
    }
}

class ThreadViewModel(val noteId: String) : ViewModel() {
    companion object {
        const val MAX_DEPTH = 4
        const val MAX_NESTED = 3
        const val PAGE_SIZE = 20
    }

    var data by mutableStateOf<NoteThreadData?>(null)
        private set
    var placeholder by mutableStateOf<Note?>(null)
        private set
    var isLoading by mutableStateOf(true)
        private set
    var failed by mutableStateOf(false)
        private set
    var repliesSynced by mutableStateOf(false)
        private set
    var quoteCount by mutableIntStateOf(0)
        private set
    var rows by mutableStateOf<List<NoteThreadRow>>(emptyList())
        private set
    var showsUntrusted by mutableStateOf(false)
        private set
    private val expanded = HashSet<String>()
    private var visibleTopLevel = PAGE_SIZE
    private var hiddenCount = 0
    private val stableOrder = mutableListOf<String>()
    private var liveJob: Job? = null
    private var liveIds: Set<String> = emptySet()
    private var started = false

    val focused: Note? get() = data?.focused ?: placeholder
    val ancestors: List<Note> get() = data?.chain?.dropLast(1) ?: emptyList()

    suspend fun start() {
        if (started) return
        started = true
        if (placeholder == null) placeholder = NoteRepository.note(noteId)
        placeholder?.let { NoteInteractionStore.seed(listOf(it)) }
        NoteRepository.threadLocal(noteId)?.let { apply(it) }
        loadNetwork()
    }

    suspend fun loadNetwork() {
        failed = false
        try {
            val remote = NoteRepository.threadNetwork(noteId)
            if (remote != null) {
                apply(remote)
                NoteRepository.threadLocal(noteId)?.let { apply(it) }
            } else if (data == null) {
                failed = placeholder == null
            }
        } catch (cancel: kotlinx.coroutines.CancellationException) {
            throw cancel
        } catch (error: Throwable) {
            if (data == null && placeholder == null) failed = true
        }
        repliesSynced = true
        isLoading = false
        afterNetwork()
    }

    suspend fun refresh() = loadNetwork()

    suspend fun reloadLocal() {
        if (!started || !repliesSynced) return
        delay(250)
        NoteRepository.threadLocal(noteId)?.let { apply(it) }
    }

    private fun apply(thread: NoteThreadData) {
        data = thread
        isLoading = false
        rebuild()
        val notes = thread.allNotes
        NoteInteractionStore.seed(notes)
        viewModelScope.launch {
            NoteContentCache.warm(notes)
            ProfileCache.load(notes.map { it.pubkey }.distinct().filter { ProfileCache.profile(it) == null })
        }
    }

    private suspend fun afterNetwork() {
        val focused = focused ?: return
        quoteCount = NoteRepository.quoteCount(focused.id)
        val ids = listOf(focused.id) + rows.mapNotNull { (it as? NoteThreadRow.Reply)?.note?.id }
        startLiveCounts(ids.take(120))
        viewModelScope.launch {
            SyncService.syncInteractions(listOf(focused.id))
            NoteInteractionStore.requestCounts(listOf(focused.id), relays = false)
        }
        viewModelScope.launch {
            NoteRepository.fetchQuotesFromRelays(focused.id)
            quoteCount = NoteRepository.quoteCount(focused.id)
        }
    }

    private fun startLiveCounts(ids: List<String>) {
        val wanted = ids.toSet()
        if (liveIds.containsAll(wanted)) return
        liveIds = wanted
        liveJob?.cancel()
        liveJob = viewModelScope.launch {
            runCatching { InteractionService.liveCounts(ids).collect { NoteInteractionStore.applyLive(it) } }
        }
    }

    fun stop() {
        liveJob?.cancel()
        liveJob = null
        liveIds = emptySet()
    }

    override fun onCleared() {
        stop()
    }

    fun expand(parentId: String) {
        expanded.add(parentId)
        rebuild()
    }

    fun revealHidden() {
        showsUntrusted = true
        rebuild()
    }

    private val filtersUntrusted: Boolean
        get() = WebOfTrustService.filtersReplies && !showsUntrusted && WebOfTrustService.isReady

    private fun rank(note: Note, me: String?): Int = when {
        note.pubkey == me -> 0
        FollowService.isFollowing(note.pubkey) -> 1
        else -> 2
    }

    fun showMoreTopLevel() {
        visibleTopLevel += PAGE_SIZE
        rebuild()
    }

    private fun sortedChildren(id: String, stable: Boolean): List<Note> {
        val children = data?.children?.get(id) ?: return emptyList()
        val me = Session.pubkey
        val deleted = NoteInteractionStore.deletedIds
        val muted = Session.mutedPubkeys.toSet()
        val author = data?.focused?.pubkey
        val filters = filtersUntrusted
        val visible = mutableListOf<Note>()
        for (note in children) {
            if (note.id in deleted || note.pubkey in muted) continue
            if (filters && note.pubkey != me && note.pubkey != author && !WebOfTrustService.isTrusted(note.pubkey)) {
                hiddenCount += 1
            } else {
                visible.add(note)
            }
        }
        val sorted = visible.sortedWith { a, b ->
            val ra = rank(a, me)
            val rb = rank(b, me)
            if (ra != rb) return@sortedWith ra.compareTo(rb)
            val sa = WebOfTrustService.score(a.pubkey)
            val sb = WebOfTrustService.score(b.pubkey)
            if (sa != sb) return@sortedWith sb.compareTo(sa)
            a.createdAt.compareTo(b.createdAt)
        }
        if (!stable) return sorted
        val byId = LinkedHashMap<String, Note>()
        for (note in sorted) if (!byId.containsKey(note.id)) byId[note.id] = note
        stableOrder.removeAll { it !in byId }
        val newOnes = sorted.filter { it.id !in stableOrder }
        val ordered = if (stableOrder.isEmpty()) newOnes else newOnes.sortedBy { it.createdAt }
        stableOrder.addAll(ordered.map { it.id })
        return stableOrder.mapNotNull { byId[it] }
    }

    fun rebuild() {
        val focused = data?.focused
        if (focused == null) {
            rows = emptyList()
            return
        }
        val result = mutableListOf<NoteThreadRow>()
        hiddenCount = 0
        val top = sortedChildren(focused.id, stable = true)
        for (note in top.take(visibleTopLevel)) flatten(note, 0, result)
        if (top.size > visibleTopLevel) result.add(NoteThreadRow.LoadMore(top.size - visibleTopLevel))
        if (hiddenCount > 0) result.add(NoteThreadRow.HiddenReplies(hiddenCount))
        rows = result
    }

    private fun flatten(note: Note, depth: Int, result: MutableList<NoteThreadRow>) {
        val kids = sortedChildren(note.id, stable = false)
        result.add(NoteThreadRow.Reply(note, depth, kids.isNotEmpty() && depth < MAX_DEPTH))
        if (kids.isEmpty()) return
        if (depth < MAX_DEPTH) {
            val shown = if (note.id in expanded) kids else kids.take(MAX_NESTED)
            for (kid in shown) flatten(kid, depth + 1, result)
            if (kids.size > shown.size) result.add(NoteThreadRow.MoreReplies(note.id, kids.size - shown.size, depth + 1))
        } else {
            result.add(NoteThreadRow.ContinueThread(note.id, kids.size, depth + 1))
        }
    }
}
