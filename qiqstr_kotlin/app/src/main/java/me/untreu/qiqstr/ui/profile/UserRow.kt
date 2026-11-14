package me.untreu.qiqstr.ui.profile

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.QrCode
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.app.AppSheet
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Profile

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun UserRow(pubkey: String, modifier: Modifier = Modifier, showFollow: Boolean = true, onClick: (() -> Unit)? = null) {
    val profile = ProfileCache.profiles[pubkey]
    val isMe = Session.pubkey == pubkey
    val haptics = LocalHapticFeedback.current
    var menu by remember { mutableStateOf(false) }
    LaunchedEffect(pubkey) { if (ProfileCache.profile(pubkey) == null) ProfileCache.load(listOf(pubkey)) }
    Box(modifier.testTag("user-row-${pubkey.take(12)}")) {
        Row(
            Modifier.fillMaxWidth()
                .combinedClickable(
                    onClick = { onClick?.invoke() ?: Router.push(Route.Profile(pubkey)) },
                    onLongClick = { haptics.performHapticFeedback(HapticFeedbackType.LongPress); menu = true },
                )
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            ProfileAvatar(pubkey, size = 46.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    profile?.bestName ?: Profile.shortNpub(pubkey),
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                val nip05 = profile?.nip05?.ifEmpty { null }
                Text(
                    nip05?.let(Nip05Verifier::display) ?: Profile.shortNpub(pubkey),
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (showFollow && !isMe && Session.pubkey != null) FollowButton(pubkey, compact = true)
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(
                text = { Text(L("profile")) },
                leadingIcon = { Icon(Icons.Outlined.Person, null) },
                onClick = { menu = false; Router.push(Route.Profile(pubkey)) },
            )
            DropdownMenuItem(
                text = { Text(L("copy")) },
                leadingIcon = { Icon(Icons.Outlined.ContentCopy, null) },
                onClick = { menu = false; ProfileSharing.copy(Nip19.npub(pubkey) ?: pubkey, L("copiedNpub")) },
            )
            if (!isMe) {
                DropdownMenuItem(
                    text = { Text(L("message")) },
                    leadingIcon = { Icon(Icons.AutoMirrored.Outlined.Chat, null) },
                    onClick = { menu = false; Router.push(Route.DMChat(pubkey)) },
                )
            }
            DropdownMenuItem(
                text = { Text(L("shareProfile")) },
                leadingIcon = { Icon(Icons.Outlined.QrCode, null) },
                onClick = { menu = false; Router.present(AppSheet.ShareProfile(pubkey)) },
            )
        }
    }
}
