package me.untreu.qiqstr.ui.wallet

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.CallMade
import androidx.compose.material.icons.automirrored.outlined.CallReceived
import androidx.compose.material.icons.automirrored.outlined.Notes
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.LinkOff
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.AppFont
import me.untreu.qiqstr.core.AppLanguage
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.PrimaryButton
import me.untreu.qiqstr.core.components.SecondaryButton
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle

sealed interface WalletSheet {
    data class Connect(val uri: String?) : WalletSheet
    data class Send(val input: String?) : WalletSheet
    data class Cashu(val token: String?) : WalletSheet
    object CashuSend : WalletSheet
    data class Payment(val transaction: WalletTransaction) : WalletSheet
}

class WalletViewModel : ViewModel() {
    var sheet by mutableStateOf<WalletSheet?>(null)
    var showScanner by mutableStateOf(false)
    var showDisconnectConfirm by mutableStateOf(false)
    var showMeltConfirm by mutableStateOf(false)
    var showAllTransactions by mutableStateOf(false)
    var refreshTick by mutableIntStateOf(0)
        private set
    var isRefreshing by mutableStateOf(false)
        private set
    private var pendingScan: String? = null

    val wallet get() = WalletService

    val visibleTransactions: List<WalletTransaction>
        get() = if (showAllTransactions) wallet.transactions else wallet.transactions.take(COLLAPSED_TRANSACTION_COUNT)

    val hasHiddenTransactions: Boolean get() = wallet.transactions.size > COLLAPSED_TRANSACTION_COUNT

    val transactionDays: List<TransactionDay> get() = TransactionDay.group(visibleTransactions)

    fun consumeIncoming() {
        if (sheet != null) return
        if (wallet.incomingConnectURI != null) {
            sheet = WalletSheet.Connect(wallet.consumeIncomingConnectURI())
        } else if (wallet.incomingPaymentRequest != null) {
            if (!wallet.isConnected) {
                wallet.consumeIncomingPaymentRequest()
                ToastCenter.show(L("pleaseConnectWalletFirst"), ToastStyle.ERROR)
                return
            }
            sheet = WalletSheet.Send(wallet.consumeIncomingPaymentRequest())
        }
    }

    fun receive() = Router.push(Route.WalletReceive)

    fun scanned(code: String) { pendingScan = code }

    fun scannerDismissed() {
        showScanner = false
        val code = pendingScan ?: return
        pendingScan = null
        when {
            WalletService.isWalletConnectURI(code) -> sheet = WalletSheet.Connect(code)
            !wallet.isConnected -> ToastCenter.show(L("pleaseConnectWalletFirst"), ToastStyle.ERROR)
            CashuTokenInfo.looksLikeToken(code) -> sheet = WalletSheet.Cashu(code)
            else -> sheet = WalletSheet.Send(code)
        }
    }

    fun refresh() {
        viewModelScope.launch {
            isRefreshing = true
            try {
                wallet.refresh()
            } finally {
                isRefreshing = false
            }
            refreshTick += 1
        }
    }

    fun disconnect() {
        wallet.disconnect()
        showAllTransactions = false
        ToastCenter.show(L("nwcDisconnected"))
    }

    fun meltAll() {
        viewModelScope.launch {
            try {
                val sats = wallet.meltAllCashu()
                ToastCenter.show(L("cashuMeltAllSuccess", "amount" to Sats.format(sats)), ToastStyle.SUCCESS)
            } catch (error: Exception) {
                if (error is kotlinx.coroutines.CancellationException) throw error
                ToastCenter.error(error)
            }
        }
    }

    companion object {
        const val COLLAPSED_TRANSACTION_COUNT = 8
    }
}

data class TransactionDay(val id: String, val date: Long, val transactions: List<WalletTransaction>) {
    val title: String
        get() {
            val today = WalletFormat.startOfDay(System.currentTimeMillis())
            val locale = AppLanguage.locale
            return when {
                date == today -> L("today")
                date == WalletFormat.startOfDay(today - 12 * 3600_000L) -> L("yesterday")
                sameYear(date) -> SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(locale, "EEEEdMMMM"), locale).format(Date(date))
                else -> java.text.DateFormat.getDateInstance(java.text.DateFormat.LONG, locale).format(Date(date))
            }
        }

    val net: Long get() = transactions.sumOf { if (it.isIncoming) it.amountSats else -it.amountSats }

    val netText: String
        get() {
            val value = net
            if (value == 0L) return "0"
            return WalletFormat.signed(value, value > 0)
        }

    companion object {
        private fun sameYear(millis: Long): Boolean {
            val year = Calendar.getInstance().apply { timeInMillis = millis }.get(Calendar.YEAR)
            return year == Calendar.getInstance().get(Calendar.YEAR)
        }

        fun group(transactions: List<WalletTransaction>): List<TransactionDay> {
            val order = mutableListOf<Long>()
            val buckets = HashMap<Long, MutableList<WalletTransaction>>()
            for (tx in transactions) {
                val day = WalletFormat.startOfDay(tx.createdAt * 1000)
                if (buckets[day] == null) order.add(day)
                buckets.getOrPut(day) { mutableListOf() }.add(tx)
            }
            return order.map { day -> TransactionDay((day / 1000).toString(), day, buckets[day] ?: emptyList()) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WalletScreen() {
    val model: WalletViewModel = viewModel()
    val wallet = WalletService
    val haptics = LocalHapticFeedback.current
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    LaunchedEffect(Unit) { model.consumeIncoming() }
    LaunchedEffect(wallet.incomingConnectURI, wallet.incomingPaymentRequest, model.sheet == null) {
        if (wallet.incomingConnectURI != null || wallet.incomingPaymentRequest != null) model.consumeIncoming()
    }
    LaunchedEffect(Unit) { BitcoinPriceService.refreshIfNeeded() }
    LaunchedEffect(wallet.lastPaymentAt) { if (wallet.lastPaymentAt != null) haptics.performHapticFeedback(HapticFeedbackType.LongPress) }

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = AppColors.background,
        contentWindowInsets = androidx.compose.foundation.layout.WindowInsets(0),
        topBar = {
            LargeTopAppBar(
                title = { Text(L("wallet")) },
                actions = { if (wallet.isConnected) WalletMenu(model) },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.largeTopAppBarColors(containerColor = AppColors.background, scrolledContainerColor = AppColors.background),
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            if (wallet.isConnected) WalletDashboard(model) else WalletOnboarding(model)
        }
    }

    var cashuCreating by remember { mutableStateOf(false) }
    model.sheet?.let { sheet ->
        val skipPartial = sheet is WalletSheet.Connect || sheet == WalletSheet.CashuSend
        val state = rememberModalBottomSheetState(
            skipPartiallyExpanded = skipPartial,
            confirmValueChange = { !(it == androidx.compose.material3.SheetValue.Hidden && (wallet.isPaying || wallet.isRedeemingCashu || cashuCreating)) },
        )
        val dismiss = { if (!cashuCreating) model.sheet = null }
        ModalBottomSheet(onDismissRequest = dismiss, sheetState = state, containerColor = AppColors.background) {
            when (sheet) {
                is WalletSheet.Connect -> ConnectWalletSheet(sheet.uri, dismiss)
                is WalletSheet.Send -> SendSheet(sheet.input, dismiss)
                is WalletSheet.Cashu -> CashuRedeemSheet(sheet.token, dismiss)
                WalletSheet.CashuSend -> ScopedViewModels { CashuSendSheet(dismiss) { cashuCreating = it } }
                is WalletSheet.Payment -> PaymentDetailSheet(sheet.transaction, dismiss)
            }
        }
    }
    if (model.showScanner) {
        QRScannerDialog(onScan = { model.scanned(it) }, onDismiss = { model.scannerDismissed() })
    }
    if (model.showDisconnectConfirm) {
        AlertDialog(
            onDismissRequest = { model.showDisconnectConfirm = false },
            title = { Text(L("walletDisconnectTitle")) },
            text = { Text(L("walletDisconnectMessage")) },
            confirmButton = {
                TextButton(onClick = { model.showDisconnectConfirm = false; model.disconnect() }, modifier = Modifier.testTag("wallet-disconnect-confirm")) {
                    Text(L("walletDisconnect"), color = AppColors.error)
                }
            },
            dismissButton = { TextButton(onClick = { model.showDisconnectConfirm = false }) { Text(L("cancel")) } },
        )
    }
    if (model.showMeltConfirm) {
        AlertDialog(
            onDismissRequest = { model.showMeltConfirm = false },
            title = { Text(L("cashuMeltAll")) },
            text = { Text(L("walletMeltAllConfirm", "amount" to Sats.format(wallet.cashuBalanceSats))) },
            confirmButton = { TextButton(onClick = { model.showMeltConfirm = false; model.meltAll() }) { Text(L("cashuMeltAll")) } },
            dismissButton = { TextButton(onClick = { model.showMeltConfirm = false }) { Text(L("cancel")) } },
        )
    }
}

@Composable
private fun WalletMenu(model: WalletViewModel) {
    var expanded by remember { mutableStateOf(false) }
    val wallet = WalletService
    Box {
        IconButton(onClick = { expanded = true }, modifier = Modifier.testTag("wallet-menu")) {
            Icon(Icons.Outlined.MoreVert, L("walletMore"))
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text(L("cashuSendTitle")) }, onClick = { expanded = false; model.sheet = WalletSheet.CashuSend }, modifier = Modifier.testTag("wallet-menu-cashu-send"))
            DropdownMenuItem(
                text = { Text(L("walletReceiveCashu")) },
                leadingIcon = { Icon(Icons.Outlined.Payments, null) },
                onClick = { expanded = false; model.sheet = WalletSheet.Cashu(null) },
                modifier = Modifier.testTag("wallet-menu-cashu"),
            )
            if (wallet.cashuBalanceSats > 0) {
                DropdownMenuItem(
                    text = { Text(L("cashuMeltAll")) },
                    leadingIcon = { Icon(Icons.Outlined.Bolt, null) },
                    enabled = !wallet.isRedeemingCashu,
                    onClick = { expanded = false; model.showMeltConfirm = true },
                )
            }
            DropdownMenuItem(
                text = { Text(L("refresh")) },
                leadingIcon = { Icon(Icons.Outlined.Refresh, null) },
                onClick = { expanded = false; model.refresh() },
                modifier = Modifier.testTag("wallet-menu-refresh"),
            )
            HorizontalDivider()
            DropdownMenuItem(
                text = { Text(L("walletDisconnect"), color = AppColors.error) },
                leadingIcon = { Icon(Icons.Outlined.LinkOff, null, tint = AppColors.error) },
                onClick = { expanded = false; model.showDisconnectConfirm = true },
                modifier = Modifier.testTag("wallet-menu-disconnect"),
            )
        }
    }
}

@Composable
private fun WalletOnboarding(model: WalletViewModel) {
    LazyColumn(Modifier.fillMaxSize().testTag("wallet-onboarding"), contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            Column(
                Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(Icons.Filled.Bolt, null, Modifier.size(56.dp), tint = AppColors.zap)
                Text(L("nwcTitle"), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
                Text(L("walletNwcIntro"), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, textAlign = TextAlign.Center)
            }
        }
        item {
            FormSection {
                Feature(Icons.Outlined.Bolt, L("onboardingCoinosFeatureSend"))
                Feature(Icons.AutoMirrored.Outlined.CallReceived, L("walletFeatureReceive"))
                Feature(Icons.Outlined.FavoriteBorder, L("onboardingCoinosFeatureZap"))
                Feature(Icons.Outlined.Payments, L("walletFeatureCashu"))
            }
        }
        item {
            FormSection(header = L("walletNwcHowToTitle")) {
                Text(
                    L("walletNwcHowTo"),
                    Modifier.padding(16.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
            }
        }
        item {
            FormSection(plain = true, footer = { Text(L("nwcDisclaimer")) }) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    PrimaryButton(L("walletConnectWallet"), { model.sheet = WalletSheet.Connect(null) }, Modifier.fillMaxWidth().testTag("wallet-connect"))
                    SecondaryButton(L("scanQRCode"), { model.showScanner = true }, Modifier.fillMaxWidth().testTag("wallet-connect-scan"), icon = Icons.Outlined.QrCodeScanner)
                }
            }
        }
    }
}

@Composable
private fun Feature(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    ListItem(
        headlineContent = { Text(text) },
        leadingContent = { Icon(icon, null, tint = AppColors.textSecondary) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WalletDashboard(model: WalletViewModel) {
    val wallet = WalletService
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(Unit) {
        while (isActive) {
            delay(30_000)
            wallet.refreshBalance()
        }
    }
    LaunchedEffect(model.refreshTick) { if (model.refreshTick > 0) haptics.performHapticFeedback(HapticFeedbackType.LongPress) }
    PullToRefreshBox(isRefreshing = model.isRefreshing, onRefresh = { model.refresh() }, modifier = Modifier.fillMaxSize().testTag("wallet-dashboard")) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
            item {
                Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    WalletBalanceCard()
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        WalletAction(L("receive"), Icons.AutoMirrored.Outlined.CallReceived, "wallet-receive", Modifier.weight(1f)) { model.receive() }
                        WalletAction(L("send"), Icons.AutoMirrored.Outlined.CallMade, "wallet-send", Modifier.weight(1f)) { model.sheet = WalletSheet.Send(null) }
                        WalletAction(L("walletScan"), Icons.Outlined.QrCodeScanner, "wallet-scan", Modifier.weight(1f)) { model.showScanner = true }
                    }
                }
                Spacer(Modifier.size(8.dp))
            }
            if (wallet.cashuBalanceSats > 0) {
                item {
                    FormSection {
                        ListItem(
                            headlineContent = { Text(L("cashu")) },
                            supportingContent = { Text("${Sats.format(wallet.cashuBalanceSats)} ${L("walletSats")}") },
                            leadingContent = { Icon(Icons.Outlined.Payments, null) },
                            trailingContent = {
                                OutlinedButton(
                                    onClick = { model.showMeltConfirm = true },
                                    enabled = !wallet.isRedeemingCashu,
                                    shape = CircleShape,
                                    modifier = Modifier.testTag("wallet-cashu-melt"),
                                ) { Text(L("walletMelt")) }
                            },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        )
                    }
                }
            }
            transactions(model)
        }
    }
}

@Composable
private fun WalletAction(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, tag: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    FilledTonalButton(
        onClick = onClick,
        modifier = modifier.heightIn(min = 64.dp).testTag(tag),
        shape = RoundedCornerShape(22.dp),
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 10.dp),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(icon, null)
            Text(title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
    }
}

private fun LazyListScope.transactions(model: WalletViewModel) {
    val wallet = WalletService
    when {
        !wallet.hasLoadedTransactions -> item {
            FormSection(header = L("recentTransactions"), modifier = Modifier.testTag("wallet-transactions")) {
                repeat(4) { index ->
                    if (index > 0) SectionDivider()
                    TransactionRow(WalletTransaction.placeholder(index), placeholder = true) {}
                }
            }
        }
        wallet.transactions.isEmpty() -> item {
            Box(Modifier.testTag("wallet-transactions")) { EmptyTransactions(model) }
        }
        else -> {
            val days = model.transactionDays
            days.forEachIndexed { index, day ->
                item(key = "day-${day.id}") {
                    FormSection(
                        modifier = Modifier.testTag(if (index == 0) "wallet-transactions" else "wallet-transactions-${day.id}"),
                        footer = if (index == days.lastIndex && (model.hasHiddenTransactions || (model.showAllTransactions && wallet.canLoadMoreTransactions))) {
                            { TransactionFooterButtons(model) }
                        } else {
                            null
                        },
                    ) {
                        DayHeader(day, isFirst = index == 0)
                        day.transactions.forEachIndexed { txIndex, tx ->
                            if (txIndex > 0) SectionDivider()
                            TransactionRow(tx, showsTimeOnly = true) { model.sheet = WalletSheet.Payment(tx) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DayHeader(day: TransactionDay, isFirst: Boolean) {
    Row(
        Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(day.title, style = MaterialTheme.typography.labelLarge, color = AppColors.textSecondary, modifier = Modifier.weight(1f))
        if (isFirst && WalletService.isLoadingTransactions) CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp, color = AppColors.textSecondary)
        Text(
            day.netText,
            style = MaterialTheme.typography.labelLarge,
            color = AppColors.textSecondary,
            modifier = Modifier.semantics { contentDescription = L("walletDayNet", "amount" to day.netText) },
        )
    }
}

@Composable
private fun TransactionFooterButtons(model: WalletViewModel) {
    val wallet = WalletService
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (model.hasHiddenTransactions) {
            TextButton(onClick = { model.showAllTransactions = !model.showAllTransactions }, modifier = Modifier.testTag("wallet-transactions-toggle")) {
                Text(if (model.showAllTransactions) L("showLess") else L("showAllTransactions", "count" to wallet.transactions.size))
            }
        }
        if (model.showAllTransactions && wallet.canLoadMoreTransactions) {
            val scope = rememberCoroutineScope()
            TextButton(
                onClick = { scope.launch { wallet.loadMoreTransactions() } },
                enabled = !wallet.isLoadingTransactions,
                modifier = Modifier.testTag("wallet-transactions-more"),
            ) {
                Text(L("walletLoadMore"))
                if (wallet.isLoadingTransactions) {
                    Spacer(Modifier.size(8.dp))
                    CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
                }
            }
        }
    }
}

@Composable
private fun EmptyTransactions(model: WalletViewModel) {
    val wallet = WalletService
    val scope = rememberCoroutineScope()
    val error = wallet.transactionsError
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
        EmptyStateView(
            icon = if (error == null) Icons.Outlined.Bolt else Icons.Outlined.WarningAmber,
            title = if (error == null) L("noTransactionsYet") else L("walletTransactionsUnavailable"),
            message = error ?: L("walletEmptyTransactionsMessage"),
        )
        if (error != null) {
            OutlinedButton(onClick = { scope.launch { wallet.loadTransactions() } }, shape = CircleShape, modifier = Modifier.testTag("wallet-transactions-retry")) {
                Text(L("retry"))
            }
        } else {
            FilledTonalButton(onClick = { model.receive() }, shape = CircleShape, modifier = Modifier.testTag("wallet-empty-receive")) {
                Icon(Icons.AutoMirrored.Outlined.CallReceived, null, Modifier.size(18.dp))
                Spacer(Modifier.size(8.dp))
                Text(L("receive"))
            }
        }
    }
}

@Composable
fun WalletBalanceCard() {
    val wallet = WalletService
    val prices = BitcoinPriceService
    val haptics = LocalHapticFeedback.current
    val showFiat = prices.isEnabled
    LaunchedEffect(showFiat) { if (showFiat) prices.refreshIfNeeded() }
    val isUnavailable = wallet.balanceSats == null && wallet.balanceError != null
    val balanceText = when {
        wallet.balanceHidden -> "••••••"
        isUnavailable -> "—"
        else -> Sats.format(wallet.balanceSats ?: 0)
    }
    val fiatText = if (showFiat && !wallet.balanceHidden) wallet.balanceSats?.let { sats -> prices.formatted(sats)?.let { L("walletFiatEstimate", "amount" to it) } } else null
    val description = when {
        wallet.balanceHidden -> L("walletBalanceHidden")
        isUnavailable -> L("balanceUnavailable")
        else -> "$balanceText ${L("walletSats")}" + (fiatText?.let { ", $it" } ?: "")
    }
    val loading = wallet.balanceSats == null && !wallet.balanceHidden && !isUnavailable
    Column(
        Modifier
            .fillMaxWidth()
            .clickable(onClickLabel = if (wallet.balanceHidden) L("walletTapToShow") else L("walletTapToHide")) {
                wallet.balanceHidden = !wallet.balanceHidden
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            }
            .padding(vertical = 16.dp)
            .semantics(mergeDescendants = true) { contentDescription = description }
            .testTag("wallet-balance"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(if (wallet.balanceHidden) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility, null, Modifier.size(16.dp), tint = AppColors.textSecondary)
            Text(L("walletBalance"), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            AnimatedContent(targetState = balanceText, label = "balance") { text ->
                Text(
                    text,
                    style = AppFont.brandSemibold(56.sp),
                    maxLines = 1,
                    modifier = Modifier.alpha(if (loading) 0.3f else 1f),
                )
            }
            Text(
                L("walletSats"),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.textSecondary,
                modifier = Modifier.padding(bottom = 10.dp),
            )
        }
        if (fiatText != null) {
            Text(fiatText, style = MaterialTheme.typography.titleMedium, color = AppColors.textSecondary, modifier = Modifier.testTag("wallet-balance-fiat"))
        }
        val name = wallet.lightningAddress ?: wallet.walletName
        if (wallet.balanceError != null) {
            NoticeLabel(L("balanceUnavailable"), Icons.Outlined.WarningAmber, AppColors.error)
        } else if (name != null) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(if (wallet.lightningAddress == null) Icons.Outlined.Link else Icons.Outlined.Bolt, null, Modifier.size(14.dp), tint = AppColors.textSecondary)
                Text(name, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun TransactionRow(transaction: WalletTransaction, showsTimeOnly: Boolean = false, placeholder: Boolean = false, onTap: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val title = transaction.description?.ifEmpty { null } ?: if (transaction.isIncoming) L("received") else L("sent")
    val subtitle = if (showsTimeOnly && transaction.createdAt > 0) WalletFormat.time(transaction.createdAt) else WalletFormat.timestamp(transaction.createdAt)
    Box {
        ListItem(
            headlineContent = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
            supportingContent = { Text(subtitle, color = AppColors.textSecondary) },
            leadingContent = { TransactionIcon(transaction.isIncoming) },
            trailingContent = {
                Text(
                    "${WalletFormat.signed(transaction.amountSats, transaction.isIncoming)} ${L("walletSats")}",
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = if (transaction.isIncoming) AppColors.success else AppColors.textPrimary,
                )
            },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            modifier = Modifier
                .alpha(if (placeholder) 0.35f else 1f)
                .combinedClickable(enabled = !placeholder, onClick = onTap, onLongClick = { menu = true })
                .testTag("wallet-transaction"),
        )
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            transaction.invoice?.let { invoice ->
                DropdownMenuItem(
                    text = { Text(L("walletCopyInvoice")) },
                    leadingIcon = { Icon(Icons.Outlined.ContentCopy, null) },
                    onClick = { menu = false; WalletClipboard.copy(invoice) },
                )
            }
            transaction.description?.let { description ->
                DropdownMenuItem(
                    text = { Text(L("walletCopyDescription")) },
                    leadingIcon = { Icon(Icons.AutoMirrored.Outlined.Notes, null) },
                    onClick = { menu = false; WalletClipboard.copy(description) },
                )
            }
            DropdownMenuItem(
                text = { Text(L("details")) },
                leadingIcon = { Icon(Icons.Outlined.Info, null) },
                onClick = { menu = false; onTap() },
            )
        }
    }
}
