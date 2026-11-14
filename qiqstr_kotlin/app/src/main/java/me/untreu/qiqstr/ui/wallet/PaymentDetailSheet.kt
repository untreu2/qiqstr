package me.untreu.qiqstr.ui.wallet

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat

@Composable
fun PaymentDetailSheet(transaction: WalletTransaction, onDismiss: () -> Unit) {
    var showTechnical by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().testTag("payment-detail")) {
        SheetTopBar(L("details"), onCancel = null) {
            IconButton(onClick = onDismiss, modifier = Modifier.testTag("payment-detail-close")) {
                Icon(Icons.Outlined.Close, L("done"))
            }
        }
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            Column(
                Modifier.fillMaxWidth().padding(vertical = 12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                TransactionIcon(transaction.isIncoming, size = 48.dp)
                Text(
                    "${WalletFormat.signed(transaction.amountSats, transaction.isIncoming)} ${L("walletSats")}",
                    style = MaterialTheme.typography.displaySmall,
                    fontWeight = FontWeight.SemiBold,
                    color = if (transaction.isIncoming) AppColors.success else AppColors.textPrimary,
                    modifier = Modifier.testTag("payment-detail-amount"),
                )
            }
            FormSection {
                LabeledValue(L("status"), if (transaction.isIncoming) L("received") else L("sent"))
                if (transaction.createdAt > 0) {
                    SectionDivider()
                    LabeledValue(L("date"), TimeFormat.full(transaction.createdAt))
                }
                if (!transaction.isIncoming) {
                    SectionDivider()
                    LabeledRow(L("fee")) { SatsText(transaction.feesSats, color = AppColors.textSecondary) }
                }
                SectionDivider()
                LabeledValue(L("method"), L("walletMethodLightning"))
                transaction.description?.let { description ->
                    SectionDivider()
                    LabeledRow(L("description")) {
                        SelectionContainer { Text(description, color = AppColors.textSecondary, style = MaterialTheme.typography.bodyLarge) }
                    }
                }
            }
            val hash = transaction.paymentHash
            val invoice = transaction.invoice
            if (invoice != null || hash != null) {
                FormSection {
                    ListItem(
                        headlineContent = { Text(L("details")) },
                        trailingContent = { Icon(if (showTechnical) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore, null) },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        modifier = Modifier.clickable { showTechnical = !showTechnical }.testTag("payment-detail-toggle"),
                    )
                    AnimatedVisibility(showTechnical) {
                        Column {
                            if (hash != null) {
                                SectionDivider()
                                CopyRow(L("paymentHash"), hash)
                            }
                            if (invoice != null) {
                                SectionDivider()
                                CopyRow(L("invoice"), invoice)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CopyRow(label: String, value: String) {
    val haptics = LocalHapticFeedback.current
    Row(
        Modifier
            .fillMaxWidth()
            .clickable {
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                WalletClipboard.copy(value, L("copiedToClipboardWithType", "type" to label))
            }
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(label, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
            Text(value, style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace), maxLines = 4)
        }
        Icon(Icons.Outlined.ContentCopy, null, tint = AppColors.textSecondary)
    }
}
