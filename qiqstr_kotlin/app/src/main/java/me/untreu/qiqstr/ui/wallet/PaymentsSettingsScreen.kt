package me.untreu.qiqstr.ui.wallet

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material.icons.outlined.AttachMoney
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.app.AppTab
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.components.IconTile
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle

private val paymentPresets = listOf(21L, 100L, 500L, 1000L, 5000L)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaymentsSettingsScreen() {
    val haptics = LocalHapticFeedback.current
    val focus = LocalFocusManager.current
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    var amountText by rememberSaveable { mutableStateOf(ZapService.defaultAmount.toString()) }
    val showFiat = BitcoinPriceService.isEnabled
    val hasChanges = amountText.toLongOrNull() != ZapService.defaultAmount
    LaunchedEffect(showFiat) { if (showFiat) BitcoinPriceService.refreshIfNeeded() }

    fun save() {
        val amount = amountText.trim().toLongOrNull()
        if (amount == null || amount <= 0) {
            ToastCenter.show(L("pleaseEnterValidAmount"), ToastStyle.ERROR)
            return
        }
        ZapService.defaultAmount = amount
        focus.clearFocus()
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        ToastCenter.show(L("amountSavedSuccessfully"), ToastStyle.SUCCESS)
    }

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = AppColors.background,
        contentWindowInsets = androidx.compose.foundation.layout.WindowInsets(0),
        topBar = {
            LargeTopAppBar(
                title = { Text(L("paymentsTitle")) },
                navigationIcon = { IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } },
                actions = {
                    Row(Modifier.testTag("payments-amount-save")) { TextAction(L("save"), { save() }, enabled = hasChanges) }
                },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.largeTopAppBarColors(containerColor = AppColors.background, scrolledContainerColor = AppColors.background),
            )
        },
    ) { padding ->
        androidx.compose.foundation.layout.Column(
            Modifier.fillMaxSize().padding(padding).imePadding().verticalScroll(rememberScrollState()).padding(bottom = 24.dp),
        ) {
            FormSection(header = L("paymentsSubtitle"), footer = { androidx.compose.material3.Text(L("nwcDescription")) }) {
                ListItem(
                    headlineContent = { Text(L("wallet"), color = AppColors.textPrimary) },
                    supportingContent = { Text(L("settingsWalletManage"), color = AppColors.textSecondary) },
                    leadingContent = { IconTile(Icons.Outlined.AccountBalanceWallet) },
                    trailingContent = { Icon(Icons.AutoMirrored.Outlined.OpenInNew, null, Modifier.size(16.dp), tint = AppColors.textSecondary) },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    modifier = Modifier.clickable { openWallet() }.testTag("payments-open-wallet"),
                )
            }
            FormSection(footer = { Text(L("nutzapSettingsFooter")) }) {
                ListItem(headlineContent = { Text(L("nutzapTitle")) }, supportingContent = { Text(L(if (me.untreu.qiqstr.data.services.NutzapService.isReceiving) "feedOn" else "feedOff")) }, modifier = Modifier.clickable { Router.push(me.untreu.qiqstr.app.Route.SettingsPage(me.untreu.qiqstr.app.SettingsRoute.NUTZAPS)) }.testTag("payments-nutzaps"), colors = ListItemDefaults.colors(containerColor = Color.Transparent))
            }
            FormSection(footer = { Text(L("oneTapZapDescription")) }) {
                val oneTap = ZapService.isOneTapEnabled
                ListItem(
                    headlineContent = { Text(L("oneTapZap")) },
                    leadingContent = { IconTile(Icons.Filled.Bolt, tint = if (oneTap) AppColors.zap else AppColors.textPrimary) },
                    trailingContent = {
                        Switch(
                            checked = oneTap,
                            onCheckedChange = {
                                ZapService.isOneTapEnabled = it
                                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            },
                            colors = SwitchDefaults.colors(checkedTrackColor = AppColors.switchActive),
                            modifier = Modifier.testTag("payments-one-tap-zap"),
                        )
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
            }
            val amount = amountText.toLongOrNull()
            val fiat = if (showFiat && amount != null && amount > 0) BitcoinPriceService.formatted(amount) else null
            FormSection(
                header = L("defaultZapAmount"),
                footer = fiat?.let { value -> { Text(L("walletFiatEstimate", "amount" to value)) } },
            ) {
                ListItem(
                    headlineContent = { Text(L("amountSats"), maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    leadingContent = { IconTile(Icons.Outlined.Bolt, tint = AppColors.zap) },
                    trailingContent = {
                        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            SatsAmountField(amountText, { amountText = it }, Modifier.testTag("payments-amount-field"), placeholder = L("amountSats"))
                            Text("sats", color = AppColors.textSecondary)
                        }
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 16.dp)) {
                    paymentPresets.forEachIndexed { index, preset ->
                        SegmentedButton(
                            selected = amountText.toLongOrNull() == preset,
                            onClick = { amountText = preset.toString() },
                            shape = SegmentedButtonDefaults.itemShape(index, paymentPresets.size),
                            icon = {},
                            modifier = Modifier.testTag("payments-preset-$preset"),
                        ) {
                            Text(Sats.format(preset), maxLines = 1)
                        }
                    }
                }
            }
            FormSection(footer = { Text(L("walletShowFiatDescription")) }) {
                ListItem(
                    headlineContent = { Text(L("walletShowFiat")) },
                    leadingContent = { IconTile(Icons.Outlined.AttachMoney) },
                    trailingContent = {
                        Switch(
                            checked = showFiat,
                            onCheckedChange = {
                                BitcoinPriceService.isEnabled = it
                                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            },
                            colors = SwitchDefaults.colors(checkedTrackColor = AppColors.switchActive),
                            modifier = Modifier.testTag("payments-show-fiat"),
                        )
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
            }
        }
    }
}

private fun openWallet() {
    Router.popToRoot(AppTab.WALLET)
    Router.selectedTab = AppTab.WALLET
}
