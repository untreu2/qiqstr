package me.untreu.qiqstr.ui.settings

import androidx.compose.runtime.Composable
import me.untreu.qiqstr.app.SettingsRoute
import me.untreu.qiqstr.ui.wallet.PaymentsSettingsScreen

@Composable
fun SettingsPageScreen(page: SettingsRoute) {
    when (page) {
        SettingsRoute.KEYS -> KeysSettingsScreen()
        SettingsRoute.RELAYS -> RelaySettingsScreen()
        SettingsRoute.MUTED -> MutedSettingsScreen()
        SettingsRoute.DISPLAY -> DisplaySettingsScreen()
        SettingsRoute.DATABASE -> DatabaseSettingsScreen()
        SettingsRoute.EVENT_MANAGER -> EventManagerSettingsScreen()
        SettingsRoute.PAYMENTS -> PaymentsSettingsScreen()
        SettingsRoute.LANGUAGE -> LanguageSettingsScreen()
        SettingsRoute.NOTIFICATIONS -> NotificationSettingsScreen()
        SettingsRoute.SAFETY -> SafetySettingsScreen()
        SettingsRoute.DIAGNOSTICS -> DiagnosticsScreen()
        SettingsRoute.MEDIA_SERVER -> MediaServerSettingsScreen()
        SettingsRoute.EMOJI_PACKS -> EmojiPacksSettingsScreen()
        SettingsRoute.NUTZAPS -> me.untreu.qiqstr.ui.wallet.CashuMintsSettingsScreen()
    }
}
