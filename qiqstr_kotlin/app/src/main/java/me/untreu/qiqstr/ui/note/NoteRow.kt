package me.untreu.qiqstr.ui.note

import me.untreu.qiqstr.App
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.material.icons.automirrored.outlined.Reply
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.HeartBroken
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.ComposeContext
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.RelativeTimeText
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile

@Composable
fun NoteRow(
    note: Note,
    modifier: Modifier = Modifier,
    showActions: Boolean = true,
    onClick: (() -> Unit)? = null,
    showsThreadContext: Boolean = true,
    compact: Boolean = false,
    showsConnector: Boolean = false,
    swipeActions: Boolean = false,
) {
    if (NoteInteractionStore.isDeleted(note.id)) return
    if (swipeActions && showActions) {
        NoteSwipeActions(note, modifier) { NoteRowContent(note, Modifier, showActions, onClick, showsThreadContext, compact, showsConnector) }
    } else {
        NoteRowContent(note, modifier, showActions, onClick, showsThreadContext, compact, showsConnector)
    }
}

@Composable
private fun NoteRowContent(
    note: Note,
    modifier: Modifier,
    showActions: Boolean,
    onClick: (() -> Unit)?,
    showsThreadContext: Boolean,
    compact: Boolean,
    showsConnector: Boolean,
) {
    val actions = remember { NoteActionHandler() }
    var showMenu by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val profile = ProfileCache.profiles[note.pubkey]
    val name = profile?.bestName ?: note.authorName ?: Profile.shortNpub(note.pubkey)
    val avatarSize = if (compact) 34.dp else 44.dp
    val dividerColor = AppColors.divider
    Box(modifier.fillMaxWidth()) {
        Column(
            Modifier.fillMaxWidth()
                .background(AppColors.background)
                .combinedClickable(
                    onClick = { onClick?.invoke() ?: Router.push(Route.Thread(note.id)) },
                    onLongClick = if (showActions) {
                        {
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            showMenu = true
                        }
                    } else null,
                )
                .drawBehind {
                    if (showsConnector) {
                        val x = 16.dp.toPx() + avatarSize.toPx() / 2
                        val top = 12.dp.toPx() + avatarSize.toPx() + 4.dp.toPx() + if (note.isRepost && note.repostedBy != null) 24.dp.toPx() else 0f
                        if (size.height > top) drawLine(dividerColor, Offset(x, top), Offset(x, size.height), strokeWidth = 2.dp.toPx())
                    }
                }
                .padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = if (showsConnector) 0.dp else 6.dp)
                .testTag("note-row"),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            val reposter = note.repostedBy
            if (note.isRepost && reposter != null) {
                NoteRepostHeader(reposter, note.repostedByName, Modifier.padding(start = avatarSize - 16.dp))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ProfileAvatar(
                    note.pubkey,
                    size = avatarSize,
                    fallbackUrl = note.authorImage,
                    modifier = Modifier.clip(CircleShape)
                        .clickable { Router.push(Route.Profile(note.pubkey)) }
                        .semantics { contentDescription = name }
                        .testTag("note-avatar"),
                )
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    NoteAuthorLine(note, name, profile?.nip05?.ifEmpty { null } ?: note.authorNip05)
                    if (showsThreadContext && note.isReply) replyTarget(note)?.let { NoteReplyContextLine(it) }
                    NoteContentView(note, style = if (compact) MaterialTheme.typography.bodyMedium else MaterialTheme.typography.bodyLarge)
                    if (showActions) {
                        InteractionBar(note, NoteInteractionStore.model(note), actions, Modifier.padding(top = 2.dp), compact = compact)
                    }
                }
            }
        }
        if (showActions) {
            DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                NoteMenuItems(note, actions) { showMenu = false }
            }
        }
    }
    NoteActionDialogs(actions)
}

fun replyTarget(note: Note): String? {
    note.tags.firstOrNull { it.size > 4 && it[0] == "e" && it[3] == "reply" && it[4].length == 64 }?.let { return it[4] }
    val pTags = note.tags.filter { it.size > 1 && it[0] == "p" && it[1].length == 64 }.map { it[1] }
    return pTags.firstOrNull { it != note.pubkey } ?: pTags.firstOrNull()
}

@Composable
fun NoteAuthorLine(note: Note, name: String, nip05: String?, modifier: Modifier = Modifier, large: Boolean = false) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            name,
            style = if (large) MaterialTheme.typography.titleMedium else MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = AppColors.textPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false),
        )
        if (large && !nip05.isNullOrEmpty()) {
            Text(
                if (nip05.startsWith("_@")) nip05.drop(2) else nip05,
                style = MaterialTheme.typography.bodyMedium,
                color = AppColors.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
        }
        if (!large) RelativeTimeText(note.createdAt, prefix = "· ")
    }
}

@Composable
fun NoteRepostHeader(pubkey: String, fallbackName: String?, modifier: Modifier = Modifier) {
    LaunchedEffect(pubkey) { if (ProfileCache.profile(pubkey) == null) ProfileCache.load(listOf(pubkey)) }
    val name = ProfileCache.profiles[pubkey]?.bestName ?: fallbackName ?: Profile.shortNpub(pubkey)
    Row(
        modifier.clickable { Router.push(Route.Profile(pubkey)) }.testTag("note-repost-header"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(Icons.Filled.Repeat, null, Modifier.size(16.dp), tint = AppColors.textSecondary)
        Text(
            L("feedRepostedBy", "name" to name),
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.Medium,
            color = AppColors.textSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
fun NoteReplyContextLine(pubkey: String, modifier: Modifier = Modifier) {
    LaunchedEffect(pubkey) { if (ProfileCache.profile(pubkey) == null) ProfileCache.load(listOf(pubkey)) }
    val name = ProfileCache.profiles[pubkey]?.bestName ?: Profile.shortNpub(pubkey)
    val style = MaterialTheme.typography.bodySmall
    Row(
        modifier.clickable { Router.push(Route.Profile(pubkey)) }.testTag("note-reply-context"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(Icons.AutoMirrored.Outlined.Reply, null, Modifier.size(14.dp), tint = AppColors.textSecondary)
        Text(L("replyingTo"), style = style, color = AppColors.textSecondary)
        Text("@$name", style = style, fontWeight = FontWeight.Medium, color = AppColors.link, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun NoteSwipeActions(note: Note, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val haptics = LocalHapticFeedback.current
    val state = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.StartToEnd -> {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    Router.compose(ComposeContext.Reply(note))
                }
                SwipeToDismissBoxValue.EndToStart -> {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    App.scope.launch { NoteInteractionStore.toggleReaction(note) }
                }
                SwipeToDismissBoxValue.Settled -> Unit
            }
            false
        },
        positionalThreshold = { it * 0.35f },
    )
    SwipeToDismissBox(
        state = state,
        modifier = modifier,
        backgroundContent = {
            val direction = state.dismissDirection
            val reacted = NoteInteractionStore.model(note).counts.hasReacted
            val (color, icon, label, alignment) = when (direction) {
                SwipeToDismissBoxValue.StartToEnd -> SwipeVisual(AppColors.reply, Icons.AutoMirrored.Filled.Reply, L("reply"), Alignment.CenterStart)
                SwipeToDismissBoxValue.EndToStart -> SwipeVisual(AppColors.reaction, if (reacted) Icons.Filled.HeartBroken else Icons.Filled.Favorite, L("reaction"), Alignment.CenterEnd)
                SwipeToDismissBoxValue.Settled -> SwipeVisual(AppColors.background, Icons.Filled.Favorite, "", Alignment.Center)
            }
            Box(Modifier.fillMaxSize().background(color).padding(horizontal = 24.dp), contentAlignment = alignment) {
                if (direction != SwipeToDismissBoxValue.Settled) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(icon, null, tint = androidx.compose.ui.graphics.Color.White)
                        Spacer(Modifier.width(0.dp))
                        Text(label, style = TextStyle(color = androidx.compose.ui.graphics.Color.White), fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        },
    ) { content() }
}

private data class SwipeVisual(
    val color: androidx.compose.ui.graphics.Color,
    val icon: androidx.compose.ui.graphics.vector.ImageVector,
    val label: String,
    val alignment: Alignment,
)
