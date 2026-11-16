package me.untreu.qiqstr.ui.compose

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.AddPhotoAlternate
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.GraphicEq
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.EmojiEmotions
import androidx.compose.material.icons.outlined.Adjust
import me.untreu.qiqstr.core.components.EmojiPickerSheet
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.RemoveCircle
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Videocam
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.ComposeContext
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.AvatarView
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.RemoteImage
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.services.VoiceRecorder
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.note.NoteRow

private class ComposeStoreOwner : ViewModelStoreOwner {
    override val viewModelStore = ViewModelStore()
}

@Composable
fun ComposeSheet(context: ComposeContext, onDismiss: () -> Unit) {
    key(context) {
        val owner = remember { ComposeStoreOwner() }
        DisposableEffect(owner) { onDispose { owner.viewModelStore.clear() } }
        CompositionLocalProvider(LocalViewModelStoreOwner provides owner) {
            ComposeEditor(context, onDismiss)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ComposeEditor(context: ComposeContext, onDismiss: () -> Unit) {
    val model: ComposeViewModel = viewModel { ComposeViewModel(context) }
    var confirmDiscard by remember { mutableStateOf(false) }
    var showsDrafts by remember { mutableStateOf(false) }
    var showsGifs by remember { mutableStateOf(false) }
    var showsEmoji by remember { mutableStateOf(false) }
    var showsRecorder by remember { mutableStateOf(false) }
    var showsSchedule by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    val remaining = maxOf(1, ComposeViewModel.MAX_ATTACHMENTS - model.attachments.size)
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(ComposeViewModel.MAX_ATTACHMENTS)) { uris: List<Uri> ->
        if (uris.isNotEmpty()) model.handlePicked(uris.take(remaining))
    }
    val capture = rememberCameraCapture { mode, file -> model.addCaptured(mode, file) }
    val cancel = { if (model.hasContent) confirmDiscard = true else onDismiss() }

    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    LaunchedEffect(model) { snapshotFlow { model.draftSnapshot }.drop(1).collect { model.scheduleSave() } }
    LaunchedEffect(model.didPost) { if (model.didPost > 0) haptics.performHapticFeedback(HapticFeedbackType.LongPress) }
    DisposableEffect(model) { onDispose { model.finishSaving() } }
    BackHandler(enabled = model.hasContent) { confirmDiscard = true }

    Column(Modifier.fillMaxWidth().fillMaxHeight().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = cancel, modifier = Modifier.testTag("compose-cancel")) { Icon(Icons.Outlined.Close, L("cancel")) }
            Text(model.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f).padding(start = 4.dp))
            if (model.otherDrafts.isNotEmpty() || model.scheduledPosts.isNotEmpty()) {
                IconButton(onClick = { showsDrafts = true }, modifier = Modifier.testTag("compose-drafts")) { Icon(Icons.Outlined.Inventory2, L("feedDrafts")) }
            }
            Button(
                onClick = { scope.launch { if (model.post()) onDismiss() } },
                enabled = model.canPost,
                colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
                modifier = Modifier.padding(start = 4.dp, end = 8.dp).testTag("compose-post"),
            ) {
                if (model.isPosting) {
                    CircularProgressIndicator(Modifier.size(18.dp), color = AppColors.background, strokeWidth = 2.dp)
                } else {
                    val label = when {
                        model.scheduledAt != null -> L("feedScheduleAction")
                        context == ComposeContext.NewNote -> L("feedPost")
                        else -> model.title
                    }
                    Text(label, fontWeight = FontWeight.SemiBold)
                }
            }
        }
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            if (context is ComposeContext.Reply) ReplyTargetPreview(context.note)
            ComposeTextEditor(model, focus, isQuote = context is ComposeContext.Quote)
            AnimatedVisibility(model.isPollActive) { ComposePollEditor(model) }
            AnimatedVisibility(model.isGoalActive) { ComposeGoalEditor(model) }
            AnimatedVisibility(model.contentWarningEnabled) {
                ComposeContentWarningField(model.contentWarningReason) { model.contentWarningReason = it }
            }
            if (model.attachments.isNotEmpty()) ComposeAttachmentStrip(model)
            model.scheduledAt?.let { date ->
                AssistChip(
                    onClick = { showsSchedule = true },
                    label = { Text(L("feedScheduledFor", "date" to TimeFormat.full(date))) },
                    leadingIcon = { Icon(Icons.Outlined.Schedule, null, Modifier.size(AssistChipDefaults.IconSize)) },
                    shape = CircleShape,
                    modifier = Modifier.padding(start = 52.dp).testTag("compose-scheduled-chip"),
                )
            }
            if (context is ComposeContext.Quote) {
                Box(
                    Modifier
                        .padding(start = 52.dp)
                        .clip(RoundedCornerShape(18.dp))
                        .background(AppColors.inputFill)
                        .pointerInput(Unit) {
                            awaitPointerEventScope {
                                while (true) awaitPointerEvent(PointerEventPass.Initial).changes.forEach { it.consume() }
                            }
                        },
                ) {
                    NoteRow(note = context.note, showActions = false)
                }
            }
        }
        ComposeBottomBar(
            model,
            onPickMedia = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)) },
            onCapture = capture,
            onGif = { showsGifs = true },
            onVoice = { showsRecorder = true },
            onSchedule = { showsSchedule = true },
            onEmoji = { showsEmoji = true },
        )
    }

    if (confirmDiscard) {
        AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text(L("feedSaveDraftTitle")) },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    Box(Modifier.testTag("compose-save-draft")) {
                        TextAction(L("feedSaveDraft"), {
                            confirmDiscard = false
                            model.finishSaving()
                            onDismiss()
                        })
                    }
                    Box(Modifier.testTag("compose-discard")) {
                        TextAction(L("feedDeleteDraft"), {
                            confirmDiscard = false
                            model.deleteDraft()
                            onDismiss()
                        }, color = AppColors.error)
                    }
                    TextAction(L("feedKeepEditing"), { confirmDiscard = false })
                }
            },
        )
    }

    if (showsDrafts) {
        ModalBottomSheet(onDismissRequest = { showsDrafts = false }, containerColor = AppColors.background) {
            ComposeDraftsSheet(
                drafts = model.otherDrafts,
                scheduled = model.scheduledPosts,
                onSelect = { draft ->
                    showsDrafts = false
                    model.open(draft)
                },
                onDelete = { model.deleteDraft(it.id) },
                onSelectScheduled = { post ->
                    showsDrafts = false
                    model.open(post)
                },
                onDeleteScheduled = { model.deleteScheduled(it.id) },
                onDismiss = { showsDrafts = false },
            )
        }
    }
    if (showsEmoji) EmojiPickerSheet(onDismiss = { showsEmoji = false }) { model.insert(it) }
    if (showsGifs) GifPickerSheet(onDismiss = { showsGifs = false }) { model.addGif(it) }
    if (showsRecorder) VoiceRecorderSheet(onDismiss = { showsRecorder = false }) { model.addRecording(it) }
    if (showsSchedule) ComposeScheduleSheet(model.scheduledAt, onChange = { model.scheduledAt = it }) { showsSchedule = false }
}

@Composable
private fun ComposeTextEditor(model: ComposeViewModel, focus: FocusRequester, isQuote: Boolean) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Session.pubkey?.let { ProfileAvatar(it, size = 40.dp) }
        Box(Modifier.weight(1f).padding(top = 8.dp)) {
            val style = MaterialTheme.typography.bodyLarge
            if (model.text.isEmpty()) {
                Text(model.placeholder, style = style, color = AppColors.textTertiary)
            }
            val label = L("composeYourNote")
            BasicTextField(
                value = model.input,
                onValueChange = model::updateField,
                textStyle = style.copy(color = AppColors.textPrimary),
                cursorBrush = SolidColor(AppColors.textPrimary),
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = if (model.attachments.isEmpty() && !isQuote) 140.dp else 72.dp)
                    .focusRequester(focus)
                    .semantics { contentDescription = label }
                    .testTag("compose-text"),
            )
        }
    }
}

@Composable
private fun ComposeBottomBar(
    model: ComposeViewModel,
    onPickMedia: () -> Unit,
    onCapture: (CameraCaptureMode) -> Unit,
    onGif: () -> Unit,
    onVoice: () -> Unit,
    onSchedule: () -> Unit,
    onEmoji: () -> Unit,
) {
    var showsCameraModes by remember { mutableStateOf(false) }
    var showsMore by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
        AnimatedVisibility(model.suggestions.isNotEmpty()) {
            ComposeMentionSuggestions(model.suggestions) { model.insertMention(it) }
        }
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val colors = IconButtonDefaults.filledTonalIconButtonColors(containerColor = AppColors.tile, contentColor = AppColors.textPrimary)
            FilledTonalIconButton(
                onClick = onPickMedia,
                enabled = model.canAttach,
                colors = colors,
                modifier = Modifier.testTag("compose-media"),
            ) { Icon(Icons.Outlined.AddPhotoAlternate, L("addMediaText")) }
            if (CameraCapture.isAvailable) {
                Box {
                    FilledTonalIconButton(
                        onClick = { showsCameraModes = true },
                        enabled = model.canAttach,
                        colors = colors,
                        modifier = Modifier.testTag("compose-camera"),
                    ) { Icon(Icons.Outlined.PhotoCamera, L("feedCamera")) }
                    DropdownMenu(expanded = showsCameraModes, onDismissRequest = { showsCameraModes = false }) {
                        DropdownMenuItem(
                            text = { Text(L("dmPhoto")) },
                            leadingIcon = { Icon(Icons.Outlined.PhotoCamera, null) },
                            onClick = {
                                showsCameraModes = false
                                onCapture(CameraCaptureMode.PHOTO)
                            },
                            modifier = Modifier.testTag("compose-camera-photo"),
                        )
                        DropdownMenuItem(
                            text = { Text(L("dmVideo")) },
                            leadingIcon = { Icon(Icons.Outlined.Videocam, null) },
                            onClick = {
                                showsCameraModes = false
                                onCapture(CameraCaptureMode.VIDEO)
                            },
                            modifier = Modifier.testTag("compose-camera-video"),
                        )
                    }
                }
            }
            val gifLabel = L("feedGif")
            FilledTonalIconButton(
                onClick = onGif,
                enabled = model.canAttach,
                colors = colors,
                modifier = Modifier.semantics { contentDescription = gifLabel }.testTag("compose-gif"),
            ) { Text("GIF", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold) }
            FilledTonalIconButton(
                onClick = onVoice,
                enabled = model.canAttach,
                colors = colors,
                modifier = Modifier.testTag("compose-voice"),
            ) { Icon(Icons.Outlined.Mic, L("voiceTitle")) }
            Box {
                val isActive = model.contentWarningEnabled || model.pollEnabled || model.goalEnabled || model.scheduledAt != null
                FilledTonalIconButton(onClick = { showsMore = true }, colors = colors, modifier = Modifier.testTag("compose-more")) {
                    Icon(Icons.Outlined.MoreHoriz, L("feedMoreOptions"), tint = if (isActive) AppColors.link else AppColors.textPrimary)
                }
                DropdownMenu(expanded = showsMore, onDismissRequest = { showsMore = false }) {
                    ComposeMenuToggle(L("feedContentWarning"), Icons.Outlined.WarningAmber, model.contentWarningEnabled, "compose-content-warning") {
                        showsMore = false
                        model.contentWarningEnabled = !model.contentWarningEnabled
                    }
                    if (model.supportsPoll) {
                        ComposeMenuToggle(L("feedPoll"), Icons.Outlined.BarChart, model.pollEnabled, "compose-poll") {
                            showsMore = false
                            model.togglePoll()
                        }
                    }
                    if (model.supportsPoll) ComposeMenuToggle(L("zapGoalTitle"), Icons.Outlined.Adjust, model.goalEnabled, "compose-goal") {
                        showsMore = false
                        model.toggleGoal()
                    }
                    DropdownMenuItem(text = { Text(L("emojiTitle")) }, leadingIcon = { Icon(Icons.Outlined.EmojiEmotions, null) }, onClick = { showsMore = false; onEmoji() }, modifier = Modifier.testTag("compose-emoji"))
                    DropdownMenuItem(
                        text = { Text(if (model.scheduledAt == null) L("feedSchedule") else L("feedScheduleChange")) },
                        leadingIcon = { Icon(Icons.Outlined.Schedule, null) },
                        onClick = {
                            showsMore = false
                            onSchedule()
                        },
                        modifier = Modifier.testTag("compose-schedule"),
                    )
                }
            }
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (model.isUploading) {
                    CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp, color = AppColors.textSecondary)
                    Text(L("uploadingDotDotDot"), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Text(
                "${model.text.length}",
                style = MaterialTheme.typography.bodySmall.copy(fontFeatureSettings = "tnum"),
                color = AppColors.textSecondary,
                maxLines = 1,
                modifier = Modifier.testTag("compose-count"),
            )
        }
    }
}

@Composable
private fun ComposeMenuToggle(title: String, icon: ImageVector, isOn: Boolean, tag: String, onToggle: () -> Unit) {
    val state = if (isOn) L("feedOn") else L("feedOff")
    DropdownMenuItem(
        text = { Text(title) },
        leadingIcon = { Icon(icon, null) },
        trailingIcon = { if (isOn) Icon(Icons.Filled.Check, null) },
        onClick = onToggle,
        modifier = Modifier.semantics {
            stateDescription = state
            selected = isOn
        }.testTag(tag),
    )
}

@Composable
private fun ReplyTargetPreview(note: Note) {
    val name = ProfileCache.profiles[note.pubkey]?.bestName ?: note.authorName ?: Profile.shortNpub(note.pubkey)
    Row(Modifier.height(IntrinsicSize.Min).testTag("compose-reply-target"), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            ProfileAvatar(note.pubkey, size = 40.dp, fallbackUrl = note.authorImage)
            Box(Modifier.width(2.dp).weight(1f).background(AppColors.divider))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                note.authorNip05?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            }
            val warning = note.contentWarning
            if (warning != null) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Outlined.WarningAmber, null, Modifier.size(16.dp), tint = AppColors.textSecondary)
                    Text(warning.ifEmpty { L("feedContentWarning") }, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
                }
            } else {
                Text(note.content, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 5, overflow = TextOverflow.Ellipsis)
            }
            Row(Modifier.padding(top = 4.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(L("replyingTo"), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
                Text("@$name", style = MaterialTheme.typography.bodySmall, color = AppColors.link, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
private fun ComposeAttachmentStrip(model: ComposeViewModel) {
    var editingAlt by remember { mutableStateOf<ComposeAttachment?>(null) }
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(start = 52.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        model.attachments.forEach { attachment ->
            key(attachment.id) {
                ComposeAttachmentTile(attachment, onRemove = { model.remove(attachment) }, onRetry = { model.retry(attachment) }, onEditAlt = { editingAlt = attachment })
            }
        }
    }
    editingAlt?.let { attachment ->
        ModalBottomSheet(onDismissRequest = { editingAlt = null }, containerColor = AppColors.background) {
            ComposeAltTextSheet(attachment) { editingAlt = null }
        }
    }
}

@Composable
private fun ComposeContentWarningField(reason: String, onChange: (String) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(start = 52.dp).clip(RoundedCornerShape(14.dp)).background(AppColors.inputFill).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Filled.Warning, null, tint = AppColors.textSecondary)
        Box(Modifier.weight(1f)) {
            val style = MaterialTheme.typography.bodyLarge
            if (reason.isEmpty()) Text(L("feedContentWarningReason"), style = style, color = AppColors.textTertiary)
            val label = L("feedContentWarning")
            BasicTextField(
                value = reason,
                onValueChange = onChange,
                singleLine = true,
                textStyle = style.copy(color = AppColors.textPrimary),
                cursorBrush = SolidColor(AppColors.textPrimary),
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = label }.testTag("compose-content-warning-reason"),
            )
        }
    }
}

@Composable
private fun ComposeAltTextSheet(attachment: ComposeAttachment, onDismiss: () -> Unit) {
    var draft by remember { mutableStateOf(attachment.altText) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    Column(Modifier.fillMaxWidth().imePadding().navigationBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onDismiss, modifier = Modifier.testTag("compose-alt-cancel")) { Icon(Icons.Outlined.Close, L("cancel")) }
            Text(L("feedAltTextTitle"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Button(
                onClick = {
                    attachment.altText = draft.trim()
                    onDismiss()
                },
                colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
                modifier = Modifier.padding(end = 8.dp).testTag("compose-alt-done"),
            ) {
                Icon(Icons.Outlined.Check, null, Modifier.size(18.dp))
                Text(L("done"), Modifier.padding(start = 6.dp), fontWeight = FontWeight.SemiBold)
            }
        }
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            attachment.preview?.let { preview ->
                androidx.compose.foundation.Image(
                    preview.asImageBitmap(),
                    null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxWidth().heightIn(max = 220.dp).clip(RoundedCornerShape(12.dp)),
                )
            }
            Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(AppColors.inputFill).padding(14.dp)) {
                val style = MaterialTheme.typography.bodyLarge
                if (draft.isEmpty()) Text(L("feedAltTextPlaceholder"), style = style, color = AppColors.textTertiary)
                BasicTextField(
                    value = draft,
                    onValueChange = { draft = it },
                    textStyle = style.copy(color = AppColors.textPrimary),
                    cursorBrush = SolidColor(AppColors.textPrimary),
                    minLines = 3,
                    maxLines = 10,
                    modifier = Modifier.fillMaxWidth().focusRequester(focus).testTag("compose-alt-text-field"),
                )
            }
            Text(L("feedAltTextFooter"), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
        }
    }
}

@Composable
private fun ComposeAttachmentTile(attachment: ComposeAttachment, onRemove: () -> Unit, onRetry: () -> Unit, onEditAlt: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    Box(Modifier.size(110.dp)) {
        Box(Modifier.fillMaxSize().clip(shape).background(AppColors.tile), contentAlignment = Alignment.Center) {
            val preview = attachment.preview
            val audio = attachment.audio
            when {
                preview != null -> androidx.compose.foundation.Image(preview.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                audio != null -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Outlined.GraphicEq, null, Modifier.size(28.dp), tint = AppColors.textSecondary)
                    Text(
                        VoiceRecorder.format(audio.duration),
                        style = MaterialTheme.typography.labelLarge.copy(fontFeatureSettings = "tnum"),
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.textSecondary,
                    )
                }
                attachment.remoteURL != null && !attachment.isVideo -> RemoteImage(attachment.remoteURL, Modifier.fillMaxSize())
                else -> Icon(if (attachment.isVideo) Icons.Outlined.Videocam else Icons.Outlined.Image, null, Modifier.size(28.dp), tint = AppColors.textSecondary)
            }
            when (attachment.status) {
                AttachmentStatus.Uploading -> Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = Color.White, modifier = Modifier.size(28.dp), strokeWidth = 2.dp)
                }
                is AttachmentStatus.Failed -> {
                    val label = L("retry")
                    Box(
                        Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f)).clickable(onClick = onRetry)
                            .semantics { contentDescription = label }.testTag("compose-attachment-retry"),
                        contentAlignment = Alignment.Center,
                    ) { Icon(Icons.Outlined.Refresh, null, tint = Color.White) }
                }
                is AttachmentStatus.Uploaded -> if (attachment.isVideo) Icon(Icons.Filled.PlayCircle, null, Modifier.size(36.dp), tint = Color.White)
            }
        }
        Surface(
            onClick = onRemove,
            shape = CircleShape,
            color = AppColors.background.copy(alpha = 0.85f),
            contentColor = AppColors.textPrimary,
            modifier = Modifier.align(Alignment.TopEnd).padding(6.dp).size(26.dp).testTag("compose-attachment-remove"),
        ) {
            Box(contentAlignment = Alignment.Center) { Icon(Icons.Outlined.Close, L("removeThisMediaFile"), Modifier.size(14.dp)) }
        }
        if (!attachment.isVideo && !attachment.isAudio) {
            val label = if (attachment.trimmedAlt == null) L("feedAddAltText") else L("feedAltTextTitle")
            Surface(
                onClick = onEditAlt,
                shape = CircleShape,
                color = AppColors.background.copy(alpha = 0.85f),
                contentColor = AppColors.textPrimary,
                modifier = Modifier.align(Alignment.BottomStart).padding(6.dp).height(26.dp)
                    .semantics {
                        contentDescription = label
                        stateDescription = attachment.trimmedAlt ?: ""
                    }
                    .testTag("compose-attachment-alt"),
            ) {
                Row(Modifier.padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    if (attachment.trimmedAlt != null) Icon(Icons.Outlined.Check, null, Modifier.size(12.dp))
                    Text(L("feedAltButton"), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun ComposeMentionSuggestions(profiles: List<Profile>, onSelect: (Profile) -> Unit) {
    val mention = L("mention")
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 6.dp).testTag("compose-mentions"),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        profiles.forEach { profile ->
            Surface(
                onClick = { onSelect(profile) },
                shape = CircleShape,
                color = AppColors.tile,
                contentColor = AppColors.textPrimary,
                modifier = Modifier.heightIn(min = 42.dp).semantics { contentDescription = "$mention ${profile.bestName}" }.testTag("compose-mention-suggestion"),
            ) {
                Row(Modifier.padding(start = 6.dp, end = 12.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AvatarView(profile.picture.ifEmpty { null }, size = 28.dp)
                    Column {
                        Text(profile.bestName, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 1)
                        if (profile.nip05.isNotEmpty()) Text(profile.nip05, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, maxLines = 1)
                    }
                }
            }
        }
    }
}

@Composable
internal fun ComposeIconRemove(onClick: () -> Unit, label: String, tag: String) {
    IconButton(onClick = onClick, modifier = Modifier.size(32.dp).testTag(tag)) {
        Icon(Icons.Outlined.RemoveCircle, label, tint = AppColors.textSecondary)
    }
}
