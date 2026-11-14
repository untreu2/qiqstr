package me.untreu.qiqstr.app

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.services.ReadOnlyGate
import me.untreu.qiqstr.data.sync.NotificationBadge
import me.untreu.qiqstr.ui.auth.AddKeySheet
import me.untreu.qiqstr.ui.auth.SidebarSheet
import me.untreu.qiqstr.ui.auth.SwitchAccountSheet
import me.untreu.qiqstr.ui.compose.ComposeSheet
import me.untreu.qiqstr.ui.profile.ShareProfileSheet
import me.untreu.qiqstr.ui.wallet.ZapRetryToast
import me.untreu.qiqstr.ui.wallet.ZapSheet
import me.untreu.qiqstr.ui.wallet.ZapTarget

private data class TabItem(val tab: AppTab, val label: String, val icon: ImageVector, val selectedIcon: ImageVector, val tag: String)

@Composable
fun HomeScreen() {
    val tabs = listOf(
        TabItem(AppTab.FEED, L("home"), Icons.Outlined.Home, Icons.Filled.Home, "tab-feed"),
        TabItem(AppTab.DM, L("messages"), Icons.Outlined.ChatBubbleOutline, Icons.Filled.ChatBubble, "tab-dm"),
        TabItem(AppTab.WALLET, L("wallet"), Icons.Outlined.Bolt, Icons.Filled.Bolt, "tab-wallet"),
        TabItem(AppTab.NOTIFICATIONS, L("notifications"), Icons.Outlined.Notifications, Icons.Filled.Notifications, "tab-notifications"),
        TabItem(AppTab.SEARCH, L("search"), Icons.Outlined.Search, Icons.Filled.Search, "tab-search"),
    )
    val tabStates = rememberSaveableStateHolder()
    LaunchedEffect(Unit) { Router.openPendingLink() }
    Scaffold(
        containerColor = AppColors.background,
        contentWindowInsets = WindowInsets(0),
        bottomBar = {
            val top = Router.stack().lastOrNull()?.route
            if (top !is Route.DMChat && top !is Route.LiveStream) NavigationBar(containerColor = AppColors.background) {
                tabs.forEach { item ->
                    val selected = Router.selectedTab == item.tab
                    val badge = when (item.tab) {
                        AppTab.NOTIFICATIONS -> NotificationBadge.hasUnreadNotifications
                        AppTab.DM -> NotificationBadge.hasUnreadMessages
                        else -> false
                    }
                    NavigationBarItem(
                        selected = selected,
                        onClick = { Router.select(item.tab) },
                        icon = {
                            BadgedBox(badge = { if (badge) Badge(containerColor = AppColors.accent) }) {
                                Icon(if (selected) item.selectedIcon else item.icon, item.label)
                            }
                        },
                        alwaysShowLabel = false,
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = AppColors.textPrimary,
                            unselectedIconColor = AppColors.textSecondary,
                            indicatorColor = AppColors.tile,
                        ),
                        modifier = Modifier.testTag(item.tag),
                    )
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            val tab = Router.selectedTab
            tabStates.SaveableStateProvider(tab.name) { TabNavHost(tab) }
            ZapRetryToast()
        }
    }
    HomeOverlays()
}

@Composable
private fun HomeOverlays() {
    val composeContext = Router.composeContext
    if (Router.isComposing && composeContext != null) {
        val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(onDismissRequest = { Router.isComposing = false }, sheetState = state, containerColor = AppColors.background) {
            SheetToasts { ComposeSheet(composeContext) { Router.isComposing = false } }
        }
    }
    if (Router.showSidebar) {
        ModalBottomSheet(onDismissRequest = { Router.showSidebar = false }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = AppColors.background) {
            SheetToasts { SidebarSheet { Router.showSidebar = false } }
        }
    }
    Router.sheet?.let { sheet ->
        val dismiss = { Router.sheet = null }
        ModalBottomSheet(onDismissRequest = dismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = AppColors.background) {
            SheetToasts { when (sheet) {
                is AppSheet.Zap -> ZapSheet(ZapTarget.NoteTarget(sheet.note), dismiss)
                is AppSheet.ZapProfile -> ZapSheet(ZapTarget.ProfileTarget(sheet.pubkey), dismiss)
                AppSheet.SwitchAccount -> SwitchAccountSheet(dismiss)
                is AppSheet.ShareProfile -> ShareProfileSheet(sheet.pubkey, dismiss)
            } }
        }
    }
    if (ReadOnlyGate.isAlertPresented) {
        AlertDialog(
            onDismissRequest = { ReadOnlyGate.isAlertPresented = false },
            title = { Text(L("readOnlyTitle")) },
            text = { Text(L("readOnlyMessage")) },
            confirmButton = { TextAction(L("addKey"), { ReadOnlyGate.addKey() }) },
            dismissButton = { TextAction(L("cancel"), { ReadOnlyGate.isAlertPresented = false }) },
        )
    }
    if (ReadOnlyGate.isAddingKey) {
        ModalBottomSheet(onDismissRequest = { ReadOnlyGate.isAddingKey = false }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = AppColors.background) {
            SheetToasts { AddKeySheet { ReadOnlyGate.isAddingKey = false } }
        }
    }
}

/** Sheets draw in their own window above the root toast host, so they need their own. */
@Composable
private fun SheetToasts(content: @Composable () -> Unit) {
    Box {
        content()
        me.untreu.qiqstr.core.components.ToastHost(Modifier.align(androidx.compose.ui.Alignment.TopCenter))
    }
}
