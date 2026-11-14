package me.untreu.qiqstr.ui.explore

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.services.FollowSetService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.profile.FollowButton

@Composable
fun ExploreUserRow(profile: Profile, modifier: Modifier = Modifier, showsFollowButton: Boolean = true, avatarSize: Dp = 44.dp) {
    val resolved = ProfileCache.profiles[profile.pubkey] ?: profile
    Row(
        modifier.fillMaxWidth().padding(vertical = 2.dp).testTag("user-row-${profile.pubkey}"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        ProfileAvatar(profile.pubkey, size = avatarSize, fallbackUrl = profile.picture.ifEmpty { null })
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(resolved.bestName, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                resolved.nip05.ifEmpty { null } ?: Profile.shortNpub(profile.pubkey),
                style = MaterialTheme.typography.bodyMedium,
                color = AppColors.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (showsFollowButton && profile.pubkey != Session.pubkey) FollowButton(profile.pubkey, compact = true)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LongPressMenuBox(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    menu: @Composable ColumnScope.(dismiss: () -> Unit) -> Unit,
    content: @Composable () -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box(modifier.combinedClickable(onClick = onClick, onLongClick = { open = true })) {
        content()
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) { menu { open = false } }
    }
}

@Composable
fun MenuAction(title: String, icon: ImageVector?, destructive: Boolean = false, onClick: () -> Unit) {
    val color = if (destructive) AppColors.error else Color.Unspecified
    DropdownMenuItem(
        text = { Text(title, color = color) },
        leadingIcon = icon?.let { { Icon(it, null, tint = if (destructive) AppColors.error else AppColors.textPrimary) } },
        onClick = onClick,
    )
}

@Composable
fun ExploreUserMenu(pubkey: String, dismiss: () -> Unit) {
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    var showsLists by remember { mutableStateOf(false) }
    MenuAction(L("exploreOpenProfile"), Icons.Outlined.AccountCircle) {
        dismiss()
        Router.push(Route.Profile(pubkey))
    }
    MenuAction(L("exploreCopyNpub"), Icons.Outlined.ContentCopy) {
        dismiss()
        clipboard.setText(AnnotatedString(Nip19.npub(pubkey) ?: pubkey))
        ToastCenter.show(L("copiedNpub"), ToastStyle.SUCCESS)
    }
    val sets = FollowSetService.sets
    if (sets.isNotEmpty() && pubkey != Session.pubkey) {
        MenuAction(L("addToList"), Icons.AutoMirrored.Outlined.List) { showsLists = !showsLists }
        if (showsLists) {
            sets.forEach { set ->
                val member = pubkey in set.pubkeys
                MenuAction(set.displayTitle, if (member) Icons.Filled.CheckCircle else Icons.Outlined.Circle) {
                    dismiss()
                    scope.launch {
                        runCatching {
                            if (member) FollowSetService.removeMember(pubkey, from = set.id) else FollowSetService.addMember(pubkey, to = set.id)
                        }.onSuccess {
                            ToastCenter.show(L(if (member) "exploreMemberRemoved" else "exploreMemberAdded"), ToastStyle.SUCCESS)
                        }.onFailure(ToastCenter::error)
                    }
                }
            }
        }
    }
}
