package me.untreu.qiqstr.ui.dm

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Reply
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.RemoteImage

class DMBubbleActions(
    val onCopy: (DMMessage) -> Unit,
    val onRetry: (DMMessage) -> Unit,
    val onDiscard: (DMMessage) -> Unit,
    val onQuote: (DMMessage) -> Unit,
    val onInfo: (DMMessage) -> Unit,
    val onReact: ((DMMessage, me.untreu.qiqstr.data.services.EmojiChoice) -> Unit)? = null,
)

fun dmBubbleShape(mine: Boolean, isFirstInGroup: Boolean, isLastInGroup: Boolean): RoundedCornerShape {
    val large = 24.dp
    val small = 10.dp
    val tail = 24.dp
    return if (mine) {
        RoundedCornerShape(topStart = large, topEnd = if (isFirstInGroup) large else small, bottomEnd = if (isLastInGroup) tail else small, bottomStart = large)
    } else {
        RoundedCornerShape(topStart = if (isFirstInGroup) large else small, topEnd = large, bottomEnd = large, bottomStart = if (isLastInGroup) tail else small)
    }
}

@Composable
fun DMMessageBubble(
    message: DMMessage,
    isFirstInGroup: Boolean,
    isLastInGroup: Boolean,
    actions: DMBubbleActions,
    searchQuery: String = "",
    isCurrentMatch: Boolean = false,
    senderName: String? = null,
    reactions: List<DMReaction> = emptyList(),
) {
    var showsPicker by remember { mutableStateOf(false) }
    if (showsPicker) me.untreu.qiqstr.core.components.EmojiPickerSheet(onDismiss = { showsPicker = false }) { actions.onReact?.invoke(message, it) }
    val mine = message.isMine
    val shape = dmBubbleShape(mine, isFirstInGroup, isLastInGroup)
    var menuOpen by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val openMenu = {
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        menuOpen = true
    }
    Row(
        Modifier.fillMaxWidth().padding(top = if (isFirstInGroup) 10.dp else 2.dp).testTag("dm-message-${message.id}"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp, if (mine) Alignment.End else Alignment.Start),
    ) {
        if (mine) Spacer(Modifier.width(48.dp))
        if (message.state == DMDeliveryState.FAILED) FailedBadge(message, actions)
        Column(Modifier.weight(1f, fill = false), horizontalAlignment = if (mine) Alignment.End else Alignment.Start, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            if (senderName != null && isFirstInGroup && !mine) Text(senderName, style = MaterialTheme.typography.labelMedium, color = AppColors.textSecondary, modifier = Modifier.padding(horizontal = 12.dp).testTag("dm-message-sender"))
            Box {
                val highlight = if (isCurrentMatch) Modifier.border(2.dp, AppColors.link, shape) else Modifier
                Box(highlight) {
                    Bubble(message, shape, searchQuery, openMenu)
                }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    if (message.state == DMDeliveryState.SENT && actions.onReact != null) {
                        Row {
                            listOf("❤️", "😂", "😮", "😢", "🔥", "👍").forEach { emoji ->
                                androidx.compose.material3.TextButton(onClick = { menuOpen = false; actions.onReact.invoke(message, me.untreu.qiqstr.data.services.EmojiChoice.Unicode(emoji)) }, contentPadding = androidx.compose.foundation.layout.PaddingValues(4.dp), modifier = Modifier.size(40.dp)) { Text(emoji) }
                            }
                        }
                        DropdownMenuItem(text = { Text(L("emojiMore")) }, onClick = { menuOpen = false; showsPicker = true }, modifier = Modifier.testTag("dm-react"))
                    }
                    MenuItems(message, actions) { menuOpen = false }
                }
            }
            if (reactions.isNotEmpty()) Row(Modifier.testTag("dm-reactions"), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                reactions.groupBy { it.emoji }.entries.sortedWith(compareByDescending<Map.Entry<String, List<DMReaction>>> { it.value.size }.thenBy { it.key }).forEach { (emoji, items) ->
                    val custom = items.firstOrNull()?.emojiURL
                    val choice = if (custom != null) me.untreu.qiqstr.data.services.EmojiChoice.Custom(me.untreu.qiqstr.data.services.CustomEmoji(emoji.trim(':'), custom)) else me.untreu.qiqstr.data.services.EmojiChoice.Unicode(emoji)
                    val mineReaction = items.any { it.sender == me.untreu.qiqstr.data.sync.Session.pubkey }
                    androidx.compose.material3.Surface(onClick = { actions.onReact?.invoke(message, choice) }, enabled = actions.onReact != null && message.state == DMDeliveryState.SENT, shape = RoundedCornerShape(50), color = if (mineReaction) AppColors.link.copy(alpha = 0.18f) else AppColors.tile) {
                        Row(Modifier.padding(horizontal = 8.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                            if (custom != null) me.untreu.qiqstr.core.components.CustomEmojiImage(custom, 16.dp) else Text(emoji, style = MaterialTheme.typography.bodySmall)
                            if (items.size > 1) Text("${items.size}", style = MaterialTheme.typography.labelSmall)
                        }
                    }
                }
            }
            if (isLastInGroup || message.state != DMDeliveryState.SENT) Footer(message, actions)
        }
        if (!mine) Spacer(Modifier.width(48.dp))
    }
}

@Composable
private fun Bubble(message: DMMessage, shape: RoundedCornerShape, searchQuery: String, openMenu: () -> Unit) {
    val mine = message.isMine
    val longPress = Modifier.pointerInput(message.id) { detectTapGestures(onLongPress = { openMenu() }) }
    val soleImage = remember(message.content) {
        val trimmed = message.content.trim()
        if (trimmed.none { it.isWhitespace() } && DMText.isImageURL(trimmed)) trimmed else null
    }
    when {
        message.isFile -> DMMediaGate(message, shape) {
            Box(Modifier.alpha(if (message.state == DMDeliveryState.SENDING) 0.7f else 1f)) {
                DMMediaBubble(message, shape, openMenu)
            }
        }
        soleImage != null -> DMMediaGate(message, shape) {
            RemoteImage(
                soleImage,
                Modifier.size(240.dp).clip(shape).then(longPress).semantics { contentDescription = L("dmSpokenPhoto", "sender" to message.spokenSender) },
                contentScale = ContentScale.Crop,
            )
        }
        else -> {
            val foreground = if (mine) AppColors.background else AppColors.textPrimary
            val text = DMText.attributed(message.content, mine, searchQuery, AppColors.link, foreground)
            Text(
                text,
                style = MaterialTheme.typography.bodyLarge,
                color = foreground,
                modifier = Modifier
                    .alpha(if (message.state == DMDeliveryState.SENDING) 0.7f else 1f)
                    .clip(shape)
                    .background(if (mine) AppColors.textPrimary else AppColors.tile)
                    .then(longPress)
                    .padding(horizontal = 16.dp, vertical = 12.dp)
                    .semantics { contentDescription = L("dmSpokenMessage", "sender" to message.spokenSender, "text" to message.content) },
            )
        }
    }
}

@Composable
private fun MenuItems(message: DMMessage, actions: DMBubbleActions, dismiss: () -> Unit) {
    if (!message.isFile) {
        DropdownMenuItem(
            text = { Text(L("copy")) },
            leadingIcon = { Icon(Icons.Outlined.ContentCopy, null) },
            onClick = { dismiss(); actions.onCopy(message) },
        )
        DropdownMenuItem(
            text = { Text(L("reply")) },
            leadingIcon = { Icon(Icons.AutoMirrored.Outlined.Reply, null) },
            onClick = { dismiss(); actions.onQuote(message) },
        )
    }
    DropdownMenuItem(
        text = { Text(L("dmInfo")) },
        leadingIcon = { Icon(Icons.Outlined.Info, null) },
        onClick = { dismiss(); actions.onInfo(message) },
    )
    if (message.state == DMDeliveryState.FAILED) {
        HorizontalDivider()
        DropdownMenuItem(
            text = { Text(L("retry")) },
            leadingIcon = { Icon(Icons.Outlined.Refresh, null) },
            onClick = { dismiss(); actions.onRetry(message) },
        )
        DropdownMenuItem(
            text = { Text(L("delete"), color = AppColors.error) },
            leadingIcon = { Icon(Icons.Outlined.DeleteOutline, null, tint = AppColors.error) },
            onClick = { dismiss(); actions.onDiscard(message) },
        )
    }
}

@Composable
private fun FailedBadge(message: DMMessage, actions: DMBubbleActions) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }, modifier = Modifier.testTag("dm-message-failed-menu")) {
            Icon(Icons.Filled.Error, L("dmSendFailed"), tint = AppColors.error)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(
                text = { Text(L("dmTryAgain")) },
                leadingIcon = { Icon(Icons.Outlined.Refresh, null) },
                onClick = { open = false; actions.onRetry(message) },
            )
            DropdownMenuItem(
                text = { Text(L("delete"), color = AppColors.error) },
                leadingIcon = { Icon(Icons.Outlined.DeleteOutline, null, tint = AppColors.error) },
                onClick = { open = false; actions.onDiscard(message) },
            )
        }
    }
}

@Composable
private fun Footer(message: DMMessage, actions: DMBubbleActions) {
    val style = MaterialTheme.typography.labelSmall
    when (message.state) {
        DMDeliveryState.SENDING -> Row(Modifier.padding(horizontal = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            CircularProgressIndicator(Modifier.size(10.dp), color = AppColors.textSecondary, strokeWidth = 1.5.dp)
            Text(L("dmSending"), style = style, color = AppColors.textSecondary)
        }
        DMDeliveryState.FAILED -> Row(
            Modifier.clip(RoundedCornerShape(6.dp)).clickable { actions.onRetry(message) }.padding(horizontal = 6.dp, vertical = 2.dp).testTag("dm-message-retry"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Icon(Icons.Filled.Error, null, Modifier.size(12.dp), tint = AppColors.error)
            Text(L("dmFailedTapRetry"), style = style, fontWeight = FontWeight.Medium, color = AppColors.error)
        }
        DMDeliveryState.SENT -> Row(Modifier.padding(horizontal = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            if (message.isFile && message.file?.isEncrypted == false) {
                Icon(Icons.Outlined.WarningAmber, null, Modifier.size(11.dp), tint = AppColors.textSecondary)
                Text("${L("notEncrypted")} · ${DMFormat.time(message.createdAt)}", style = style, color = AppColors.textSecondary)
            } else {
                Icon(Icons.Filled.Lock, null, Modifier.size(10.dp).alpha(0.6f), tint = AppColors.textSecondary)
                Text(DMFormat.time(message.createdAt), style = style, color = AppColors.textSecondary)
            }
        }
    }
}
