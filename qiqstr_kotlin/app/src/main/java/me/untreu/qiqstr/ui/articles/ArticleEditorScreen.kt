package me.untreu.qiqstr.ui.articles

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.AddPhotoAlternate
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.*
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.*
import me.untreu.qiqstr.core.components.RemoteImage
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.ui.compose.MediaSanitizer
import me.untreu.qiqstr.ui.compose.MediaUploadService

class ArticleEditorViewModel(initial: ArticleDraft) : ViewModel() {
    private val owner = Session.pubkey
    private val original = initial
    private val wasSaved = ArticleDraftStore.draft(initial.id) != null
    private var saveJob: Job? = null
    private var finished = false
    var draft by mutableStateOf(initial)
        private set
    var text by mutableStateOf(TextFieldValue(initial.content))
        private set
    var preview by mutableStateOf(false)
    var busy by mutableStateOf(false)
        private set
    var uploading by mutableStateOf(false)
        private set
    val dirty: Boolean get() = draft != original
    fun update(value: ArticleDraft) { draft = value; saveJob?.cancel(); saveJob = viewModelScope.launch { delay(600); if (!finished) ArticleDraftStore.save(draft, owner) } }
    fun updateText(value: TextFieldValue) { text = value; if (draft.content != value.text) update(draft.copy(content = value.text)) }
    fun format(style: MarkdownStyle) = insert(MarkdownEdit.apply(style, text.text, text.selection.start, text.selection.end))
    private fun insert(edit: MarkdownEdit) = updateText(TextFieldValue(edit.text, TextRange(edit.caret)))
    fun save() { saveJob?.cancel(); ArticleDraftStore.save(draft, owner) }
    fun discard() { finished = true; saveJob?.cancel(); if (owner == Session.pubkey) { if (wasSaved) ArticleDraftStore.save(original, owner) else ArticleDraftStore.delete(draft.id) } }
    fun publish() {
        if (busy || uploading || owner != Session.pubkey) return
        save(); busy = true
        viewModelScope.launch {
            try {
                val address = ArticlePublisher.publish(draft)
                finished = true
                ToastCenter.show(L(if (draft.isEditingPublished) "articleUpdated" else "articlePublished"), ToastStyle.SUCCESS)
                Router.pop(); address.naddr?.let { Router.push(Route.ArticleAddress(it)) }
            } catch (error: Throwable) { ToastCenter.error(error) } finally { busy = false }
        }
    }
    fun upload(uri: Uri, cover: Boolean) {
        if (uploading || busy) return
        val selection = text.selection
        uploading = true
        viewModelScope.launch {
            try {
                val prepared = withContext(Dispatchers.IO) {
                    val mime = App.context.contentResolver.getType(uri) ?: "image/jpeg"
                    val bytes = App.context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: throw CoreError(L("errorSelectingMedia"))
                    MediaSanitizer.prepareImage(bytes, mime) ?: throw CoreError(L("errorSelectingMedia"))
                }
                val url = MediaUploadService.upload(prepared.bytes, prepared.mimeType)
                if (owner == Session.pubkey) {
                    if (cover) update(draft.copy(image = url))
                    else insert(MarkdownEdit.image(url, text.text, selection.start, selection.end))
                }
            } catch (error: Throwable) { ToastCenter.error(error) } finally { uploading = false }
        }
    }
    override fun onCleared() { if (!finished) save(); super.onCleared() }
}

@Composable
fun ArticleEditorScreen(draftId: String?) {
    val model: ArticleEditorViewModel = viewModel { ArticleEditorViewModel(draftId?.let { ArticleDraftStore.draft(it) } ?: ArticleDraft()) }
    var publishing by remember { mutableStateOf(false) }
    val contentFocus = remember { FocusRequester() }
    if (publishing) AlertDialog(onDismissRequest = { publishing = false }, title = { Text(L(if (model.draft.isEditingPublished) "articleUpdateConfirm" else "articlePublishConfirm")) }, text = { Text(L("articlePublishMessage")) }, confirmButton = { TextButton(onClick = { publishing = false; model.publish() }, modifier = Modifier.testTag("article-publish-confirm")) { Text(L("articlePublish")) } }, dismissButton = { TextButton(onClick = { publishing = false }) { Text(L("cancel")) } })
    var close by remember { mutableStateOf(false) }
    val closing = { if (model.dirty) close = true else { model.save(); Router.pop(); Unit } }
    BackHandler { closing() }
    val coverPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { it?.let { uri -> model.upload(uri, true) } }
    val inlinePicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { it?.let { uri -> model.upload(uri, false) } }
    if (close) AlertDialog(onDismissRequest = { close = false }, title = { Text(L("articleCloseTitle")) }, text = { Text(L("articleNoDraftsMessage")) }, confirmButton = {
        TextButton(onClick = { model.save(); Router.pop() }, modifier = Modifier.testTag("article-keep-draft")) { Text(L("articleKeepDraft")) }
    }, dismissButton = { TextButton(onClick = { model.discard(); Router.pop() }, modifier = Modifier.testTag("article-discard-draft")) { Text(L("articleDiscardDraft"), color = AppColors.error) } })
    Scaffold(topBar = {
        TopAppBar(title = { Text(L(if (model.draft.isEditingPublished) "articleEditTitle" else "articleNewTitle")) }, navigationIcon = { IconButton(onClick = { closing() }, modifier = Modifier.testTag("article-editor-close")) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } }, actions = {
            TextButton(onClick = { publishing = true }, enabled = model.draft.canPublish && !model.busy && !model.uploading, modifier = Modifier.testTag("article-publish")) { Text(L(if (model.draft.isEditingPublished) "articleUpdate" else "articlePublish")) }
        })
    }, modifier = Modifier.testTag("article-editor")) { padding ->
        Column(Modifier.padding(padding).imePadding()) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp).testTag("article-editor-mode")) {
                listOf("articleWrite", "articlePreview").forEachIndexed { index, key -> SegmentedButton(selected = model.preview == (index == 1), onClick = { model.preview = index == 1 }, shape = SegmentedButtonDefaults.itemShape(index, 2)) { Text(L(key)) } }
            }
            if (model.busy || model.uploading) LinearProgressIndicator(Modifier.fillMaxWidth())
            if (model.preview) Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp).testTag("article-preview"), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                if (model.draft.image.isNotEmpty()) RemoteImage(model.draft.image, Modifier.fillMaxWidth().height(200.dp))
                Text(model.draft.displayTitle, style = MaterialTheme.typography.headlineLarge)
                if (model.draft.summary.isNotEmpty()) Text(model.draft.summary, color = AppColors.textSecondary)
                if (model.draft.hashtags.isNotEmpty()) Text(model.draft.hashtags.joinToString(" ") { "#$it" })
                MarkdownView(MarkdownParser.parse(model.draft.content))
            } else {
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedTextField(model.draft.title, { model.update(model.draft.copy(title = it)) }, label = { Text(L("articleTitlePlaceholder")) }, enabled = !model.busy, modifier = Modifier.fillMaxWidth().testTag("article-title"))
                    OutlinedTextField(model.draft.summary, { model.update(model.draft.copy(summary = it)) }, label = { Text(L("articleSummaryPlaceholder")) }, enabled = !model.busy, modifier = Modifier.fillMaxWidth().testTag("article-summary"))
                    Row {
                        OutlinedTextField(model.draft.image, { model.update(model.draft.copy(image = it)) }, label = { Text(L("articleCoverURL")) }, enabled = !model.busy, modifier = Modifier.weight(1f).testTag("article-cover-url"))
                        IconButton(onClick = { coverPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, enabled = !model.uploading && !model.busy, modifier = Modifier.testTag("article-add-cover")) { Icon(Icons.Outlined.AddPhotoAlternate, L("articleAddCover")) }
                    }
                    if (model.draft.image.isNotEmpty()) {
                        RemoteImage(model.draft.image, Modifier.fillMaxWidth().height(160.dp))
                        TextButton(onClick = { model.update(model.draft.copy(image = "")) }, enabled = !model.busy && !model.uploading, modifier = Modifier.testTag("article-remove-cover")) { Text(L("articleRemoveCover")) }
                    }
                    var hashtags by remember { mutableStateOf(model.draft.hashtags.joinToString(", ")) }
                    OutlinedTextField(hashtags, { hashtags = it; model.update(model.draft.copy(hashtags = ArticleIdentifier.hashtags(it))) }, label = { Text(L("articleHashtagsPlaceholder")) }, enabled = !model.busy, modifier = Modifier.fillMaxWidth().testTag("article-hashtags"))
                    OutlinedTextField(model.text, model::updateText, placeholder = { Text(L("articleContentPlaceholder")) }, enabled = !model.busy, modifier = Modifier.fillMaxWidth().heightIn(min = 320.dp).focusRequester(contentFocus).testTag("article-content"))
                    Text(L("articleWordCount", "words" to model.draft.wordCount, "minutes" to maxOf(1, model.draft.wordCount / 220)), color = AppColors.textSecondary)
                }
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).navigationBarsPadding().testTag("article-format-bar")) {
                    MarkdownStyle.entries.forEach { style -> TextButton(onClick = { model.format(style); contentFocus.requestFocus() }, enabled = !model.busy && !model.uploading, modifier = Modifier.semantics { contentDescription = L(style.key) }.testTag("article-format-${style.name.lowercase()}")) { Text(style.symbol, modifier = Modifier.clearAndSetSemantics {}) } }
                    IconButton(onClick = { inlinePicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, enabled = !model.busy && !model.uploading, modifier = Modifier.testTag("article-inline-image")) { Icon(Icons.Outlined.AddPhotoAlternate, L("articleInsertImage")) }
                }
            }
        }
    }
}

@Composable
fun ArticleWriteMenu() {
    var open by remember { mutableStateOf(false) }
    val count = ArticleDraftStore.all().size
    if (!Session.canSign) return
    Box {
        TextButton(onClick = { open = true }, modifier = Modifier.testTag("article-write-menu")) { Text(L("articleWrite")) }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(text = { Text(L("articleWriteNew")) }, onClick = { open = false; Router.push(Route.ArticleEditor()) }, modifier = Modifier.testTag("article-write-new"))
            DropdownMenuItem(text = { Text(if (count > 0) L("articleDraftsCount", "count" to count) else L("articleDrafts")) }, onClick = { open = false; Router.push(Route.ArticleDrafts) }, modifier = Modifier.testTag("article-open-drafts"))
        }
    }
}

@Composable
fun ArticleDraftsScreen() {
    val drafts = ArticleDraftStore.all()
    var deleting by remember { mutableStateOf<String?>(null) }
    deleting?.let { id -> AlertDialog(onDismissRequest = { deleting = null }, title = { Text(L("articleDeleteDraftTitle")) }, text = { Text(L("articleNoDraftsMessage")) }, confirmButton = { TextButton(onClick = { ArticleDraftStore.delete(id); deleting = null }) { Text(L("delete")) } }, dismissButton = { TextButton(onClick = { deleting = null }) { Text(L("cancel")) } }) }
    Scaffold(topBar = { TopAppBar(title = { Text(L("articleDrafts")) }, navigationIcon = { IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } }, actions = { TextButton(onClick = { Router.push(Route.ArticleEditor()) }, modifier = Modifier.testTag("article-drafts-new")) { Text(L("articleWriteNew")) } }) }, modifier = Modifier.testTag("article-drafts")) { padding ->
        LazyColumn(Modifier.padding(padding)) {
            if (drafts.isEmpty()) item { Text(L("articleNoDrafts"), Modifier.padding(24.dp).testTag("article-drafts-empty")) }
            items(drafts, key = { it.id }) { draft ->
                ListItem(headlineContent = { TextButton(onClick = { Router.push(Route.ArticleEditor(draft.id)) }) { Text(draft.displayTitle) } }, supportingContent = { Column {
                    Text(draft.summary.ifEmpty { draft.content }.take(120), maxLines = 2)
                    if (draft.isEditingPublished) Text(L("articleEditingPublished"), style = MaterialTheme.typography.labelSmall)
                    Text(L("articleDraftEdited", "time" to TimeFormat.relative(draft.updatedAt)) + " · " + L("exploreMinRead", "count" to maxOf(1, draft.wordCount / 220)), style = MaterialTheme.typography.bodySmall)
                } }, trailingContent = { IconButton(onClick = { deleting = draft.id }) { Icon(Icons.Outlined.DeleteOutline, L("delete")) } }, modifier = Modifier.testTag("article-draft-row"))
            }
        }
    }
}
