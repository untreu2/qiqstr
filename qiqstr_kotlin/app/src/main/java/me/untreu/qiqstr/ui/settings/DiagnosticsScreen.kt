package me.untreu.qiqstr.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import java.text.DateFormat
import java.util.Date
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.AppLanguage
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.TextAction

@Composable
fun DiagnosticsScreen() {
    val store = DiagnosticsStore
    var confirmDelete by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { store.reload() }
    SettingsScaffold(
        L("diagnosticsTitle"),
        tag = "diagnostics-list",
        actions = {
            if (store.reports.isNotEmpty()) {
                IconButton(onClick = { confirmDelete = true }, modifier = Modifier.testTag("diagnostics-delete-all")) {
                    Icon(Icons.Outlined.Delete, L("diagnosticsDeleteAll"))
                }
            }
        },
    ) {
        settingsSection("reports", footer = L("diagnosticsFooterAndroid")) {
            if (store.reports.isEmpty()) {
                EmptyStateView(Icons.Outlined.Verified, L("diagnosticsEmpty"), L("diagnosticsEmptyMessageAndroid"), modifier = Modifier.testTag("diagnostics-empty"))
            }
            store.reports.forEach { report -> key(report.id) { ReportRow(report) } }
        }
    }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(L("diagnosticsDeleteAll")) },
            confirmButton = { TextAction(L("diagnosticsDeleteAll"), { confirmDelete = false; store.deleteAll() }, color = AppColors.error) },
            dismissButton = { TextAction(L("cancel"), { confirmDelete = false }) },
        )
    }
}

private fun title(report: DiagnosticReport): String {
    val parts = mutableListOf<String>()
    if (report.crashes > 0) parts.add(L("diagnosticsCrashes", "count" to report.crashes))
    if (report.hangs > 0) parts.add(L("diagnosticsHangs", "count" to report.hangs))
    if (report.other > 0 || parts.isEmpty()) parts.add(L("diagnosticsOther"))
    return parts.joinToString(", ")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReportRow(report: DiagnosticReport) {
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) DiagnosticsStore.delete(report)
        false
    })
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(Modifier.fillMaxSize().background(AppColors.error).padding(horizontal = 20.dp), contentAlignment = Alignment.CenterEnd) {
                Icon(Icons.Outlined.Delete, L("delete"), tint = MaterialTheme.colorScheme.onError)
            }
        },
        modifier = Modifier.testTag("diagnostics-report"),
    ) {
        SettingsRow(
            title(report),
            subtitle = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, AppLanguage.locale).format(Date(report.receivedAt)),
            trailing = { Icon(Icons.Outlined.Share, L("share"), tint = AppColors.textSecondary) },
        ) { SettingsShare.text(DiagnosticsStore.contents(report), report.file.name) }
    }
}
