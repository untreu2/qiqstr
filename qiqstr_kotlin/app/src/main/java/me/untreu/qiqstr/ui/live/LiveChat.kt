package me.untreu.qiqstr.ui.live

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.VolumeOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.data.services.LiveChatMessage
import me.untreu.qiqstr.data.services.MuteService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.ui.explore.LongPressMenuBox
import me.untreu.qiqstr.ui.explore.MenuAction

@Composable
fun LiveChatList(messages: List<LiveChatMessage>, loaded: Boolean, isLive: Boolean, modifier: Modifier = Modifier) {
    val state = rememberLazyListState()
    LaunchedEffect(messages.lastOrNull()?.id) {
        if (messages.isNotEmpty()) state.animateScrollToItem(messages.lastIndex)
    }
    LazyColumn(
        state = state,
        modifier = modifier.testTag("live-chat"),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (!loaded) {
            item(key = "chat-loading") {
                Box(Modifier.fillMaxWidth().padding(top = 24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = AppColors.textPrimary) }
            }
        } else if (messages.isEmpty()) {
            item(key = "chat-empty") {
                Text(
                    L(if (isLive) "liveChatEmpty" else "liveChatEmptyEnded"),
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
                )
            }
        }
        items(messages, key = { it.id }) { LiveChatRow(it) }
    }
}

@Composable
fun LiveChatRow(message: LiveChatMessage) {
    val scope = rememberCoroutineScope()
    LongPressMenuBox(
        onClick = {},
        menu = { dismiss ->
            if (message.pubkey != Session.pubkey) {
                MenuAction(L("mute"), Icons.Outlined.VolumeOff, destructive = true) {
                    dismiss()
                    scope.launch {
                        runCatching { MuteService.mute(message.pubkey) }
                            .onSuccess { ToastCenter.show(L("feedUserMuted"), ToastStyle.SUCCESS) }
                            .onFailure(ToastCenter::error)
                    }
                }
            }
        },
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ProfileAvatar(message.pubkey, size = 28.dp, modifier = Modifier.clickable { Router.push(Route.Profile(message.pubkey)) })
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(liveHostName(message.pubkey), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    Text(TimeFormat.relative(message.createdAt), style = MaterialTheme.typography.labelSmall, color = AppColors.textTertiary)
                }
                SelectionContainer { Text(message.content, style = MaterialTheme.typography.bodyMedium) }
            }
        }
    }
}

@Composable
fun LiveChatInput(text: String, onTextChange: (String) -> Unit, canSend: Boolean, isSending: Boolean, onSend: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.ime.union(WindowInsets.navigationBars)).padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.Bottom,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        TextField(
            value = text,
            onValueChange = onTextChange,
            placeholder = { Text(L("liveChatPlaceholder")) },
            maxLines = 4,
            shape = RoundedCornerShape(22.dp),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = { if (canSend) onSend() }),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = AppColors.inputFill,
                unfocusedContainerColor = AppColors.inputFill,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
            ),
            modifier = Modifier.weight(1f).testTag("live-chat-field"),
        )
        FilledIconButton(
            onClick = onSend,
            enabled = canSend,
            colors = IconButtonDefaults.filledIconButtonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
            modifier = Modifier.size(48.dp).testTag("live-chat-send"),
        ) {
            if (isSending) {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = AppColors.background)
            } else {
                Icon(Icons.Outlined.ArrowUpward, L("liveSend"))
            }
        }
    }
}
