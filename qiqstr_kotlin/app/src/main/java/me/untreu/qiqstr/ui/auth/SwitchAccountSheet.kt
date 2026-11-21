package me.untreu.qiqstr.ui.auth

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateListOf
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
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.accounts.Account
import me.untreu.qiqstr.data.services.ReadOnlyGate
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SwitchAccountSheet(onDismiss: () -> Unit) {
    var addingAccount by remember { mutableStateOf(false) }
    val path = remember { mutableStateListOf<AuthStep>() }
    BackHandler(enabled = addingAccount) { if (path.isNotEmpty()) path.removeAt(path.lastIndex) else addingAccount = false }
    if (addingAccount) {
        Box(Modifier.fillMaxWidth().fillMaxHeight(0.95f)) {
            AuthNavHost(path, onBack = { addingAccount = false }) {
                AuthWelcomeContent(
                    isAddAccount = true,
                    onBack = { addingAccount = false },
                    onLogin = { path.add(AuthStep.LOGIN) },
                    onSignup = { path.add(AuthStep.SIGNUP) },
                )
            }
        }
    } else {
        AccountList(onDismiss) {
            path.clear()
            addingAccount = true
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AccountList(onDismiss: () -> Unit, onAddAccount: () -> Unit) {
    val haptics = rememberHaptics()
    var switchingTo by remember { mutableStateOf<String?>(null) }
    var removing by remember { mutableStateOf<Account?>(null) }
    var confirmLogout by remember { mutableStateOf(false) }
    var isLoggingOut by remember { mutableStateOf(false) }
    val accounts = Session.accounts
    LaunchedEffect(accounts.map { it.npub }) { ProfileCache.load(accounts.map { it.pubkeyHex }.filter { it.isNotEmpty() }) }

    fun switchTo(account: Account) {
        if (account.npub == Session.npub) {
            onDismiss()
            return
        }
        switchingTo = account.npub
        App.scope.launch {
            try {
                Session.switchAccount(account.npub)
                haptics.success()
            } catch (error: Throwable) {
                ToastCenter.error(error)
            }
            switchingTo = null
        }
    }

    Column(Modifier.fillMaxWidth().navigationBarsPadding().testTag("switch-account-sheet")) {
        TopAppBar(
            title = { Text(L("switchAccount")) },
            navigationIcon = { IconButton(onClick = onDismiss, modifier = Modifier.testTag("switch-close")) { Icon(Icons.Filled.Close, L("close")) } },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background),
        )
        Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 16.dp)) {
            Text(L("authAccounts"), style = MaterialTheme.typography.labelLarge, color = AppColors.textSecondary, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
            accounts.forEach { account ->
                key(account.npub) {
                    AccountRow(
                        account = account,
                        switching = switchingTo == account.npub,
                        enabled = switchingTo == null,
                        onClick = { switchTo(account) },
                        onRemove = { removing = account },
                    )
                }
            }
            if (Session.isReadOnly) {
                HorizontalDivider(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), color = AppColors.divider)
                ListItem(
                    headlineContent = { Text(L("readOnlyAddKey")) },
                    supportingContent = { Text(L("readOnlyMessage")) },
                    leadingContent = { Icon(Icons.Outlined.Key, null) },
                    colors = ListItemDefaults.colors(containerColor = AppColors.background),
                    modifier = Modifier.testTag("switch-add-key").clickableRow { ReadOnlyGate.addKey() },
                )
            }
            HorizontalDivider(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), color = AppColors.divider)
            ListItem(
                headlineContent = { Text(L("addAccount")) },
                leadingContent = { Icon(Icons.Outlined.AddCircleOutline, null) },
                colors = ListItemDefaults.colors(containerColor = AppColors.background),
                modifier = Modifier.testTag("switch-add-account").clickableRow(onClick = onAddAccount),
            )
            ListItem(
                headlineContent = { Text(L("logout"), color = AppColors.error) },
                leadingContent = { Icon(Icons.AutoMirrored.Outlined.Logout, null, tint = AppColors.error) },
                trailingContent = if (isLoggingOut) ({ CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) }) else null,
                colors = ListItemDefaults.colors(containerColor = AppColors.background),
                modifier = Modifier.testTag("switch-logout").clickableRow(enabled = !isLoggingOut) { confirmLogout = true },
            )
        }
    }

    if (confirmLogout) {
        AlertDialog(
            onDismissRequest = { confirmLogout = false },
            title = { Text(L("areYouSureLogout")) },
            text = { Text(L("seedPhraseWarning")) },
            confirmButton = {
                Box(Modifier.testTag("switch-logout-confirm")) {
                    TextAction(L("logout"), {
                        confirmLogout = false
                        isLoggingOut = true
                        App.scope.launch {
                            Session.logout()
                            isLoggingOut = false
                        }
                    }, color = AppColors.error)
                }
            },
            dismissButton = { TextAction(L("cancel"), { confirmLogout = false }) },
        )
    }
    removing?.let { account ->
        AlertDialog(
            onDismissRequest = { removing = null },
            title = { Text(L("authRemoveAccountTitle")) },
            text = { Text(L("seedPhraseWarning")) },
            confirmButton = {
                Box(Modifier.testTag("switch-remove-confirm")) {
                    TextAction(L("authRemoveAccount"), {
                        removing = null
                        App.scope.launch { Session.removeAccount(account.npub) }
                    }, color = AppColors.error)
                }
            },
            dismissButton = { TextAction(L("cancel"), { removing = null }) },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun AccountRow(account: Account, switching: Boolean, enabled: Boolean, onClick: () -> Unit, onRemove: () -> Unit) {
    val pubkey = account.pubkeyHex
    val isActive = account.npub == Session.npub
    val profile = ProfileCache.profiles[pubkey]
    var menu by remember { mutableStateOf(false) }
    val dismissState = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) onRemove()
        false
    })
    SwipeToDismissBox(
        state = dismissState,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(Modifier.fillMaxSize().background(AppColors.error).padding(horizontal = 20.dp), contentAlignment = Alignment.CenterEnd) {
                Icon(Icons.Outlined.Delete, L("authRemoveAccount"), tint = MaterialTheme.colorScheme.onError)
            }
        },
        modifier = Modifier.testTag("switch-remove-${account.npub.takeLast(6)}"),
    ) {
        Box {
            ListItem(
                headlineContent = {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(profile?.givenName ?: L("anonymous"), fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (account.isReadOnly) {
                            Icon(
                                Icons.Outlined.Visibility,
                                L("readOnlyBadge"),
                                Modifier.size(16.dp).testTag("switch-read-only-${account.npub.takeLast(6)}"),
                                tint = AppColors.textSecondary,
                            )
                        }
                    }
                },
                supportingContent = { Text(shortNpub(account.npub), fontFamily = FontFamily.Monospace, maxLines = 1) },
                leadingContent = { ProfileAvatar(pubkey, size = 40.dp) },
                trailingContent = when {
                    switching -> ({ CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) })
                    isActive -> ({ Icon(Icons.Filled.Check, L("authActive"), tint = AppColors.textPrimary) })
                    else -> null
                },
                colors = ListItemDefaults.colors(containerColor = AppColors.background),
                modifier = Modifier.testTag("switch-account-${account.npub.takeLast(6)}").combinedClickable(
                    enabled = enabled,
                    onClick = onClick,
                    onLongClick = { menu = true },
                ),
            )
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                if (account.isReadOnly && isActive) {
                    DropdownMenuItem(
                        text = { Text(L("readOnlyAddKey")) },
                        leadingIcon = { Icon(Icons.Outlined.Key, null) },
                        onClick = { menu = false; ReadOnlyGate.addKey() },
                    )
                }
                DropdownMenuItem(
                    text = { Text(L("publicKeyNpub")) },
                    leadingIcon = { Icon(Icons.Outlined.ContentCopy, null) },
                    onClick = {
                        menu = false
                        SecureClipboard.copy(account.npub, sensitive = false)
                        ToastCenter.show(L("copiedNpub"), ToastStyle.SUCCESS)
                    },
                )
                DropdownMenuItem(
                    text = { Text(L("authRemoveAccount"), color = AppColors.error) },
                    leadingIcon = { Icon(Icons.Outlined.Delete, null, tint = AppColors.error) },
                    onClick = { menu = false; onRemove() },
                )
            }
        }
    }
}

private fun shortNpub(npub: String) = if (npub.length > 16) "${npub.take(10)}…${npub.takeLast(6)}" else npub

@OptIn(ExperimentalFoundationApi::class)
fun Modifier.clickableRow(enabled: Boolean = true, onClick: () -> Unit) = combinedClickable(enabled = enabled, onClick = onClick)
