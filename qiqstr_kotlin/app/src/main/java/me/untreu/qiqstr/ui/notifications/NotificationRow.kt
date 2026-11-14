package me.untreu.qiqstr.ui.notifications

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AlternateEmail
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.NotificationKind
import me.untreu.qiqstr.domain.Profile

val NotificationKind.icon: ImageVector
    get() = when (this) {
        NotificationKind.REACTION -> Icons.Filled.Favorite
        NotificationKind.REPOST -> Icons.Filled.Repeat
        NotificationKind.REPLY -> Icons.Filled.ChatBubble
        NotificationKind.MENTION -> Icons.Filled.AlternateEmail
        NotificationKind.QUOTE -> Icons.Filled.FormatQuote
        NotificationKind.ZAP -> Icons.Filled.Bolt
        NotificationKind.UNKNOWN -> Icons.Filled.Notifications
    }

val NotificationKind.tint: Color
    @Composable get() = when (this) {
        NotificationKind.REACTION -> AppColors.reaction
        NotificationKind.REPOST -> AppColors.repost
        NotificationKind.REPLY -> AppColors.reply
        NotificationKind.ZAP -> AppColors.zap
        NotificationKind.MENTION, NotificationKind.QUOTE, NotificationKind.UNKNOWN -> AppColors.textSecondary
    }

val NotificationKind.actionText: String
    get() = when (this) {
        NotificationKind.REACTION -> L("reactedToYourPost")
        NotificationKind.REPOST -> L("repostedYourPost")
        NotificationKind.REPLY -> L("repliedToYourPost")
        NotificationKind.MENTION -> L("mentionedYou")
        NotificationKind.QUOTE -> L("quotedYourPost")
        NotificationKind.ZAP -> L("zappedYou")
        NotificationKind.UNKNOWN -> L("interactedWithYou")
    }

@Composable
fun NotificationRowView(group: NotificationGroup, isUnread: Boolean) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        NotificationAvatars(group)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Headline(group, Modifier.weight(1f))
                Text(timestamp(group), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
                if (isUnread) {
                    Box(Modifier.padding(top = 5.dp).size(8.dp).clip(CircleShape).background(AppColors.accent))
                }
            }
            val showsContent = !group.isGrouped && (group.kind == NotificationKind.REPLY || group.kind == NotificationKind.MENTION || group.kind == NotificationKind.QUOTE)
            if (showsContent) {
                val text = NotificationText.readable(group.lead.content)
                if (text.isNotEmpty()) Text(text, style = MaterialTheme.typography.bodyMedium, maxLines = 6)
            }
            val target = group.targetNoteId
            if (!target.isNullOrEmpty() && group.kind != NotificationKind.MENTION) NotificationNotePreview(target)
        }
    }
}

private fun timestamp(group: NotificationGroup): String =
    if (TimeFormat.now - group.createdAt < 60) L("now") else TimeFormat.relative(group.createdAt)

@Composable
private fun NotificationAvatars(group: NotificationGroup) {
    val shown = group.authors.take(3)
    val open = { shown.firstOrNull()?.takeIf { it.isNotEmpty() }?.let { Router.push(Route.Profile(it)) } }
    Box(Modifier.testTag("notification-avatar")) {
        if (shown.size <= 1) {
            ProfileAvatar(group.lead.fromPubkey, size = 42.dp, fallbackUrl = group.lead.fromImage, modifier = Modifier.clickable { open() })
        } else {
            Row(Modifier.clickable { open() }, horizontalArrangement = Arrangement.spacedBy((-14).dp)) {
                shown.forEachIndexed { index, pubkey ->
                    ProfileAvatar(
                        pubkey,
                        size = 34.dp,
                        fallbackUrl = group.items.firstOrNull { it.fromPubkey == pubkey }?.fromImage,
                        modifier = Modifier.zIndex((shown.size - index).toFloat()).border(2.dp, AppColors.background, CircleShape),
                    )
                }
            }
        }
        Box(
            Modifier.align(Alignment.BottomEnd).offset(4.dp, 4.dp).size(20.dp).clip(CircleShape).background(AppColors.background).zIndex(10f),
            contentAlignment = Alignment.Center,
        ) {
            val emoji = reactionEmoji(group)
            if (group.kind == NotificationKind.REACTION && !group.isGrouped && emoji != null) {
                Text(emoji, style = MaterialTheme.typography.labelSmall)
            } else {
                Icon(group.kind.icon, null, Modifier.size(12.dp), tint = group.kind.tint)
            }
        }
    }
}

private fun reactionEmoji(group: NotificationGroup): String? {
    val content = group.lead.content.trim()
    if (content.isEmpty() || content == "+" || content.startsWith(":")) return null
    val iterator = android.icu.text.BreakIterator.getCharacterInstance().apply { setText(content) }
    var graphemes = 0
    while (iterator.next() != android.icu.text.BreakIterator.DONE) graphemes++
    return if (graphemes > 2) null else content
}

private fun name(group: NotificationGroup, pubkey: String): String {
    ProfileCache.profiles[pubkey]?.let { profile ->
        if (profile.name.isNotEmpty()) return profile.name
        if (profile.displayName.isNotEmpty()) return profile.displayName
    }
    group.items.firstOrNull { it.fromPubkey == pubkey }?.fromName?.let { return it }
    return Profile.shortNpub(pubkey)
}

@Composable
private fun Headline(group: NotificationGroup, modifier: Modifier) {
    val zapColor = AppColors.zap
    val bold = SpanStyle(fontWeight = FontWeight.SemiBold)
    val text = buildAnnotatedString {
        val authors = group.authors.ifEmpty { listOf(group.lead.fromPubkey) }
        if (authors.size <= 3) {
            authors.forEachIndexed { i, pk ->
                if (i > 0) append(", ")
                withStyle(bold) { append(name(group, pk)) }
            }
        } else {
            withStyle(bold) { append(name(group, authors[0])) }
            append(", ")
            withStyle(bold) { append(name(group, authors[1])) }
            append(" " + L("andCountOthers", "count" to authors.size - 2))
        }
        append(" " + group.kind.actionText)
        if (group.kind == NotificationKind.ZAP && group.totalZapAmount > 0) {
            withStyle(bold.copy(color = zapColor)) { append(" " + L("notificationZapSatsCount", "count" to group.totalZapAmount)) }
        }
    }
    Text(text, style = MaterialTheme.typography.bodyMedium, modifier = modifier)
}
