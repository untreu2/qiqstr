package me.untreu.qiqstr.ui.auth

import androidx.compose.runtime.snapshotFlow
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.AppTab
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.data.sync.FeatureHooks
import me.untreu.qiqstr.data.sync.NotificationBadge
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SessionPhase
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.ui.settings.DiagnosticsStore
import me.untreu.qiqstr.ui.settings.LocalNotificationService

object AuthFeature : FeatureHooks {
    override fun register() {
        DiagnosticsStore.activate()
        LocalNotificationService.activate()
        SyncService.notificationHandler = LocalNotificationService
        Router.externalHandlers.add(LocalNotificationService::handle)
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStop(owner: LifecycleOwner) = LocalNotificationService.enteredBackground()

            override fun onStart(owner: LifecycleOwner) {
                LocalNotificationService.refreshStatus()
                if (Session.phase == SessionPhase.Ready && Router.selectedTab == AppTab.NOTIFICATIONS) {
                    NotificationBadge.markRead()
                    LocalNotificationService.clearBadge()
                }
            }
        })
        App.scope.launch {
            snapshotFlow { Session.phase }.filter { it == SessionPhase.Ready }.collect { LocalNotificationService.sessionReady() }
        }
        App.scope.launch {
            snapshotFlow { NotificationBadge.hasUnreadNotifications }.drop(1).filter { !it }.collect { LocalNotificationService.clearBadge() }
        }
        App.scope.launch {
            snapshotFlow { NotificationBadge.hasUnreadMessages }.drop(1).filter { !it }.collect { LocalNotificationService.clearMessages() }
        }
    }
}
