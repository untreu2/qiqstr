package me.untreu.qiqstr.ui.wallet

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Cancel
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.coreErrorMessage

sealed interface SendPhase {
    object Editing : SendPhase
    object Paying : SendPhase
    data class Sent(val amount: Long, val fee: Long) : SendPhase
    data class Redeemed(val amount: Long) : SendPhase
}

class SendViewModel(initialInput: String?) : ViewModel() {
    var input by mutableStateOf(initialInput ?: "")
    var amountText by mutableStateOf("")
    var comment by mutableStateOf("")
    var showConfirm by mutableStateOf(false)
    var request by mutableStateOf<PaymentRequest?>(null)
        private set
    var lnurlParams by mutableStateOf<LnurlPayParams?>(null)
        private set
    var isResolving by mutableStateOf(false)
        private set
    var parseError by mutableStateOf<String?>(null)
        private set
    var payError by mutableStateOf<String?>(null)
        private set
    var phase by mutableStateOf<SendPhase>(SendPhase.Editing)
        private set
    var failureTick by mutableIntStateOf(0)
        private set
    var paymentMayHaveSettled by mutableStateOf(false)
        private set
    private var settledInput: String? = null

    val wallet get() = WalletService

    val trimmedInput: String get() = input.trim()

    val amountSats: Long?
        get() {
            val current = request
            if (current is PaymentRequest.Bolt11) current.invoice.amountSats?.let { return it }
            if (current is PaymentRequest.Cashu) return current.info.amountSats
            return amountText.filter(Char::isDigit).toLongOrNull()?.takeIf { it > 0 }
        }

    val needsAmountField: Boolean
        get() = when (request) {
            is PaymentRequest.LightningAddress, is PaymentRequest.LnurlRequest -> lnurlParams?.isFixedAmount != true
            else -> false
        }

    val allowsComment: Boolean get() = (lnurlParams?.commentAllowed ?: 0) > 0

    val destination: String
        get() = when (val current = request) {
            is PaymentRequest.Bolt11 -> WalletFormat.truncated(current.raw)
            is PaymentRequest.LightningAddress -> current.address
            is PaymentRequest.LnurlRequest -> current.url.host
            is PaymentRequest.Cashu -> current.info.mintUrl
            null -> ""
        }

    val typeLabel: String
        get() = when (request) {
            is PaymentRequest.Bolt11 -> L("walletTypeInvoice")
            is PaymentRequest.LightningAddress -> L("lightningAddress")
            is PaymentRequest.LnurlRequest -> L("walletTypeLnurl")
            is PaymentRequest.Cashu -> L("cashuToken")
            null -> ""
        }

    val memo: String?
        get() = when (val current = request) {
            is PaymentRequest.Bolt11 -> current.invoice.description
            is PaymentRequest.LightningAddress, is PaymentRequest.LnurlRequest -> lnurlParams?.description
            else -> null
        }

    val validationMessage: String?
        get() {
            val current = request
            if (current is PaymentRequest.Bolt11) {
                if (current.invoice.amountMsat == null) return L("walletAmountlessInvoice")
                if (current.invoice.isExpired) return L("walletInvoiceExpired")
                if (!current.invoice.isMainnet) return L("walletWrongNetwork")
            }
            val params = lnurlParams
            val sats = amountSats
            if (needsAmountField && params != null && sats != null && (sats < params.minSats || sats > params.maxSats)) {
                return WalletError.AmountOutOfRange(params.minSats, params.maxSats).message
            }
            return null
        }

    val canSubmit: Boolean
        get() {
            val current = request ?: return false
            if (phase != SendPhase.Editing || isResolving || paymentMayHaveSettled || validationMessage != null) return false
            if (current is PaymentRequest.Cashu) return !wallet.isRedeemingCashu
            if (current is PaymentRequest.LightningAddress && lnurlParams == null) return false
            if (current is PaymentRequest.LnurlRequest && lnurlParams == null) return false
            return amountSats != null
        }

    fun paste() {
        WalletClipboard.text()?.let { input = it.trim() }
    }

    suspend fun parse() {
        val text = trimmedInput
        if (paymentMayHaveSettled) {
            if (text == settledInput) return
            paymentMayHaveSettled = false
            settledInput = null
        }
        payError = null
        if (text.isEmpty()) {
            request = null
            lnurlParams = null
            parseError = null
            isResolving = false
            return
        }
        val parsed = wallet.resolve(text)
        if (parsed == null) {
            request = null
            lnurlParams = null
            parseError = if (CashuTokenInfo.looksLikeToken(text)) L("cashuInvalidToken") else L("unrecognizedPaymentFormat")
            return
        }
        val needsParams = parsed is PaymentRequest.LightningAddress || parsed is PaymentRequest.LnurlRequest
        if (parsed == request && (!needsParams || lnurlParams != null)) return
        parseError = null
        request = parsed
        lnurlParams = null
        when (parsed) {
            is PaymentRequest.LightningAddress -> resolveParams { Lnurl.payParams(parsed.address) }
            is PaymentRequest.LnurlRequest -> resolveParams { Lnurl.payParams(parsed.url) }
            else -> Unit
        }
    }

    private suspend fun resolveParams(fetch: suspend () -> LnurlPayParams) {
        isResolving = true
        try {
            val params = fetch()
            lnurlParams = params
            if (params.isFixedAmount) amountText = params.minSats.toString()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            parseError = coreErrorMessage(error)
        } finally {
            isResolving = false
        }
    }

    fun submit() {
        if (!canSubmit) return
        if (request is PaymentRequest.Cashu) viewModelScope.launch { redeem() } else showConfirm = true
    }

    fun pay() {
        val current = request ?: return
        val amount = amountSats ?: return
        viewModelScope.launch {
            phase = SendPhase.Paying
            payError = null
            try {
                val result = when (current) {
                    is PaymentRequest.Bolt11 -> wallet.payBolt11(current.raw)
                    is PaymentRequest.LightningAddress, is PaymentRequest.LnurlRequest -> {
                        val params = lnurlParams ?: throw WalletError.ResolveFailed()
                        wallet.pay(params, amount, comment)
                    }
                    is PaymentRequest.Cashu -> return@launch
                }
                phase = SendPhase.Sent(amount, result.feesSats)
            } catch (error: CancellationException) {
                throw error
            } catch (error: WalletError.PaymentPending) {
                phase = SendPhase.Editing
                paymentMayHaveSettled = true
                settledInput = trimmedInput
                payError = L("walletPaymentPending")
                failureTick += 1
            } catch (error: Exception) {
                phase = SendPhase.Editing
                payError = "${L("paymentFailed")}: ${coreErrorMessage(error)}"
                failureTick += 1
            }
        }
    }

    private suspend fun redeem() {
        val current = request as? PaymentRequest.Cashu ?: return
        phase = SendPhase.Paying
        payError = null
        try {
            phase = SendPhase.Redeemed(wallet.redeemCashu(current.info.token))
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            phase = SendPhase.Editing
            payError = coreErrorMessage(error)
            failureTick += 1
        }
    }
}

@Composable
fun SendSheet(initialInput: String?, onDismiss: () -> Unit) {
    ScopedViewModels {
        val model: SendViewModel = viewModel { SendViewModel(initialInput) }
        SendContent(model, onDismiss)
    }
}

@Composable
private fun SendContent(model: SendViewModel, onDismiss: () -> Unit) {
    val haptics = LocalHapticFeedback.current
    val focus = LocalFocusManager.current
    var showScanner by remember { mutableStateOf(false) }
    val trimmed = model.trimmedInput
    LaunchedEffect(trimmed) {
        delay(350)
        model.parse()
    }
    LaunchedEffect(model.failureTick) { if (model.failureTick > 0) haptics.performHapticFeedback(HapticFeedbackType.LongPress) }
    LaunchedEffect(model.phase) {
        if (model.phase is SendPhase.Sent || model.phase is SendPhase.Redeemed) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
    }

    Column(Modifier.fillMaxWidth().imePadding()) {
        SheetTopBar(
            L("send"),
            onCancel = onDismiss,
            cancelEnabled = model.phase != SendPhase.Paying,
            cancelTag = "send-cancel",
        ) {
            if (model.phase == SendPhase.Editing || model.phase == SendPhase.Paying) {
                if (model.phase == SendPhase.Paying || model.wallet.isRedeemingCashu) {
                    CircularProgressIndicator(Modifier.padding(end = 16.dp).size(24.dp), strokeWidth = 2.dp)
                } else {
                    Button(
                        onClick = { focus.clearFocus(); model.submit() },
                        enabled = model.canSubmit,
                        shape = CircleShape,
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
                        modifier = Modifier.padding(end = 8.dp).testTag("send-submit"),
                    ) {
                        Text(if (model.request is PaymentRequest.Cashu) L("cashuRedeem") else L("send"))
                    }
                }
            }
        }
        when (val phase = model.phase) {
            is SendPhase.Sent -> PaymentSuccessView(L("paymentSent"), phase.amount, phase.fee, onDone = onDismiss)
            is SendPhase.Redeemed -> PaymentSuccessView(L("cashuRedeemSuccess", "amount" to Sats.format(phase.amount)), phase.amount, null, onDone = onDismiss)
            else -> SendForm(model) { showScanner = true }
        }
    }

    if (model.showConfirm) {
        val amount = Sats.format(model.amountSats ?: 0)
        AlertDialog(
            onDismissRequest = { model.showConfirm = false },
            title = { Text(L("walletConfirmPayment")) },
            text = { Text(L("walletConfirmPaymentMessage", "amount" to amount, "destination" to model.destination)) },
            confirmButton = {
                TextButton(onClick = { model.showConfirm = false; model.pay() }, modifier = Modifier.testTag("send-confirm")) {
                    Text(L("walletPayAmount", "amount" to amount))
                }
            },
            dismissButton = { TextButton(onClick = { model.showConfirm = false }) { Text(L("cancel")) } },
        )
    }
    if (showScanner) {
        QRScannerDialog(onScan = { model.input = it }, onDismiss = { showScanner = false })
    }
}

@Composable
private fun SendForm(model: SendViewModel, onScan: () -> Unit) {
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        FormSection(
            footer = when {
                model.isResolving -> {
                    { NoticeLabel(L("resolvingAddress"), Icons.Outlined.MoreHoriz, AppColors.textSecondary) }
                }
                model.parseError != null -> {
                    { NoticeLabel(model.parseError ?: "", Icons.Outlined.ErrorOutline, AppColors.error) }
                }
                else -> null
            },
        ) {
            FormTextField(model.input, { model.input = it }, L("walletSendPlaceholder"), Modifier.testTag("send-input"), minLines = 2, maxLines = 5, monospace = true)
            SectionDivider()
            ActionRow(L("walletPaste"), Icons.Outlined.ContentPaste, "send-paste") { model.paste() }
            SectionDivider()
            ActionRow(L("walletScan"), Icons.Outlined.QrCodeScanner, "send-scan", onClick = onScan)
        }
        if (model.request != null) Details(model)
        model.payError?.let { error ->
            FormSection {
                NoticeLabel(error, Icons.Outlined.Cancel, AppColors.error, Modifier.padding(16.dp).testTag("send-error"))
            }
        }
    }
}

@Composable
private fun Details(model: SendViewModel) {
    val request = model.request
    FormSection(
        footer = model.validationMessage?.let { warning -> { NoticeLabel(warning, Icons.Outlined.WarningAmber, AppColors.warning) } },
    ) {
        LabeledRow(model.typeLabel) {
            SelectionContainer {
                Text(model.destination, style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace), maxLines = 2, color = AppColors.textSecondary)
            }
        }
        val amount = model.amountSats
        if (!model.needsAmountField && amount != null) {
            SectionDivider()
            LabeledRow(L("amount")) { SatsText(amount, Modifier.testTag("send-amount-fixed")) }
        }
        model.memo?.takeIf { it.isNotEmpty() }?.let { memo ->
            SectionDivider()
            LabeledValue(L("description"), memo)
        }
        if (request is PaymentRequest.Bolt11 && request.invoice.amountMsat != null && !request.invoice.isExpired) {
            SectionDivider()
            LabeledRow(L("walletExpiresIn")) { Countdown(request.invoice.expiresAt) }
        }
    }
    if (model.needsAmountField || model.allowsComment) {
        val params = model.lnurlParams
        FormSection(
            footer = if (model.needsAmountField && params != null) {
                { Text(L("walletAmountRange", "min" to Sats.format(params.minSats), "max" to Sats.format(params.maxSats))) }
            } else {
                null
            },
        ) {
            if (model.needsAmountField) {
                LabeledRow(L("amountInSats")) {
                    SatsAmountField(model.amountText, { model.amountText = it }, Modifier.testTag("send-amount"))
                }
            }
            if (model.allowsComment) {
                if (model.needsAmountField) SectionDivider()
                FormTextField(model.comment, { model.comment = it }, L("commentOptional"), Modifier.testTag("send-comment"), maxLines = 4)
            }
        }
    }
}

@Composable
fun ActionRow(title: String, icon: ImageVector, tag: String, enabled: Boolean = true, trailing: (@Composable () -> Unit)? = null, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title, color = if (enabled) AppColors.textPrimary else AppColors.textTertiary) },
        leadingContent = { Icon(icon, null, tint = if (enabled) AppColors.textPrimary else AppColors.textTertiary) },
        trailingContent = trailing,
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.clickable(enabled = enabled, onClick = onClick).testTag(tag),
    )
}
