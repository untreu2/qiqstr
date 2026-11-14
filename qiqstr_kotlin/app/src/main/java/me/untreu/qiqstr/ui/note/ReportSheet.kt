package me.untreu.qiqstr.ui.note

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.data.services.InteractionService
import me.untreu.qiqstr.data.services.MuteService
import me.untreu.qiqstr.data.services.NoteReportReason
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile

@Immutable
data class ReportTarget(val pubkey: String, val eventId: String? = null, val parentId: String? = null, val name: String? = null) {
    val id: String get() = eventId ?: pubkey

    companion object {
        fun from(note: Note) = ReportTarget(note.pubkey, note.id, note.parentId, note.authorName)
    }
}

object Moderation {
    suspend fun report(target: ReportTarget, reason: NoteReportReason, muteAuthor: Boolean): Boolean {
        target.eventId?.let { NoteInteractionStore.hide(it, target.parentId) }
        if (muteAuthor) mute(target.pubkey)
        if (!Session.canSign) return false
        return runCatching { InteractionService.report(target.pubkey, target.eventId, reason.raw) }.isSuccess
    }

    suspend fun mute(pubkey: String) {
        runCatching { MuteService.mute(pubkey) }
        DataBus.feedChanged()
    }
}

@Composable
fun ReportSheet(target: ReportTarget, onDismiss: () -> Unit, onFinish: ((ReportTarget) -> Unit)? = null) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, containerColor = AppColors.background) {
        ReportSheetContent(target, onDismiss, onFinish)
    }
}

@Composable
fun ReportSheetContent(target: ReportTarget, onDismiss: () -> Unit, onFinish: ((ReportTarget) -> Unit)? = null) {
    var reason by remember { mutableStateOf<NoteReportReason?>(null) }
    var muteAuthor by remember { mutableStateOf(true) }
    var isWorking by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val name = ProfileCache.profiles[target.pubkey]?.bestName ?: target.name ?: Profile.shortNpub(target.pubkey)
    val submit = {
        val chosen = reason
        if (chosen != null && !isWorking) {
            isWorking = true
            scope.launch {
                val sent = Moderation.report(target, chosen, muteAuthor)
                isWorking = false
                ToastCenter.show(L(if (sent) "reportSentHidden" else "reportHiddenOnly"), ToastStyle.SUCCESS)
                onDismiss()
                onFinish?.invoke(target)
            }
        }
    }
    Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
        TopAppBar(
            title = { Text(L("reportUser", "user" to name), maxLines = 1) },
            navigationIcon = {
                IconButton(onClick = onDismiss, modifier = Modifier.testTag("report-cancel")) { Icon(Icons.Filled.Close, L("cancel")) }
            },
            actions = {
                Button(
                    onClick = submit,
                    enabled = reason != null && !isWorking,
                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
                    modifier = Modifier.padding(end = 8.dp).testTag("report-submit"),
                ) { Text(L("report"), fontWeight = FontWeight.SemiBold) }
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background),
        )
        Column(Modifier.verticalScroll(rememberScrollState())) {
            NoteReportReason.entries.forEach { item ->
                ListItem(
                    headlineContent = { Text(item.title) },
                    trailingContent = { if (reason == item) Icon(Icons.Filled.Check, null, tint = AppColors.textPrimary) },
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
                    Switch(checked = muteAuthor, onCheckedChange = { muteAuthor = it }, modifier = Modifier.testTag("report-also-mute"))
                },
                colors = ListItemDefaults.colors(containerColor = AppColors.background),
                modifier = Modifier.clickable { muteAuthor = !muteAuthor },
            )
            Text(
                L("muteUserDescription"),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textSecondary,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 24.dp),
            )
        }
    }
}
