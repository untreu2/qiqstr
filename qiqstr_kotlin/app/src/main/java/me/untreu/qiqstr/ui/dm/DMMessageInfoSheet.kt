package me.untreu.qiqstr.ui.dm

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Profile

@Composable
fun DMMessageInfoSheet(message: DMMessage, deliveryRelays: List<String>, chatRelays: List<String>, onDone: () -> Unit) {
    LaunchedEffect(message.sender) { ProfileCache.load(listOf(message.sender)) }
    val senderName = if (message.isMine) L("dmYou") else ProfileCache.profiles[message.sender]?.bestName ?: Profile.shortNpub(message.sender)
    val status = when (message.state) {
        DMDeliveryState.SENT -> if (message.isMine) L("dmInfoStatusSent") else L("dmInfoStatusReceived")
        DMDeliveryState.SENDING -> L("dmSending")
        DMDeliveryState.FAILED -> L("dmSendFailed")
    }
    val unencrypted = message.isFile && message.file?.isEncrypted == false
    Column(Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(bottom = 16.dp)) {
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(L("dmInfo"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            TextAction(L("done"), onDone)
        }
        InfoRow(if (message.isMine) L("dmInfoSent") else L("dmInfoReceived"), DMFormat.infoDate(message.createdAt))
        InfoRow(L("dmInfoFrom"), senderName)
        InfoRow(L("dmInfoStatus"), status)
        InfoRow(L("dmInfoType"), if (message.isFile) L("dmAttachment") else L("dmInfoText"))
        HorizontalDivider(Modifier.padding(vertical = 8.dp))
        ListItem(
            headlineContent = { Text(if (unencrypted) L("notEncrypted") else L("dmInfoEncrypted"), color = AppColors.textSecondary) },
            leadingContent = { Icon(if (unencrypted) Icons.Outlined.WarningAmber else Icons.Outlined.Lock, null, tint = AppColors.textSecondary) },
            colors = ListItemDefaults.colors(containerColor = AppColors.background),
        )
        HorizontalDivider(Modifier.padding(vertical = 8.dp))
        if (message.isMine) {
            RelaySection(L("dmInfoDeliveredTo"), deliveryRelays, if (deliveryRelays.isEmpty()) L("dmInfoRelaysUnknown") else L("dmInfoDeliveredFooter"))
        } else {
            RelaySection(L("dmInfoChatRelays"), chatRelays, if (chatRelays.isEmpty()) L("dmInfoRelaysUnknown") else L("dmInfoChatFooter"))
        }
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    ListItem(
        headlineContent = { Text(label) },
        trailingContent = { Text(value, color = AppColors.textSecondary, textAlign = TextAlign.End, style = MaterialTheme.typography.bodyMedium) },
        colors = ListItemDefaults.colors(containerColor = AppColors.background),
    )
}

@Composable
private fun RelaySection(title: String, relays: List<String>, footer: String) {
    Text(
        title,
        style = MaterialTheme.typography.labelLarge,
        color = AppColors.textSecondary,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
    relays.forEach { relay ->
        ListItem(
            headlineContent = {
                SelectionContainer { Text(relay.replace("wss://", ""), maxLines = 1, overflow = TextOverflow.Ellipsis) }
            },
            leadingContent = { Icon(Icons.Outlined.Dns, null, tint = AppColors.textSecondary) },
            colors = ListItemDefaults.colors(containerColor = AppColors.background),
        )
    }
    Text(
        footer,
        style = MaterialTheme.typography.bodySmall,
        color = AppColors.textSecondary,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
}
