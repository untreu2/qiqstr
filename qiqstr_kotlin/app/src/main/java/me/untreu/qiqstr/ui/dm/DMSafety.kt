package me.untreu.qiqstr.ui.dm

import com.qiqstr.core.signEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Block
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.services.MuteService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Profile

class DMSafetyModel {
    var blockTarget by mutableStateOf<String?>(null)
    var deleteTarget by mutableStateOf<String?>(null)
    var reportTarget by mutableStateOf<String?>(null)
}

private enum class DMReportReason(val raw: String, val key: String) {
    SPAM("spam", "reportReasonSpam"),
    NUDITY("nudity", "reportReasonNudity"),
    PROFANITY("profanity", "reportReasonProfanity"),
    ILLEGAL("illegal", "reportReasonIllegal"),
    IMPERSONATION("impersonation", "reportReasonImpersonation"),
    OTHER("other", "reportReasonOther"),
}

private object DMModeration {
    suspend fun mute(pubkey: String) {
        runCatching { MuteService.mute(pubkey) }
        DataBus.feedChanged()
    }

    suspend fun report(pubkey: String, reason: DMReportReason, muteAuthor: Boolean): Boolean {
        if (muteAuthor) mute(pubkey)
        if (!Session.canSign) return false
        return runCatching {
            val event = signEvent(1984u.toUShort(), "", listOf(listOf("p", pubkey, reason.raw)))
            SyncService.publish(event)
        }.isSuccess
    }
}

private fun displayName(pubkey: String) = DMService.group(pubkey)?.displayName ?: ProfileCache.profile(pubkey)?.bestName ?: Profile.shortNpub(pubkey)

@Composable
fun DMSafetyMenuItems(peer: String, safety: DMSafetyModel, onDismiss: () -> Unit) {
    HorizontalDivider()
    if (!DMService.isGroup(peer)) {
    if (peer in MuteService.mutedPubkeys) {
        DropdownMenuItem(
            text = { Text(L("dmUnblock")) },
            leadingIcon = { Icon(Icons.Outlined.PanTool, null) },
            onClick = {
                onDismiss()
                App.scope.launch { runCatching { MuteService.unmute(peer) } }
            },
            modifier = Modifier.testTag("dm-unblock"),
        )
    } else {
        DropdownMenuItem(
            text = { Text(L("block"), color = AppColors.error) },
            leadingIcon = { Icon(Icons.Outlined.Block, null, tint = AppColors.error) },
            onClick = { onDismiss(); safety.blockTarget = peer },
            modifier = Modifier.testTag("dm-block"),
        )
    }
    DropdownMenuItem(
        text = { Text(L("report"), color = AppColors.error) },
        leadingIcon = { Icon(Icons.Outlined.Flag, null, tint = AppColors.error) },
        onClick = { onDismiss(); safety.reportTarget = peer },
        modifier = Modifier.testTag("dm-report"),
    )
    }
    DropdownMenuItem(
        text = { Text(L("dmDeleteConversation"), color = AppColors.error) },
        leadingIcon = { Icon(Icons.Outlined.DeleteOutline, null, tint = AppColors.error) },
        onClick = { onDismiss(); safety.deleteTarget = peer },
        modifier = Modifier.testTag("dm-delete-conversation"),
    )
}

@Composable
fun DMSafetyDialogs(safety: DMSafetyModel, onRemoved: ((String) -> Unit)? = null) {
    safety.blockTarget?.let { peer ->
        AlertDialog(
            onDismissRequest = { safety.blockTarget = null },
            title = { Text(L("dmBlockUser", "user" to displayName(peer))) },
            text = { Text(L("dmBlockMessage")) },
            confirmButton = {
                TextAction(L("block"), {
                    safety.blockTarget = null
                    App.scope.launch {
                        DMModeration.mute(peer)
                        ToastCenter.show(L("dmUserBlocked"), ToastStyle.SUCCESS)
                        onRemoved?.invoke(peer)
                    }
                }, color = AppColors.error)
            },
            dismissButton = { TextAction(L("cancel"), { safety.blockTarget = null }) },
            modifier = Modifier.testTag("dm-block-confirm"),
        )
    }
    safety.deleteTarget?.let { peer ->
        AlertDialog(
            onDismissRequest = { safety.deleteTarget = null },
            title = { Text(L("dmDeleteConversation")) },
            text = { Text(L("dmDeleteConversationMessage")) },
            confirmButton = {
                TextAction(L("delete"), {
                    safety.deleteTarget = null
                    DMService.deleteConversation(peer)
                    onRemoved?.invoke(peer)
                }, color = AppColors.error)
            },
            dismissButton = { TextAction(L("cancel"), { safety.deleteTarget = null }) },
            modifier = Modifier.testTag("dm-delete-confirm"),
        )
    }
    safety.reportTarget?.let { peer ->
        DMReportSheet(peer, onDismiss = { safety.reportTarget = null }) {
            if (MuteService.isMuted(peer)) onRemoved?.invoke(peer)
        }
    }
}

@Composable
private fun DMReportSheet(pubkey: String, onDismiss: () -> Unit, onFinish: () -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    var reason by remember { mutableStateOf<DMReportReason?>(null) }
    var muteAuthor by remember { mutableStateOf(true) }
    var isWorking by remember { mutableStateOf(false) }
    val close: () -> Unit = {
        scope.launch { state.hide() }.invokeOnCompletion { onDismiss() }
    }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, containerColor = AppColors.background) {
        Column(Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = close, modifier = Modifier.testTag("report-cancel")) { Icon(Icons.Outlined.Close, L("cancel")) }
                Text(
                    L("reportUser", "user" to displayName(pubkey)),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    modifier = Modifier.weight(1f),
                )
                Button(
                    onClick = {
                        val selected = reason ?: return@Button
                        if (isWorking) return@Button
                        isWorking = true
                        App.scope.launch {
                            val sent = DMModeration.report(pubkey, selected, muteAuthor)
                            isWorking = false
                            ToastCenter.show(L(if (sent) "reportSentHidden" else "reportHiddenOnly"), ToastStyle.SUCCESS)
                            onDismiss()
                            onFinish()
                        }
                    },
                    enabled = reason != null && !isWorking,
                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
                    modifier = Modifier.testTag("report-submit"),
                ) { Text(L("report")) }
            }
            DMReportReason.entries.forEach { item ->
                ListItem(
                    headlineContent = { Text(L(item.key)) },
                    trailingContent = { if (reason == item) Icon(Icons.Outlined.Check, null) },
                    colors = ListItemDefaults.colors(containerColor = AppColors.background),
                    modifier = Modifier.clickable { reason = item }.testTag("report-reason-${item.raw}"),
                )
            }
            Text(
                L("reportUserDescription"),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textSecondary,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            ListItem(
                headlineContent = { Text(L("reportAlsoMute")) },
                trailingContent = {
                    Switch(
                        checked = muteAuthor,
                        onCheckedChange = { muteAuthor = it },
                        colors = SwitchDefaults.colors(checkedTrackColor = AppColors.switchActive),
                        modifier = Modifier.testTag("report-also-mute"),
                    )
                },
                colors = ListItemDefaults.colors(containerColor = AppColors.background),
            )
            Text(
                L("muteUserDescription"),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textSecondary,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 24.dp),
            )
        }
    }
}

@Composable
fun DMMediaGate(message: DMMessage, shape: Shape, content: @Composable () -> Unit) {
    var isAllowed by remember(message.id) { mutableStateOf(false) }
    if (isAllowed || message.isMine || DMService.isKnown(message.peer)) {
        content()
        return
    }
    Box(
        Modifier
            .defaultMinSize(minWidth = 200.dp, minHeight = 96.dp)
            .clip(shape)
            .background(AppColors.tile)
            .clickable { isAllowed = true }
            .padding(horizontal = 16.dp)
            .testTag("dm-media-gate"),
        contentAlignment = Alignment.Center,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.VisibilityOff, null, Modifier.size(18.dp), tint = AppColors.textSecondary)
            Text(L("dmLoadMedia"), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = AppColors.textSecondary)
        }
    }
}
