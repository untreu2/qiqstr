package me.untreu.qiqstr.ui.wallet

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.FlashOff
import androidx.compose.material.icons.outlined.QrCode2
import androidx.compose.material.icons.outlined.Restore
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.TimerOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.BackTopBar
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle

class ReceiveViewModel : ViewModel() {
    enum class Mode { INVOICE, TOKEN }

    var mode by mutableStateOf(Mode.INVOICE)
    var amountText by mutableStateOf("")
    var descriptionText by mutableStateOf("")
    var invoice by mutableStateOf<CreatedInvoice?>(null)
        private set
    var isCreating by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set
    var isPaid by mutableStateOf(false)
        private set
    var isExpired by mutableStateOf(false)
        private set
    var copiedTick by mutableIntStateOf(0)
        private set

    val wallet get() = WalletService

    val amount: Long? get() = amountText.filter(Char::isDigit).toLongOrNull()?.takeIf { it > 0 }

    val canCreate: Boolean get() = amount != null && !isCreating && wallet.isConnected

    val qrContent: String?
        get() {
            invoice?.let { return "lightning:${it.invoice}" }
            val address = wallet.lightningAddress
            if (address != null && amountText.isEmpty()) return "lightning:$address"
            return null
        }

    fun create() {
        val amount = amount ?: return
        viewModelScope.launch {
            isCreating = true
            error = null
            try {
                invoice = wallet.makeInvoice(amount, descriptionText)
                isPaid = false
                isExpired = false
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                this@ReceiveViewModel.error = L("failedToCreateInvoice", "message" to coreErrorMessage(error))
            } finally {
                isCreating = false
            }
        }
    }

    fun reset() {
        invoice = null
        isPaid = false
        isExpired = false
        error = null
    }

    fun copy(text: String) {
        copiedTick += 1
        WalletClipboard.copy(text)
    }

    suspend fun watch() {
        val watched = invoice ?: return
        while (currentCoroutineActive() && !isPaid) {
            delay(4000)
            if (invoice != watched) return
            val expiry = watched.expiresAt
            if (expiry != null && expiry < TimeFormat.now) {
                isExpired = true
                return
            }
            if (wallet.isInvoicePaid(watched) && invoice == watched) {
                isPaid = true
                ToastCenter.show(L("paymentReceived"), ToastStyle.SUCCESS)
            }
        }
    }

    private suspend fun currentCoroutineActive(): Boolean = kotlin.coroutines.coroutineContext.isActive
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReceiveScreen() {
    val model: ReceiveViewModel = viewModel()
    val cashuModel: CashuRedeemModel = viewModel(key = "receive-cashu") { CashuRedeemModel(null) }
    val haptics = LocalHapticFeedback.current
    val dismiss = { Router.pop(); Unit }

    LaunchedEffect(model.invoice) { model.watch() }
    LaunchedEffect(model.copiedTick) { if (model.copiedTick > 0) haptics.performHapticFeedback(HapticFeedbackType.LongPress) }
    LaunchedEffect(model.isPaid) {
        if (!model.isPaid) return@LaunchedEffect
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        delay(1600)
        dismiss()
    }

    Scaffold(
        modifier = Modifier.testTag("receive-view"),
        containerColor = AppColors.background,
        contentWindowInsets = androidx.compose.foundation.layout.WindowInsets(0),
        topBar = {
            BackTopBar(
                L("receive"),
                actions = {
                    if (model.invoice != null && !model.isPaid) {
                        IconButton(onClick = { model.reset() }, modifier = Modifier.testTag("receive-new-invoice")) {
                            Icon(Icons.Outlined.Restore, L("walletNewInvoice"))
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 24.dp),
        ) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).testTag("receive-mode")) {
                ReceiveViewModel.Mode.entries.forEachIndexed { index, mode ->
                    SegmentedButton(
                        selected = model.mode == mode,
                        onClick = { model.mode = mode },
                        shape = SegmentedButtonDefaults.itemShape(index, ReceiveViewModel.Mode.entries.size),
                    ) {
                        Text(if (mode == ReceiveViewModel.Mode.INVOICE) L("invoice") else L("token"))
                    }
                }
            }
            when {
                !model.wallet.isConnected -> EmptyStateView(icon = Icons.Outlined.FlashOff, title = L("pleaseConnectWalletFirst"))
                model.mode == ReceiveViewModel.Mode.INVOICE -> InvoiceContent(model, dismiss)
                else -> CashuRedeemForm(cashuModel, dismiss)
            }
        }
    }
}

@Composable
private fun InvoiceContent(model: ReceiveViewModel, dismiss: () -> Unit) {
    val invoice = model.invoice
    when {
        model.isPaid && invoice != null -> PaymentSuccessView(L("paymentReceived"), invoice.amountSats, null, Modifier.heightIn(min = 420.dp), onDone = dismiss)
        invoice != null -> InvoiceSections(model, invoice)
        else -> {
            QrPlaceholder(model)
            InvoiceForm(model)
        }
    }
}

@Composable
private fun QrPlaceholder(model: ReceiveViewModel) {
    val content = model.qrContent ?: return
    val address = model.wallet.lightningAddress ?: return
    Column(
        Modifier.fillMaxWidth().padding(vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        QRCodeView(content, 200.dp, Modifier.clip(RoundedCornerShape(28.dp)).clickable { model.copy(address) })
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Icon(Icons.Filled.Bolt, null, Modifier.size(16.dp), tint = AppColors.textSecondary)
            Text(address, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, modifier = Modifier.testTag("receive-lightning-address"))
        }
    }
}

@Composable
private fun InvoiceForm(model: ReceiveViewModel) {
    val focus = LocalFocusManager.current
    FormSection(
        footer = {
            val error = model.error
            if (error != null) {
                Text(error, color = AppColors.error, modifier = Modifier.testTag("receive-error"))
            } else if (model.qrContent == null && model.amount == null) {
                Text(L("enterAmountToGenerateInvoice"))
            }
        },
    ) {
        LabeledRow(L("amountInSats")) {
            SatsAmountField(model.amountText, { model.amountText = it }, Modifier.testTag("receive-amount"))
        }
        SectionDivider()
        FormTextField(model.descriptionText, { model.descriptionText = it }, L("listDescriptionHint"), Modifier.testTag("receive-description"), maxLines = 4)
        SectionDivider()
        ActionRow(
            L("walletCreateInvoice"),
            Icons.Outlined.QrCode2,
            "receive-create",
            enabled = model.canCreate,
            trailing = if (model.isCreating) {
                { CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) }
            } else {
                null
            },
        ) {
            focus.clearFocus()
            model.create()
        }
    }
}

@Composable
private fun InvoiceSections(model: ReceiveViewModel, invoice: CreatedInvoice) {
    val context = LocalContext.current
    Column(
        Modifier.fillMaxWidth().padding(vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        QRCodeView(
            "lightning:${invoice.invoice}",
            220.dp,
            Modifier.clip(RoundedCornerShape(28.dp)).clickable(enabled = !model.isExpired) { model.copy(invoice.invoice) }.alpha(if (model.isExpired) 0.25f else 1f),
        )
        Text(
            "${Sats.format(invoice.amountSats)} ${L("walletSats")}",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.testTag("receive-invoice-amount"),
        )
        invoice.description?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 32.dp))
        }
    }
    FormSection(
        footer = if (!model.isExpired) {
            {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("receive-waiting")) {
                    CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp, color = AppColors.textSecondary)
                    Text(L("walletWaitingForPayment"))
                }
            }
        } else {
            null
        },
    ) {
        if (model.isExpired) {
            NoticeLabel(L("walletInvoiceExpired"), Icons.Outlined.TimerOff, AppColors.error, Modifier.padding(16.dp))
            SectionDivider()
            ActionRow(L("walletNewInvoice"), Icons.Outlined.Restore, "receive-new-invoice-inline") { model.reset() }
        } else {
            invoice.expiresAt?.let { expiry ->
                LabeledRow(L("walletExpiresIn")) { Countdown(expiry) }
                SectionDivider()
            }
            ActionRow(
                L("copy"),
                Icons.Outlined.ContentCopy,
                "receive-copy",
                trailing = {
                    Text(
                        WalletFormat.truncated(invoice.invoice, 10, 8),
                        style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                        color = AppColors.textSecondary,
                        maxLines = 1,
                    )
                },
            ) { model.copy(invoice.invoice) }
            SectionDivider()
            ActionRow(L("share"), Icons.Outlined.Share, "receive-share") { WalletClipboard.share(context, invoice.invoice) }
        }
    }
}
