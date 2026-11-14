package me.untreu.qiqstr.ui.compose

import android.graphics.Bitmap
import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.ComposeContext
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.services.FollowService
import me.untreu.qiqstr.data.services.InteractionService
import me.untreu.qiqstr.data.services.SearchService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.note.BlurHash
import me.untreu.qiqstr.ui.note.NoteInteractionStore
import me.untreu.qiqstr.ui.note.NoteRepository

sealed interface AttachmentStatus {
    object Uploading : AttachmentStatus
    data class Uploaded(val media: UploadedMedia) : AttachmentStatus
    data class Failed(val reason: String) : AttachmentStatus
}

class ComposeAttachment(
    val preview: Bitmap?,
    val isVideo: Boolean,
    val width: Int?,
    val height: Int?,
    val blurhash: String? = null,
    val remoteURL: String? = null,
) {
    val id: String = UUID.randomUUID().toString()
    var status by mutableStateOf<AttachmentStatus>(AttachmentStatus.Uploading)
    var altText by mutableStateOf("")
    var payload: Pair<ByteArray, String>? = null

    val trimmedAlt: String? get() = altText.trim().ifEmpty { null }
    val uploaded: UploadedMedia? get() = (status as? AttachmentStatus.Uploaded)?.media
}

class ComposePollOption(text: String = "") {
    val id: String = UUID.randomUUID().toString()
    var text by mutableStateOf(text)
}

class ComposeViewModel(val context: ComposeContext) : ViewModel() {
    companion object {
        const val MIN_POLL_OPTIONS = 2
        const val MAX_POLL_OPTIONS = 6
        const val MAX_ATTACHMENTS = 8
        const val MAX_FILE_SIZE = 50 * 1024 * 1024
    }

    var input by mutableStateOf(TextFieldValue(""))
        private set
    val text: String get() = input.text
    var contentWarningEnabled by mutableStateOf(false)
    var contentWarningReason by mutableStateOf("")
    var pollEnabled by mutableStateOf(false)
    val pollOptions = mutableStateListOf(ComposePollOption(), ComposePollOption())
    var pollMultiple by mutableStateOf(false)
    var pollHasEnd by mutableStateOf(false)
    var pollEndsAt by mutableStateOf(TimeFormat.now + 86400)
    var draftId by mutableStateOf(UUID.randomUUID().toString())
        private set
    val attachments = mutableStateListOf<ComposeAttachment>()
    var suggestions by mutableStateOf<List<Profile>>(emptyList())
        private set
    var isPosting by mutableStateOf(false)
        private set
    var didPost by mutableIntStateOf(0)
        private set
    private var mentionMap: MutableMap<String, String> = mutableMapOf()
    private var mentionRange: IntRange? = null
    private var searchJob: Job? = null
    private var lastQuery: String? = null
    private var saveJob: Job? = null
    private var finished = false

    init {
        val pending = DraftStore.pendingDraftId?.let { DraftStore.draft(it) }
        DraftStore.pendingDraftId = null
        val draft = if (pending?.contextKey == contextKey) pending else DraftStore.latest(contextKey)
        if (draft != null) apply(draft)
    }

    val contextKey: String
        get() = when (val c = context) {
            ComposeContext.NewNote -> "new"
            is ComposeContext.Reply -> "reply-${c.note.id}"
            is ComposeContext.Quote -> "quote-${c.note.id}"
        }

    val supportsPoll: Boolean get() = context == ComposeContext.NewNote

    val otherDrafts: List<ComposeDraft> get() = DraftStore.drafts.filter { it.id != draftId }

    private val validPollOptions: List<String>
        get() {
            val seen = HashSet<String>()
            return pollOptions.map { it.text.trim() }.filter { it.isNotEmpty() && seen.add(it.lowercase()) }
        }

    val target: Note?
        get() = when (val c = context) {
            ComposeContext.NewNote -> null
            is ComposeContext.Reply -> c.note
            is ComposeContext.Quote -> c.note
        }

    val draftSnapshot: ComposeDraft
        get() {
            val kind = when (context) {
                ComposeContext.NewNote -> ComposeDraft.Kind.NEW_NOTE
                is ComposeContext.Reply -> ComposeDraft.Kind.REPLY
                is ComposeContext.Quote -> ComposeDraft.Kind.QUOTE
            }
            val media = attachments.mapNotNull { attachment ->
                val item = attachment.uploaded ?: return@mapNotNull null
                ComposeDraftMedia(item.url, item.sha256, item.mimeType, item.size, attachment.width?.toDouble(), attachment.height?.toDouble(), attachment.blurhash, attachment.altText, attachment.isVideo)
            }
            val poll = if (pollEnabled) ComposeDraftPoll(pollOptions.map { it.text }, pollMultiple, if (pollHasEnd) pollEndsAt else null) else null
            return ComposeDraft(draftId, kind, target?.id, target?.pubkey, text, mentionMap.toMap(), media, contentWarningEnabled, contentWarningReason, poll, 0)
        }

    private fun apply(draft: ComposeDraft) {
        draftId = draft.id
        mentionMap = draft.mentions.toMutableMap()
        input = TextFieldValue(draft.text, TextRange(draft.text.length))
        contentWarningEnabled = draft.contentWarningEnabled
        contentWarningReason = draft.contentWarningReason
        attachments.clear()
        attachments.addAll(draft.media.map { item ->
            ComposeAttachment(null, item.isVideo, item.width?.toInt(), item.height?.toInt(), item.blurhash, item.url).apply {
                status = AttachmentStatus.Uploaded(UploadedMedia(item.url, item.sha256, item.mimeType, item.size))
                altText = item.altText
            }
        })
        val poll = draft.poll
        if (poll != null && supportsPoll) {
            pollEnabled = true
            val options = poll.options.map { ComposePollOption(it) }.toMutableList()
            while (options.size < MIN_POLL_OPTIONS) options.add(ComposePollOption())
            pollOptions.clear()
            pollOptions.addAll(options.take(MAX_POLL_OPTIONS))
            pollMultiple = poll.multiple
            pollHasEnd = poll.endsAt != null
            pollEndsAt = poll.endsAt ?: (TimeFormat.now + 86400)
        } else {
            pollEnabled = false
            pollOptions.clear()
            pollOptions.addAll(listOf(ComposePollOption(), ComposePollOption()))
            pollMultiple = false
            pollHasEnd = false
        }
        clearSuggestions()
    }

    fun updateField(value: TextFieldValue) {
        val changed = value.text != input.text || value.selection != input.selection
        input = value
        if (changed) updateMentionQuery()
        scheduleSave()
    }

    fun scheduleSave() {
        if (finished) return
        saveJob?.cancel()
        saveJob = viewModelScope.launch {
            delay(700)
            saveDraft()
        }
    }

    fun saveDraft() {
        saveJob?.cancel()
        if (finished) return
        if (hasContent) DraftStore.save(draftSnapshot.copy(updatedAt = System.currentTimeMillis()))
        else DraftStore.delete(draftId)
    }

    fun finishSaving() {
        saveDraft()
        finished = true
    }

    fun deleteDraft() {
        saveJob?.cancel()
        finished = true
        DraftStore.delete(draftId)
    }

    fun deleteDraft(id: String) = DraftStore.delete(id)

    fun open(draft: ComposeDraft) {
        saveDraft()
        if (draft.contextKey == contextKey) {
            apply(draft)
            return
        }
        viewModelScope.launch {
            val next: ComposeContext = when (draft.kind) {
                ComposeDraft.Kind.NEW_NOTE -> ComposeContext.NewNote
                ComposeDraft.Kind.REPLY, ComposeDraft.Kind.QUOTE -> {
                    val id = draft.targetId
                    val note = id?.let { NoteRepository.ensureNote(it) }
                    if (note == null) {
                        ToastCenter.show(L("eventNotFound"), ToastStyle.ERROR)
                        return@launch
                    }
                    if (draft.kind == ComposeDraft.Kind.REPLY) ComposeContext.Reply(note) else ComposeContext.Quote(note)
                }
            }
            finished = true
            DraftStore.pendingDraftId = draft.id
            Router.composeContext = next
        }
    }

    fun togglePoll() {
        pollEnabled = !pollEnabled
        scheduleSave()
    }

    fun addPollOption() {
        if (pollOptions.size >= MAX_POLL_OPTIONS) return
        pollOptions.add(ComposePollOption())
        scheduleSave()
    }

    fun removePollOption(option: ComposePollOption) {
        if (pollOptions.size <= MIN_POLL_OPTIONS) return
        pollOptions.removeAll { it.id == option.id }
        scheduleSave()
    }

    val isUploading: Boolean get() = attachments.any { it.status == AttachmentStatus.Uploading }

    val hasContent: Boolean
        get() = text.isNotBlank() || attachments.isNotEmpty() || (pollEnabled && pollOptions.any { it.text.isNotBlank() })

    val isPollActive: Boolean get() = pollEnabled && supportsPoll

    val canPost: Boolean
        get() {
            if (isPosting || isUploading) return false
            if (isPollActive) return text.isNotBlank() && validPollOptions.size >= MIN_POLL_OPTIONS && (!pollHasEnd || pollEndsAt > TimeFormat.now)
            if (context is ComposeContext.Quote) return true
            return text.isNotBlank() || attachments.any { it.uploaded != null }
        }

    val title: String
        get() = when (context) {
            ComposeContext.NewNote -> L("newPost")
            is ComposeContext.Reply -> L("reply")
            is ComposeContext.Quote -> L("quote")
        }

    val placeholder: String
        get() {
            if (isPollActive) return L("feedPollQuestion")
            return when (context) {
                is ComposeContext.Reply -> L("addAReply")
                else -> L("hintText")
            }
        }

    private fun updateMentionQuery() {
        val value = input
        val end = value.selection.end.coerceIn(0, value.text.length)
        val prefix = value.text.substring(0, end)
        val at = prefix.lastIndexOf('@')
        if (at < 0) { clearSuggestions(); return }
        val token = prefix.substring(at + 1)
        val before = if (at == 0) null else value.text[at - 1]
        if (!(before == null || before.isWhitespace()) || token.any { it.isWhitespace() || it == '@' } || token.length > 32) {
            clearSuggestions()
            return
        }
        mentionRange = at until end
        if (token.isEmpty()) { suggestions = emptyList(); lastQuery = null; return }
        if (token == lastQuery) return
        lastQuery = token
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(180)
            val results = NoteRepository.searchProfiles(token, 8)
            val follows = FollowService.following.toSet()
            suggestions = results.sortedWith { a, b ->
                val af = a.pubkey in follows
                val bf = b.pubkey in follows
                if (af != bf) (if (af) -1 else 1) else a.bestName.length.compareTo(b.bestName.length)
            }
        }
    }

    private fun clearSuggestions() {
        mentionRange = null
        lastQuery = null
        searchJob?.cancel()
        if (suggestions.isNotEmpty()) suggestions = emptyList()
    }

    fun insertMention(profile: Profile) {
        val range = mentionRange ?: return
        if (range.last + 1 > text.length) return
        val npub = Nip19.npub(profile.pubkey) ?: return
        val name = profile.bestName.replace("\n", " ")
        val key = "@$name"
        mentionMap[key] = "nostr:$npub"
        val replaced = text.replaceRange(range.first, range.last + 1, "$key ")
        val cursor = minOf(range.first + key.length + 1, replaced.length)
        input = TextFieldValue(replaced, TextRange(cursor))
        clearSuggestions()
        ProfileCache.set(profile)
        scheduleSave()
    }

    fun handlePicked(uris: List<Uri>) {
        val room = maxOf(0, MAX_ATTACHMENTS - attachments.size)
        viewModelScope.launch {
            for (uri in uris.take(room)) add(uri)
        }
    }

    private suspend fun add(uri: Uri) {
        val resolver = App.context.contentResolver
        val type = resolver.getType(uri)
        val isVideo = type?.startsWith("video/") == true
        var mime = type ?: if (isVideo) "video/mp4" else "image/jpeg"
        var preview: Bitmap? = null
        var width: Int? = null
        var height: Int? = null
        val payload: ByteArray
        if (isVideo) {
            if (fileSize(uri) > MAX_FILE_SIZE) {
                ToastCenter.show(L("fileTooLarge"), ToastStyle.ERROR)
                return
            }
            val stripped = MediaSanitizer.strippedVideo(uri)
            if (stripped == null) {
                ToastCenter.show(L("errorSelectingMedia"), ToastStyle.ERROR)
                return
            }
            payload = stripped
            mime = "video/mp4"
        } else {
            val data = withContext(Dispatchers.IO) { runCatching { resolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull() }
            if (data == null) {
                ToastCenter.show(L("errorSelectingMedia"), ToastStyle.ERROR)
                return
            }
            val inputMime = mime
            val prepared = withContext(Dispatchers.Default) { runCatching { MediaSanitizer.prepareImage(data, inputMime) }.getOrNull() }
            if (prepared == null) {
                ToastCenter.show(L("invalidMediaFileType"), ToastStyle.ERROR)
                return
            }
            payload = prepared.bytes
            mime = prepared.mimeType
            preview = prepared.preview
            width = prepared.width
            height = prepared.height
        }
        if (payload.size > MAX_FILE_SIZE) {
            ToastCenter.show(L("fileTooLarge"), ToastStyle.ERROR)
            return
        }
        val blurhash = preview?.let { bitmap -> withContext(Dispatchers.Default) { runCatching { BlurHash.encode(bitmap) }.getOrNull() } }
        val attachment = ComposeAttachment(preview, isVideo, width, height, blurhash)
        attachment.payload = payload to mime
        attachments.add(attachment)
        upload(attachment)
    }

    private suspend fun fileSize(uri: Uri): Long = withContext(Dispatchers.IO) {
        runCatching {
            App.context.contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else 0L
            } ?: 0L
        }.getOrDefault(0L)
    }

    fun retry(attachment: ComposeAttachment) {
        viewModelScope.launch { upload(attachment) }
    }

    private suspend fun upload(attachment: ComposeAttachment) {
        val (data, mime) = attachment.payload ?: return
        attachment.status = AttachmentStatus.Uploading
        try {
            val media = MediaUploadService.uploadMedia(data, mime)
            attachment.status = AttachmentStatus.Uploaded(media)
            attachment.payload = null
            scheduleSave()
        } catch (error: Throwable) {
            attachment.status = AttachmentStatus.Failed(coreErrorMessage(error))
            ToastCenter.show(L("mediaUploadFailed"), ToastStyle.ERROR)
        }
    }

    private val contentWarningTags: List<List<String>>
        get() {
            if (!contentWarningEnabled) return emptyList()
            val reason = contentWarningReason.trim()
            return listOf(if (reason.isEmpty()) listOf("content-warning") else listOf("content-warning", reason))
        }

    fun remove(attachment: ComposeAttachment) {
        attachments.removeAll { it.id == attachment.id }
        scheduleSave()
    }

    private fun finalContent(): String {
        var content = text
        for (key in mentionMap.keys.sortedByDescending { it.length }) {
            mentionMap[key]?.let { content = content.replace(key, it) }
        }
        return content.trim()
    }

    suspend fun post(): Boolean {
        if (!canPost) {
            if (!hasContent) ToastCenter.show(L("emptyNoteMessage"), ToastStyle.ERROR)
            return false
        }
        if (SearchService.containsSecret(text)) {
            ToastCenter.show(L("composeSecretBlocked"), ToastStyle.ERROR)
            return false
        }
        isPosting = true
        try {
            val uploaded = attachments.filter { it.uploaded != null }
            val urls = uploaded.mapNotNull { it.uploaded?.url }
            val imeta = uploaded.mapNotNull { attachment ->
                val item = attachment.uploaded ?: return@mapNotNull null
                val tag = mutableListOf("imeta", "url ${item.url}", "m ${item.mimeType}")
                if (item.sha256.isNotEmpty()) tag.add("x ${item.sha256}")
                if (attachment.width != null && attachment.height != null) tag.add("dim ${attachment.width}x${attachment.height}")
                attachment.blurhash?.let { tag.add("blurhash $it") }
                attachment.trimmedAlt?.let { tag.add("alt $it") }
                tag
            }
            val extraTags = imeta + contentWarningTags
            val content = finalContent()
            when (val c = context) {
                ComposeContext.NewNote -> if (isPollActive) {
                    InteractionService.publishPoll(content, validPollOptions, pollMultiple, if (pollHasEnd) pollEndsAt else null, urls, extraTags)
                } else {
                    InteractionService.publishNote(content, urls, extraTags)
                }
                is ComposeContext.Reply -> {
                    InteractionService.publishReply(c.note, content, urls, extraTags)
                    NoteInteractionStore.markReplied(c.note.id)
                }
                is ComposeContext.Quote -> InteractionService.publishQuote(c.note, content, urls, extraTags)
            }
            didPost++
            deleteDraft()
            DataBus.feedChanged()
            return true
        } catch (error: Throwable) {
            ToastCenter.show("${L("errorSharingNote")}: ${coreErrorMessage(error)}", ToastStyle.ERROR)
            return false
        } finally {
            isPosting = false
        }
    }

    override fun onCleared() {
        saveJob?.cancel()
        searchJob?.cancel()
    }
}
