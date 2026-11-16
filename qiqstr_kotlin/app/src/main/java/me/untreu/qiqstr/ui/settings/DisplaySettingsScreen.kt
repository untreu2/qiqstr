package me.untreu.qiqstr.ui.settings

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Contrast
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.DataSaverOn
import androidx.compose.material.icons.outlined.LightMode
import androidx.compose.material.icons.outlined.SmartDisplay
import androidx.compose.material.icons.outlined.Translate
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.app.SettingsRoute
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.AppLanguage
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.MediaPolicy
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.ThemePreference
import me.untreu.qiqstr.core.ThemeState
import me.untreu.qiqstr.core.VideoAutoplay
import me.untreu.qiqstr.ui.auth.localizedName
import me.untreu.qiqstr.ui.auth.rememberHaptics

val ThemePreference.title: String
    get() = when (this) {
        ThemePreference.SYSTEM -> L("settingsSystemDefault")
        ThemePreference.LIGHT -> L("lightMode")
        ThemePreference.DARK -> L("darkMode")
    }

val ThemePreference.icon: ImageVector
    get() = when (this) {
        ThemePreference.SYSTEM -> Icons.Outlined.Contrast
        ThemePreference.LIGHT -> Icons.Outlined.LightMode
        ThemePreference.DARK -> Icons.Outlined.DarkMode
    }

const val EXPANDED_NOTE_MODE_KEY = "expanded_note_mode"

@Composable
fun DisplaySettingsScreen() {
    val haptics = rememberHaptics()
    var expandedNotes by remember { mutableStateOf(Prefs.bool(EXPANDED_NOTE_MODE_KEY)) }
    var pickingAutoplay by remember { mutableStateOf(false) }
    SettingsScaffold(L("displayTitle")) {
        settingsSection("appearance", L("settingsAppearance"), footer = L("displaySubtitle")) {
            ThemePreference.entries.forEach { option ->
                ChoiceRow(
                    title = option.title,
                    icon = option.icon,
                    selected = ThemeState.preference == option,
                    tag = "display-theme-${option.raw}",
                ) {
                    if (ThemeState.preference != option) haptics.selection()
                    ThemeState.applyTheme(option)
                }
            }
        }
        settingsSection("expanded", footer = L("settingsExpandedNotesFooter")) {
            SettingsToggle(L("expandedNotes"), Icons.Outlined.UnfoldMore, expandedNotes, Modifier.testTag("display-expanded-notes")) {
                haptics.selection()
                expandedNotes = it
                Prefs.set(EXPANDED_NOTE_MODE_KEY, it)
            }
        }
        settingsSection("media", L("settingsMediaSection"), footer = L("settingsDataSaverFooter")) {
            SettingsRow(
                L("settingsAutoplay"),
                Icons.Outlined.SmartDisplay,
                modifier = Modifier.testTag("display-autoplay"),
                trailing = {
                    Box {
                        Text(MediaPolicy.autoplay.title, color = AppColors.textSecondary)
                        DropdownMenu(expanded = pickingAutoplay, onDismissRequest = { pickingAutoplay = false }) {
                            VideoAutoplay.entries.forEach { option ->
                                DropdownMenuItem(
                                    text = { Text(option.title) },
                                    trailingIcon = { if (MediaPolicy.autoplay == option) Icon(Icons.Filled.Check, null) },
                                    onClick = {
                                        pickingAutoplay = false
                                        if (MediaPolicy.autoplay != option) haptics.selection()
                                        MediaPolicy.updateAutoplay(option)
                                    },
                                    modifier = Modifier.testTag("display-autoplay-${option.raw}"),
                                )
                            }
                        }
                    }
                },
            ) { pickingAutoplay = true }
            SettingsToggle(L("settingsDataSaver"), Icons.Outlined.DataSaverOn, MediaPolicy.dataSaver, Modifier.testTag("display-data-saver")) {
                haptics.selection()
                MediaPolicy.updateDataSaver(it)
            }
        }
        settingsSection("language") {
            SettingsRow(
                L("language"),
                Icons.Outlined.Translate,
                modifier = Modifier.testTag("display-language"),
                trailing = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(AppLanguage.from(ThemeState.language)?.displayName ?: L("settingsSystemDefault"), color = AppColors.textSecondary)
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = AppColors.textTertiary)
                    }
                },
            ) { Router.push(Route.SettingsPage(SettingsRoute.LANGUAGE)) }
        }
    }
}

@Composable
private fun ChoiceRow(title: String, icon: ImageVector?, selected: Boolean, tag: String, subtitle: String? = null, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().selectable(selected, role = Role.RadioButton, onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp).testTag(tag),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            SettingsIcon(icon)
            Spacer(Modifier.width(16.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
        }
        RadioButton(selected = selected, onClick = null)
    }
}

@Composable
fun LanguageSettingsScreen() {
    val haptics = rememberHaptics()
    val current = ThemeState.language
    fun apply(code: String?) {
        if (code != current) haptics.selection()
        ThemeState.applyLanguage(code)
    }
    SettingsScaffold(L("language")) {
        settingsSection("languages") {
            ChoiceRow(L("settingsSystemDefault"), null, current == null, "language-system") { apply(null) }
            AppLanguage.entries.forEach { lang ->
                ChoiceRow(lang.displayName, null, current == lang.code, "language-${lang.code}", subtitle = lang.localizedName) { apply(lang.code) }
            }
        }
    }
}
