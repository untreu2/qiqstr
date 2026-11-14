package me.untreu.qiqstr.ui.settings

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Contrast
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Hub
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.MedicalServices
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.SettingsInputAntenna
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.QrCode
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.BuildConfig
import me.untreu.qiqstr.app.AppSheet
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.app.SettingsRoute
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.AppLanguage
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.ThemeState
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.auth.AuthTermsSheet
import me.untreu.qiqstr.ui.auth.AuthTermsText
import me.untreu.qiqstr.ui.auth.SecureClipboard
import me.untreu.qiqstr.ui.auth.rememberHaptics

private const val SOURCE_URL = "https://github.com/untreu2/qiqstr"

val settingsVersionString: String get() = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"

@Composable
fun SettingsScreen() {
    var showLogout by remember { mutableStateOf(false) }
    var showTerms by remember { mutableStateOf(false) }
    var isLoggingOut by remember { mutableStateOf(false) }
    val tile = AppColors.settingsTile
    val languageName = AppLanguage.from(ThemeState.language)?.displayName ?: L("settingsSystemDefault")
    val pubkey = Session.pubkey

    fun open(page: SettingsRoute) = Router.push(Route.SettingsPage(page))

    SettingsScaffold(L("settings"), tag = "settings-list") {
        if (pubkey != null) item("account") { AccountHeader(pubkey) }
        settingsSection("security") {
            Link(L("keys"), Icons.Filled.Key, tile, "settings-row-KEYS") { open(SettingsRoute.KEYS) }
            Link(L("relays"), Icons.Filled.Hub, tile, "settings-row-RELAYS") { open(SettingsRoute.RELAYS) }
            Link(
                L("notifications"),
                Icons.Filled.NotificationsActive,
                tile,
                "settings-row-notifications",
                if (LocalNotificationService.isDelivering) L("localNotifyOn") else L("localNotifyOff"),
            ) { open(SettingsRoute.NOTIFICATIONS) }
            Link(L("muted"), Icons.Filled.NotificationsOff, tile, "settings-row-MUTED") { open(SettingsRoute.MUTED) }
            Link(L("safetyTitle"), Icons.Filled.PanTool, tile, "settings-row-safety") { open(SettingsRoute.SAFETY) }
        }
        settingsSection("display") {
            Link(L("display"), Icons.Filled.Contrast, tile, "settings-row-DISPLAY") { open(SettingsRoute.DISPLAY) }
            Link(L("language"), Icons.Filled.Translate, tile, "settings-row-LANGUAGE", languageName) { open(SettingsRoute.LANGUAGE) }
            Link(L("payments"), Icons.Filled.Bolt, tile, "settings-row-PAYMENTS") { open(SettingsRoute.PAYMENTS) }
        }
        settingsSection("data") {
            Link(L("databaseCache"), Icons.Filled.Storage, tile, "settings-row-DATABASE") { open(SettingsRoute.DATABASE) }
            Link(L("yourDataOnRelays"), Icons.Filled.SettingsInputAntenna, tile, "settings-row-EVENT_MANAGER") { open(SettingsRoute.EVENT_MANAGER) }
        }
        settingsSection("accounts") {
            SettingsRow(
                L("switchAccount"),
                Icons.Filled.People,
                fill = tile,
                value = if (Session.accounts.size > 1) "${Session.accounts.size}" else null,
                modifier = Modifier.testTag("settings-switch-account"),
            ) { Router.present(AppSheet.SwitchAccount) }
        }
        settingsSection("about") {
            SettingsRow(L("settingsTerms"), Icons.Filled.Description, fill = tile, modifier = Modifier.testTag("settings-terms")) { showTerms = true }
            SettingsRow(L("settingsContactSupport"), Icons.Filled.Email, fill = tile, modifier = Modifier.testTag("settings-contact")) { Router.openUrl(AuthTermsText.SUPPORT_URL) }
            Link(L("diagnosticsTitle"), Icons.Filled.MedicalServices, tile, "settings-diagnostics") { open(SettingsRoute.DIAGNOSTICS) }
            SettingsRow(L("settingsSourceCode"), Icons.Filled.Code, fill = tile, modifier = Modifier.testTag("settings-source")) { Router.openUrl(SOURCE_URL) }
            SettingsRow(L("version"), Icons.Filled.Info, fill = tile, value = settingsVersionString, modifier = Modifier.testTag("settings-version"))
        }
        settingsSection("logout") {
            SettingsCenteredAction(L("logout"), AppColors.error, Modifier.testTag("settings-logout"), loading = isLoggingOut) { showLogout = true }
        }
        if (Session.canSign) {
            settingsSection("delete", footer = L("settingsDeleteAccountFooter")) {
                SettingsRow(L("deleteAccount"), tint = AppColors.error, modifier = Modifier.testTag("settings-delete-account")) { open(SettingsRoute.EVENT_MANAGER) }
            }
        }
    }

    if (showLogout) {
        AlertDialog(
            onDismissRequest = { showLogout = false },
            title = { Text(L("areYouSureLogout")) },
            text = { Text(L("seedPhraseWarning")) },
            confirmButton = {
                Box(Modifier.testTag("settings-logout-confirm")) {
                    TextAction(L("logout"), {
                        showLogout = false
                        isLoggingOut = true
                        App.scope.launch {
                            Session.logout()
                            isLoggingOut = false
                        }
                    }, color = AppColors.error)
                }
            },
            dismissButton = { TextAction(L("cancel"), { showLogout = false }) },
        )
    }
    if (showTerms) AuthTermsSheet(onAccept = null) { showTerms = false }
}

@Composable
private fun Link(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, fill: androidx.compose.ui.graphics.Color, tag: String, value: String? = null, onClick: () -> Unit) {
    SettingsRow(
        title = title,
        icon = icon,
        fill = fill,
        modifier = Modifier.testTag(tag),
        trailing = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (value != null) Text(value, color = AppColors.textSecondary, maxLines = 1)
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = AppColors.textTertiary)
            }
        },
        onClick = onClick,
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun AccountHeader(pubkey: String) {
    val profile = ProfileCache.profiles[pubkey]
    val haptics = rememberHaptics()
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().testTag("settings-account-header")
                .combinedClickable(onClick = { Router.push(Route.Profile(pubkey)) }, onLongClick = { menu = true })
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            ProfileAvatar(pubkey, size = 58.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(profile?.givenName ?: L("anonymous"), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                profile?.nip05?.ifEmpty { null }?.let {
                    Text(it, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Text(Profile.shortNpub(pubkey), style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace, color = AppColors.textSecondary, maxLines = 1)
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = AppColors.textTertiary)
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(
                text = { Text(L("settingsCopyNpub")) },
                leadingIcon = { Icon(Icons.Outlined.ContentCopy, null) },
                onClick = {
                    menu = false
                    SecureClipboard.copy(Session.npub ?: "", sensitive = false)
                    haptics.success()
                    ToastCenter.show(L("copiedNpub"), ToastStyle.SUCCESS)
                },
            )
            DropdownMenuItem(
                text = { Text(L("settingsShareProfile")) },
                leadingIcon = { Icon(Icons.Outlined.QrCode, null) },
                onClick = {
                    menu = false
                    Router.present(AppSheet.ShareProfile(pubkey))
                },
            )
        }
    }
}
