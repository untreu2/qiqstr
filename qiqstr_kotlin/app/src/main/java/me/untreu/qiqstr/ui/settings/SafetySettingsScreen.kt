package me.untreu.qiqstr.ui.settings

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import java.text.NumberFormat
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.AppLanguage
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.data.services.WebOfTrustService
import me.untreu.qiqstr.ui.auth.rememberHaptics

@Composable
fun SafetySettingsScreen() {
    val trust = WebOfTrustService
    val haptics = rememberHaptics()
    var filterNotifications by remember { mutableStateOf(Prefs.bool(WebOfTrustService.FILTER_NOTIFICATIONS_KEY, true)) }
    var filterReplies by remember { mutableStateOf(Prefs.bool(WebOfTrustService.FILTER_REPLIES_KEY, true)) }
    var showSensitive by remember { mutableStateOf(Prefs.bool(WebOfTrustService.SHOW_SENSITIVE_CONTENT_KEY)) }
    val networkValue = if (trust.trustedCount == 0) {
        if (trust.isBuilding) L("safetyBuilding") else L("safetyNotBuilt")
    } else {
        L("safetyPeopleCount", "count" to trust.trustedCount, "people" to NumberFormat.getIntegerInstance(AppLanguage.locale).format(trust.trustedCount))
    }

    SettingsScaffold(L("safetyTitle")) {
        settingsSection(
            "spam",
            L("safetySpamFilter"),
            footer = L("safetySpamFilterFooter", "count" to WebOfTrustService.MINIMUM_MUTUAL_FOLLOWS),
        ) {
            SettingsToggle(L("safetyFilterNotifications"), Icons.Outlined.NotificationsActive, filterNotifications, Modifier.testTag("safety-filter-notifications")) {
                haptics.selection()
                filterNotifications = it
                Prefs.set(WebOfTrustService.FILTER_NOTIFICATIONS_KEY, it)
            }
            SettingsToggle(L("safetyFilterReplies"), Icons.Outlined.Forum, filterReplies, Modifier.testTag("safety-filter-replies")) {
                haptics.selection()
                filterReplies = it
                Prefs.set(WebOfTrustService.FILTER_REPLIES_KEY, it)
            }
        }
        settingsSection("network", L("safetyTrustedNetwork"), footer = L("safetyNetworkFooter")) {
            SettingsRow(L("safetyTrustedNetwork"), Icons.Outlined.Groups, value = networkValue, modifier = Modifier.testTag("safety-network-size"))
            val updatedAt = trust.updatedAt
            if (trust.isBuilding) {
                LinearProgressIndicator(
                    progress = { trust.progress.toFloat() },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).testTag("safety-network-progress"),
                    color = AppColors.textPrimary,
                )
            } else if (updatedAt != null) {
                SettingsRow(L("safetyLastUpdated"), value = TimeFormat.relative(updatedAt / 1000))
            }
            SettingsRow(L("safetyRebuild"), tint = AppColors.link, enabled = !trust.isBuilding, modifier = Modifier.testTag("safety-rebuild")) {
                haptics.impact()
                trust.rebuild()
            }
        }
        if (AppStorePolicy.allowsSensitiveContentToggle) {
            settingsSection("content", L("safetyContent"), footer = L("safetySensitiveFooter")) {
                SettingsToggle(L("safetySensitiveContent"), Icons.Outlined.VisibilityOff, showSensitive, Modifier.testTag("safety-show-sensitive")) {
                    haptics.selection()
                    showSensitive = it
                    Prefs.set(WebOfTrustService.SHOW_SENSITIVE_CONTENT_KEY, it)
                }
            }
        }
    }
}
