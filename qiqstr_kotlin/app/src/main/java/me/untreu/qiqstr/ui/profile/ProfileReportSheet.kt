package me.untreu.qiqstr.ui.profile

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.PrimaryButton
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.services.InteractionService
import me.untreu.qiqstr.data.services.MuteService
import me.untreu.qiqstr.data.services.NoteReportReason
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Profile

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileReportSheet(pubkey: String, displayName: String?, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var reason by remember { mutableStateOf<NoteReportReason?>(null) }
    var muteAuthor by remember { mutableStateOf(true) }
    var isWorking by remember { mutableStateOf(false) }
    val name = ProfileCache.profiles[pubkey]?.bestName ?: displayName ?: Profile.shortNpub(pubkey)

    fun submit() {
        val selected = reason ?: return
        if (isWorking) return
        isWorking = true
        scope.launch {
            if (muteAuthor) {
                runCatching { MuteService.mute(pubkey) }
                DataBus.feedChanged()
            }
            val sent = Session.canSign && runCatching { InteractionService.report(pubkey, null, selected.raw) }.isSuccess
            isWorking = false
            ToastCenter.show(L(if (sent) "reportSentHidden" else "reportHiddenOnly"), ToastStyle.SUCCESS)
            onDismiss()
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = AppColors.background,
    ) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.testTag("report-cancel")) { TextAction(L("cancel"), onDismiss) }
                Text(
                    L("reportUser", "user" to name),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
                )
            }
            NoteReportReason.entries.forEach { item ->
                ListItem(
                    headlineContent = { Text(item.title) },
                    trailingContent = { if (reason == item) Icon(Icons.Outlined.Check, null, tint = AppColors.textPrimary) },
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
                supportingContent = { Text(L("muteUserDescription")) },
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
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                PrimaryButton(
                    L("report"),
                    ::submit,
                    enabled = reason != null,
                    loading = isWorking,
                    modifier = Modifier.fillMaxWidth().testTag("report-submit"),
                )
            }
        }
    }
}
