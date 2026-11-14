package me.untreu.qiqstr.ui.dm

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.data.services.ReadOnlyGate
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle

@Immutable
sealed interface DMChatRow {
    val id: String

    data class Day(val start: Long) : DMChatRow {
        override val id: String get() = "day-$start"
    }

    data class Message(val message: DMMessage, val isFirstInGroup: Boolean, val isLastInGroup: Boolean) : DMChatRow {
        override val id: String get() = message.id
    }
}

sealed interface DMAttachmentState {
    object Preparing : DMAttachmentState
    data class Ready(val file: DMPreparedFile) : DMAttachmentState
}

data class DMAttachmentDraft(
    val id: String = UUID.randomUUID().toString(),
    val thumbnail: Bitmap? = null,
    val isVideo: Boolean,
    val state: DMAttachmentState = DMAttachmentState.Preparing,
) {
    val prepared: DMPreparedFile? get() = (state as? DMAttachmentState.Ready)?.file
}

class DMChatViewModel(val peer: String) : ViewModel() {
    var draft by mutableStateOf(TextFieldValue(""))
    var attachments by mutableStateOf<List<DMAttachmentDraft>>(emptyList())
        private set
    var sentCount by mutableIntStateOf(0)
        private set
    var failureCount by mutableIntStateOf(0)
        private set
    var focusRequest by mutableIntStateOf(0)
        private set
    var infoMessage by mutableStateOf<DMMessage?>(null)
    var searchQuery by mutableStateOf("")
        private set
    var matchIndex by mutableIntStateOf(0)
        private set
    private val service = DMService
    private val groupWindow = 300L

    val messages: List<DMMessage> get() = service.messages(peer)
    val isLoading: Boolean get() = !service.hasLoaded && messages.isEmpty()
    val isPreparingAttachment: Boolean get() = attachments.any { it.state == DMAttachmentState.Preparing }
    val isPeerUnavailable: Boolean get() = messages.isEmpty() && service.status(peer) == DMPeerStatus.UNAVAILABLE
    val isRequest: Boolean get() = service.isRequest(peer)
    val canLoadOlder: Boolean get() = !isSearching && service.canLoadOlder(peer)
    val isLoadingOlder: Boolean get() = peer in service.loadingOlder

    fun acceptRequest() = service.accept(peer)

    suspend fun loadOlder() = service.loadOlder(peer)

    val canSend: Boolean
        get() {
            val hasText = draft.text.isNotBlank()
            val hasReady = attachments.any { it.prepared != null }
            return (hasText || hasReady) && !isPreparingAttachment
        }

    fun rows(list: List<DMMessage>): List<DMChatRow> {
        val rows = ArrayList<DMChatRow>(list.size + 8)
        list.forEachIndexed { index, message ->
            val previous = list.getOrNull(index - 1)
            val next = list.getOrNull(index + 1)
            if (previous == null || !DMFormat.sameDay(previous.createdAt, message.createdAt)) rows.add(DMChatRow.Day(DMFormat.dayStart(message.createdAt)))
            val first = previous?.let { !grouped(it, message) } ?: true
            val last = next?.let { !grouped(message, it) } ?: true
            rows.add(DMChatRow.Message(message, first, last))
        }
        return rows
    }

    val trimmedSearch: String get() = searchQuery.trim()
    val isSearching: Boolean get() = trimmedSearch.isNotEmpty()

    val searchMatches: List<String>
        get() {
            val query = trimmedSearch
            if (query.isEmpty()) return emptyList()
            return messages.filter { !it.isFile && DMText.contains(it.content, query) }.map { it.id }
        }

    val currentMatchId: String?
        get() {
            val matches = searchMatches
            if (matches.isEmpty()) return null
            return matches[matchIndex.coerceIn(0, matches.size - 1)]
        }

    val matchPositionText: String
        get() {
            val matches = searchMatches
            if (matches.isEmpty()) return L("dmSearchNoMatches")
            return L("dmSearchPosition", "current" to minOf(matchIndex, matches.size - 1) + 1, "total" to matches.size)
        }

    fun updateSearch(value: String) {
        if (value == searchQuery) return
        searchQuery = value
        matchIndex = maxOf(searchMatches.size - 1, 0)
    }

    fun previousMatch() {
        val count = searchMatches.size
        if (count == 0) return
        matchIndex = (minOf(matchIndex, count - 1) - 1 + count) % count
    }

    fun nextMatch() {
        val count = searchMatches.size
        if (count == 0) return
        matchIndex = (minOf(matchIndex, count - 1) + 1) % count
    }

    fun quote(message: DMMessage) {
        val quoted = message.content.trim().lines().joinToString("\n") { "> $it" }
        val existing = draft.text.trim()
        val text = if (existing.isEmpty()) "$quoted\n\n" else "$quoted\n\n$existing"
        draft = TextFieldValue(text, TextRange(text.length))
        focusRequest += 1
    }

    fun showInfo(message: DMMessage) {
        infoMessage = message
    }

    fun deliveryRelays(message: DMMessage): List<String> = service.deliveryRelays[message.id].orEmpty()

    fun chatRelays(): List<String> = service.chatRelays(peer)

    private fun grouped(a: DMMessage, b: DMMessage): Boolean =
        a.isMine == b.isMine && b.createdAt - a.createdAt < groupWindow && DMFormat.sameDay(a.createdAt, b.createdAt) && a.state == b.state

    suspend fun appeared() {
        service.activePeer = peer
        service.start()
        service.markRead(peer)
        service.checkPeer(peer)
    }

    fun disappeared() {
        if (service.activePeer == peer) service.activePeer = null
        service.markRead(peer)
    }

    suspend fun poll() {
        var delaySeconds = 8L
        var lastCount = messages.size
        var lastSent = sentCount
        while (currentCoroutineContext().isActive) {
            delay(delaySeconds * 1000)
            service.refresh()
            val changed = messages.size != lastCount || sentCount != lastSent
            delaySeconds = if (changed) 8 else minOf(delaySeconds * 2, 60)
            lastCount = messages.size
            lastSent = sentCount
        }
    }

    suspend fun refresh() = service.refresh()

    fun send() {
        if (!ReadOnlyGate.check()) return
        val text = draft.text.trim()
        val files = attachments.mapNotNull { it.prepared }
        if (!canSend) return
        draft = TextFieldValue("")
        attachments = emptyList()
        sentCount += 1
        App.scope.launch {
            if (text.isNotEmpty()) perform { service.send(text, peer) }
            for (file in files) perform { service.sendPrepared(file, peer) }
        }
    }

    fun retry(message: DMMessage) {
        App.scope.launch { perform { service.retry(message) } }
    }

    fun discard(message: DMMessage) = service.discard(message)

    private suspend fun perform(work: suspend () -> Unit) {
        try {
            work()
        } catch (error: CancellationException) {
            return
        } catch (error: Throwable) {
            failureCount += 1
            ToastCenter.show(service.errorMessage(error), ToastStyle.ERROR)
        }
    }

    fun copy(message: DMMessage) {
        val clipboard = App.context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("message", message.content))
        ToastCenter.show(L("copiedToClipboard"), ToastStyle.SUCCESS)
    }

    fun removeAttachment(id: String) {
        attachments = attachments.filter { it.id != id }
    }

    fun handlePicked(uris: List<Uri>) {
        if (uris.isEmpty()) return
        if (!ReadOnlyGate.check()) return
        viewModelScope.launch {
            for (uri in uris) prepare(uri)
        }
    }

    private suspend fun prepare(uri: Uri) {
        val isVideo = DMMediaPrep.mimeType(uri)?.startsWith("video/") == true
        val draftItem = DMAttachmentDraft(isVideo = isVideo)
        attachments = attachments + draftItem
        val id = draftItem.id
        try {
            val picked = DMMediaPrep.load(uri, isVideo)
            if (picked.data.size > DMService.MAX_FILE_SIZE) throw DMMediaError(tooLarge = true)
            update(id) { it.copy(thumbnail = picked.thumbnail) }
            val prepared = service.prepareFile(picked.data, picked.mimeType, peer)
            update(id) { it.copy(state = DMAttachmentState.Ready(prepared)) }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            attachments = attachments.filter { it.id != id }
            val message = when {
                error is DMMediaError && error.tooLarge -> L("fileTooLarge")
                error is DMMediaError -> L("invalidMediaFileType")
                else -> service.errorMessage(error)
            }
            ToastCenter.show(message, ToastStyle.ERROR)
        }
    }

    private fun update(id: String, change: (DMAttachmentDraft) -> DMAttachmentDraft) {
        attachments = attachments.map { if (it.id == id) change(it) else it }
    }
}
