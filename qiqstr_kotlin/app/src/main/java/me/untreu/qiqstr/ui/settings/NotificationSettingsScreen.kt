package me.untreu.qiqstr.ui.settings

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.Repeat
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.delay
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.components.PrimaryButton
import me.untreu.qiqstr.core.components.SecondaryButton
import me.untreu.qiqstr.data.services.WebOfTrustService
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SessionPhase
import me.untreu.qiqstr.ui.auth.rememberHaptics

@Composable
fun rememberNotificationEnabler(onDone: (Boolean) -> Unit = {}): () -> Unit {
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        onDone(LocalNotificationService.completeEnable(granted))
    }
    return {
        if (LocalNotificationService.needsPermissionRequest) {
            Prefs.set(LocalNotificationService.PROMPTED_KEY, true)
            launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            onDone(LocalNotificationService.completeEnable(true))
        }
    }
}

object SystemSettings {
    fun openNotifications() {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, App.context.packageName)
        open(intent)
    }

    fun openAppDetails() {
        open(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", App.context.packageName, null)))
    }

    private fun open(intent: Intent) {
        runCatching { App.context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
            .onFailure { openAppDetailsFallback() }
    }

    private fun openAppDetailsFallback() {
        runCatching {
            App.context.startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", App.context.packageName, null)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }
}

@Composable
private fun RefreshOnResume() {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_RESUME) LocalNotificationService.refreshStatus() }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
}

@Composable
fun NotificationSettingsScreen() {
    val service = LocalNotificationService
    val haptics = rememberHaptics()
    var isRequesting by remember { mutableStateOf(false) }
    val enable = rememberNotificationEnabler { isRequesting = false }
    val types = remember { LocalNotificationType.entries.associateWith { mutableStateOf(it.isEnabled) } }
    var onlyKnown by remember { mutableStateOf(WebOfTrustService.filtersNotifications) }
    RefreshOnResume()

    SettingsScaffold(L("notifications")) {
        settingsSection("master", footer = if (service.isDenied) L("localNotifyDeniedFooterAndroid") else L("localNotifyAllowFooter")) {
            SettingsToggle(L("localNotifyAllow"), Icons.Outlined.NotificationsActive, service.isDelivering, Modifier.testTag("notify-master"), enabled = !isRequesting) { isOn ->
                haptics.selection()
                when {
                    !isOn -> service.updateEnabled(false)
                    service.isDenied && !service.needsPermissionRequest -> SystemSettings.openNotifications()
                    else -> {
                        isRequesting = true
                        enable()
                    }
                }
            }
            if (service.isDenied) {
                SettingsRow(L("walletOpenSettings"), tint = AppColors.link, modifier = Modifier.testTag("notify-open-settings")) { SystemSettings.openNotifications() }
            }
        }
        settingsSection("types", L("localNotifyTypesHeader")) {
            TypeToggle(types, LocalNotificationType.REPLIES, L("notificationFilterReplies"), Icons.Outlined.Forum, service.isEnabled)
            TypeToggle(types, LocalNotificationType.REACTIONS, L("reactions"), Icons.Outlined.FavoriteBorder, service.isEnabled)
            TypeToggle(types, LocalNotificationType.REPOSTS, L("reposts"), Icons.Outlined.Repeat, service.isEnabled)
            TypeToggle(types, LocalNotificationType.ZAPS, L("zaps"), Icons.Outlined.Bolt, service.isEnabled)
            TypeToggle(types, LocalNotificationType.MESSAGES, L("messages"), Icons.Outlined.ChatBubbleOutline, service.isEnabled)
        }
        settingsSection("known", footer = L("localNotifyOnlyKnownFooter")) {
            SettingsToggle(L("notificationsOnlyKnown"), Icons.Outlined.People, onlyKnown, Modifier.testTag("notify-only-known")) {
                haptics.selection()
                onlyKnown = it
                Prefs.set(WebOfTrustService.FILTER_NOTIFICATIONS_KEY, it)
            }
        }
        settingsSection("background", footer = L("localNotifyDeliveryFooterAndroid")) {
            SettingsRow(
                L("localNotifyBackgroundActivity"),
                Icons.Outlined.Sync,
                value = if (service.backgroundRefreshAvailable) L("localNotifyOn") else L("localNotifyOff"),
                modifier = Modifier.testTag("notify-background-refresh"),
            )
            if (!service.backgroundRefreshAvailable) {
                SettingsRow(L("walletOpenSettings"), tint = AppColors.link) { SystemSettings.openAppDetails() }
            }
        }
    }
}

@Composable
private fun TypeToggle(
    states: Map<LocalNotificationType, androidx.compose.runtime.MutableState<Boolean>>,
    type: LocalNotificationType,
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    enabled: Boolean,
) {
    val haptics = rememberHaptics()
    val state = states.getValue(type)
    SettingsToggle(title, icon, state.value, Modifier.testTag("notify-type-${type.raw}"), enabled = enabled) {
        haptics.selection()
        state.value = it
        Prefs.set(type.key, it)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotificationPrompt() {
    var isPresented by remember { mutableStateOf(false) }
    var isForeground by remember { mutableStateOf(true) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> isForeground = true
                Lifecycle.Event.ON_PAUSE -> isForeground = false
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    val canOffer = LocalNotificationService.shouldOfferPrompt && Session.phase == SessionPhase.Ready && !Session.isNewAccount &&
        isForeground && Router.sheet == null && !Router.isComposing && !Router.showSidebar
    LaunchedEffect(canOffer) {
        if (!canOffer) return@LaunchedEffect
        delay(8_000)
        isPresented = true
    }
    if (!isPresented) return
    var isRequesting by remember { mutableStateOf(false) }
    val close = {
        LocalNotificationService.dismissPrompt()
        isPresented = false
    }
    val enable = rememberNotificationEnabler {
        isRequesting = false
        close()
    }
    ModalBottomSheet(
        onDismissRequest = { if (!isRequesting) close() },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = AppColors.background,
        modifier = Modifier.testTag("notify-prompt"),
    ) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding().padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Icon(Icons.Outlined.NotificationsActive, null, Modifier.size(44.dp), tint = AppColors.textPrimary)
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(L("localNotifyPromptTitle"), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
                Text(L("localNotifyPromptMessage"), style = MaterialTheme.typography.bodyLarge, color = AppColors.textSecondary, textAlign = TextAlign.Center)
            }
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                PrimaryButton(L("localNotifyPromptAllow"), {
                    isRequesting = true
                    enable()
                }, Modifier.fillMaxWidth().testTag("notify-prompt-allow"), loading = isRequesting)
                SecondaryButton(L("localNotifyPromptLater"), close, Modifier.fillMaxWidth().testTag("notify-prompt-later"), enabled = !isRequesting)
            }
        }
    }
}
