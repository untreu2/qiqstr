package me.untreu.qiqstr.ui.dm

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Videocam
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L

@Composable
fun DMInputBar(
    model: DMChatViewModel,
    focusRequester: FocusRequester,
    placeholder: String = L("typeAMessage"),
    onFocusChanged: (Boolean) -> Unit = {},
) {
    val haptics = LocalHapticFeedback.current
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(4)) { uris -> model.handlePicked(uris) }
    LaunchedEffect(model.sentCount) { if (model.sentCount > 0) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove) }
    LaunchedEffect(model.failureCount) { if (model.failureCount > 0) haptics.performHapticFeedback(HapticFeedbackType.LongPress) }
    val sendAlpha by animateFloatAsState(if (model.canSend) 1f else 0.3f, label = "send")

    Column(
        Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 6.dp, bottom = 8.dp).animateContentSize(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        AnimatedVisibility(model.attachments.isNotEmpty()) { AttachmentStrip(model) }
        Surface(shape = RoundedCornerShape(28.dp), color = AppColors.inputFill) {
            Row(Modifier.padding(8.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                IconButton(
                    onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)) },
                    colors = IconButtonDefaults.iconButtonColors(containerColor = AppColors.tile, contentColor = AppColors.textPrimary),
                    modifier = Modifier.size(40.dp).testTag("dm-attach"),
                ) { Icon(Icons.Outlined.Add, L("dmAttach")) }
                Box(Modifier.weight(1f).heightIn(min = 40.dp).padding(vertical = 8.dp), contentAlignment = Alignment.CenterStart) {
                    if (model.draft.text.isEmpty()) {
                        Text(placeholder, style = MaterialTheme.typography.bodyLarge, color = AppColors.textTertiary, maxLines = 1)
                    }
                    BasicTextField(
                        value = model.draft,
                        onValueChange = { model.draft = it },
                        textStyle = MaterialTheme.typography.bodyLarge.copy(color = AppColors.textPrimary),
                        cursorBrush = SolidColor(AppColors.textPrimary),
                        maxLines = 6,
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                        modifier = Modifier.fillMaxWidth().focusRequester(focusRequester).onFocusChanged { onFocusChanged(it.isFocused) }.testTag("dm-input"),
                    )
                }
                IconButton(
                    onClick = model::send,
                    enabled = model.canSend,
                    colors = IconButtonDefaults.iconButtonColors(
                        containerColor = AppColors.textPrimary,
                        contentColor = AppColors.background,
                        disabledContainerColor = AppColors.textPrimary,
                        disabledContentColor = AppColors.background,
                    ),
                    modifier = Modifier.size(40.dp).alpha(sendAlpha).testTag("dm-send"),
                ) { Icon(Icons.Outlined.ArrowUpward, L("sendMessage")) }
            }
        }
    }
}

@Composable
private fun AttachmentStrip(model: DMChatViewModel) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 4.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.testTag("dm-attachments"),
    ) {
        items(model.attachments, key = { it.id }) { attachment ->
            Box(Modifier.animateItem()) {
                Box(Modifier.size(72.dp).clip(RoundedCornerShape(14.dp)).background(AppColors.tile), contentAlignment = Alignment.Center) {
                    val thumbnail = attachment.thumbnail
                    if (thumbnail != null) {
                        Image(thumbnail.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                    } else {
                        Icon(if (attachment.isVideo) Icons.Outlined.Videocam else Icons.Outlined.Image, null, tint = AppColors.textSecondary)
                    }
                    if (attachment.state == DMAttachmentState.Preparing) {
                        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(Modifier.size(24.dp), color = Color.White, strokeWidth = 2.dp)
                        }
                    } else if (attachment.isVideo) {
                        Icon(Icons.Filled.PlayCircle, null, Modifier.size(32.dp), tint = Color.White)
                    }
                }
                IconButton(
                    onClick = { model.removeAttachment(attachment.id) },
                    modifier = Modifier.align(Alignment.TopEnd).offset(x = 10.dp, y = (-10).dp).size(36.dp).testTag("dm-attachment-remove"),
                ) {
                    Box(Modifier.size(22.dp).background(AppColors.background, CircleShape), contentAlignment = Alignment.Center) {
                        Icon(Icons.Outlined.Close, L("removeThisMediaFile"), Modifier.size(14.dp), tint = AppColors.textPrimary)
                    }
                }
            }
        }
    }
}
