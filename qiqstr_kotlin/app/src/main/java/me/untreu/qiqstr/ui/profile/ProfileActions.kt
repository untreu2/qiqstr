package me.untreu.qiqstr.ui.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.PlaylistAdd
import androidx.compose.material.icons.automirrored.outlined.VolumeOff
import androidx.compose.material.icons.automirrored.outlined.VolumeUp
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.QrCode
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.AppSheet
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.services.MuteService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.Session

@Composable
fun ProfileActionButtons(model: ProfileViewModel, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (!model.isMe) {
            ActionIcon(Icons.Outlined.ChatBubbleOutline, L("message"), "profile-message") { Router.push(Route.DMChat(model.pubkey)) }
            if (model.profile.lud16.isNotEmpty()) {
                ActionIcon(Icons.Outlined.Bolt, L("zap"), "profile-zap") { Router.present(AppSheet.ZapProfile(model.pubkey)) }
            }
        }
        ActionIcon(Icons.Outlined.QrCode, L("shareProfile"), "profile-share") { Router.present(AppSheet.ShareProfile(model.pubkey)) }
        if (model.isMe) {
            ActionIcon(Icons.Outlined.Edit, L("editProfileButton"), "profile-edit") { Router.push(Route.EditProfile) }
        } else if (Session.pubkey != null) {
            FollowButton(model.pubkey, displayName = model.displayName, circular = true)
        }
    }
}

@Composable
private fun ActionIcon(icon: ImageVector, label: String, tag: String, onClick: () -> Unit) {
    FilledTonalIconButton(onClick = onClick, modifier = Modifier.size(40.dp).testTag(tag)) {
        Icon(icon, label, Modifier.size(20.dp))
    }
}

object ProfileModeration {
    suspend fun setMuted(pubkey: String, muted: Boolean) {
        try {
            if (muted) MuteService.mute(pubkey) else MuteService.unmute(pubkey)
            DataBus.feedChanged()
        } catch (error: Throwable) {
            ToastCenter.error(error)
        }
    }
}

@Composable
fun ProfileMenu(model: ProfileViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var expanded by remember { mutableStateOf(false) }
    var confirmMute by remember { mutableStateOf(false) }
    var showReport by remember { mutableStateOf(false) }
    var showAddToList by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { expanded = true }, modifier = Modifier.testTag("profile-menu")) {
            Icon(Icons.Outlined.MoreVert, L("profileMoreActions"))
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            MenuItem(L("profileCopyNpub"), Icons.Outlined.ContentCopy, "menu-copy-npub") {
                expanded = false
                ProfileSharing.copy(model.npub, L("copiedNpub"))
            }
            MenuItem(L("profileCopyLink"), Icons.Outlined.Link, "menu-copy-link") {
                expanded = false
                ProfileSharing.copy(model.profileLink, L("profileLinkCopied"))
            }
            MenuItem(L("shareProfile"), Icons.Outlined.Share, "menu-share") {
                expanded = false
                ProfileSharing.share(context, model.profileLink, model.displayName)
            }
            MenuItem(L("profileShowQRCode"), Icons.Outlined.QrCode, "menu-qr") {
                expanded = false
                Router.present(AppSheet.ShareProfile(model.pubkey))
            }
            if (!model.isMe && Session.canSign) {
                HorizontalDivider()
                MenuItem(L("addToList"), Icons.AutoMirrored.Outlined.PlaylistAdd, "menu-add-to-list") {
                    expanded = false
                    showAddToList = true
                }
            }
            if (!model.isMe && Session.pubkey != null) {
                HorizontalDivider()
                if (MuteService.isMuted(model.pubkey)) {
                    MenuItem(L("unmute"), Icons.AutoMirrored.Outlined.VolumeUp, "menu-unmute") {
                        expanded = false
                        scope.launch { ProfileModeration.setMuted(model.pubkey, false) }
                    }
                } else {
                    MenuItem(L("mute"), Icons.AutoMirrored.Outlined.VolumeOff, "menu-mute", destructive = true) {
                        expanded = false
                        confirmMute = true
                    }
                }
                MenuItem(L("report"), Icons.Outlined.Flag, "menu-report", destructive = true) {
                    expanded = false
                    showReport = true
                }
            }
        }
    }
    if (confirmMute) {
        AlertDialog(
            onDismissRequest = { confirmMute = false },
            title = { Text(L("muteUser", "user" to model.displayName)) },
            text = { Text(L("muteUserDescription")) },
            confirmButton = {
                Box(Modifier.testTag("confirm-mute")) {
                    TextAction(L("mute"), {
                        confirmMute = false
                        scope.launch { ProfileModeration.setMuted(model.pubkey, true) }
                    }, color = AppColors.error)
                }
            },
            dismissButton = { TextAction(L("cancel"), { confirmMute = false }) },
        )
    }
    if (showReport) ProfileReportSheet(model.pubkey, model.displayName) { showReport = false }
    if (showAddToList) AddToListSheet(model.pubkey, model.displayName) { showAddToList = false }
}

@Composable
private fun MenuItem(title: String, icon: ImageVector, tag: String, destructive: Boolean = false, onClick: () -> Unit) {
    val color = if (destructive) AppColors.error else AppColors.textPrimary
    DropdownMenuItem(
        text = { Text(title, color = color) },
        leadingIcon = { Icon(icon, null, tint = color) },
        onClick = onClick,
        modifier = Modifier.testTag(tag),
    )
}
