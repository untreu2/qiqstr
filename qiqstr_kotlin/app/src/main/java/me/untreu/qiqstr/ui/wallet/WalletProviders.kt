package me.untreu.qiqstr.ui.wallet

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.ElectricBolt
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.clickable
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.IconTile

data class WalletProvider(
    val id: String,
    val name: String,
    val detailKey: String,
    val icon: ImageVector,
    val connectScheme: String? = null,
    val fallback: String,
) {
    val supportsOneTap: Boolean get() = connectScheme != null
    val opensInBrowser: Boolean get() = Uri.parse(fallback).host?.contains("play.google.com") == false

    val connectUri: Uri?
        get() {
            val scheme = connectScheme ?: return null
            fun encode(value: String) = Uri.encode(value)
            return Uri.parse("$scheme://connect?appname=${encode("qiqstr")}&appicon=${encode(APP_ICON)}&callback=${encode(WalletService.CALLBACK_URL)}")
        }

    fun open() {
        val uri = connectUri
        if (uri == null) {
            openFallback()
            return
        }
        val opened = runCatching {
            App.context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }.isSuccess
        if (!opened) openFallback()
    }

    private fun openFallback() {
        val uri = Uri.parse(fallback)
        if (opensInBrowser) {
            Router.browse(uri)
        } else {
            runCatching { App.context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                .onFailure { Router.browse(uri) }
        }
    }

    companion object {
        const val APP_ICON = "https://raw.githubusercontent.com/untreu2/qiqstr/master/qiqstr_flutter/assets/main_icon_uni.png"
        private fun play(id: String) = "https://play.google.com/store/apps/details?id=$id"

        val all = listOf(
            WalletProvider("primal", "Primal", "walletProviderPrimal", Icons.Outlined.Bolt, "nostrnwc+primal", play("net.primal.android")),
            WalletProvider("alby-go", "Alby Go", "walletProviderAlbyGo", Icons.Outlined.PhoneAndroid, "nostrnwc+alby", play("com.getalby.mobile")),
            WalletProvider("alby-hub", "Alby Hub", "walletProviderAlbyHub", Icons.Outlined.Dns, fallback = "https://getalby.com/alby-hub"),
            WalletProvider("coinos", "Coinos", "walletProviderCoinos", Icons.Outlined.Language, fallback = "https://coinos.io"),
            WalletProvider("minibits", "Minibits", "walletProviderMinibits", Icons.Outlined.Payments, fallback = play("com.minibits_wallet")),
            WalletProvider("zeus", "ZEUS", "walletProviderZeus", Icons.Outlined.ElectricBolt, fallback = play("app.zeusln.zeus")),
        )

        val oneTap: List<WalletProvider> get() = all.filter { it.supportsOneTap }
    }
}

@Composable
fun WalletProviderRow(provider: WalletProvider) {
    val hint = if (provider.supportsOneTap) L("walletProviderOneTapHint") else L("walletProviderOpenHint")
    ListItem(
        headlineContent = { Text(provider.name, color = AppColors.textPrimary) },
        supportingContent = { Text(L(provider.detailKey), color = AppColors.textSecondary) },
        leadingContent = { IconTile(provider.icon) },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (provider.supportsOneTap) {
                    Surface(shape = CircleShape, color = AppColors.tile) {
                        Text(
                            L("walletOneTap"),
                            Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
                Icon(Icons.AutoMirrored.Outlined.OpenInNew, null, Modifier.size(16.dp), tint = AppColors.textTertiary)
            }
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier
            .clickable { provider.open() }
            .semantics { contentDescription = "${provider.name}. $hint" }
            .testTag("wallet-provider-${provider.id}"),
    )
}
