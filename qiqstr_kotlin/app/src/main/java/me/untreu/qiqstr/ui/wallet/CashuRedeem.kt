package me.untreu.qiqstr.ui.wallet

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.FlashOff
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle

class CashuRedeemModel(initialToken: String?) : ViewModel() {
    var token by mutableStateOf(initialToken ?: "")
    var showMeltConfirm by mutableStateOf(false)
    var decoded by mutableStateOf<CashuTokenInfo?>(null)
        private set
    var isInvalid by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set
    var redeemedAmount by mutableStateOf<Long?>(null)
        private set

    val wallet get() = WalletService

    init { decode() }

    val hasToken: Boolean get() = token.isNotBlank()
    val canRedeem: Boolean
        get() = wallet.isConnected && !wallet.isRedeemingCashu && (decoded != null || (!hasToken && wallet.cashuBalanceSats > 0))

    fun decode() {
        error = null
        if (!hasToken) {
            decoded = null
            isInvalid = false
            return
        }
        decoded = wallet.decodeCashu(token)
        isInvalid = decoded == null
    }

    fun paste() {
        WalletClipboard.text()?.let { token = it.trim() }
    }

    fun submit() {
        if (hasToken) viewModelScope.launch { redeem() } else showMeltConfirm = true
    }

    private suspend fun redeem() {
        val info = decoded ?: return
        error = null
        try {
            val sats = wallet.redeemCashu(info.token)
            finish(L("cashuRedeemSuccess", "amount" to Sats.format(sats)), sats)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            this.error = coreErrorMessage(error)
        }
    }

    fun meltAll() {
        viewModelScope.launch {
            error = null
            try {
                val sats = wallet.meltAllCashu()
                finish(L("cashuMeltAllSuccess", "amount" to Sats.format(sats)), sats)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                this@CashuRedeemModel.error = coreErrorMessage(error)
            }
        }
    }

    private fun finish(message: String, sats: Long) {
        token = ""
        decoded = null
        redeemedAmount = sats
        ToastCenter.show(message, ToastStyle.SUCCESS)
    }
}

@Composable
fun CashuRedeemForm(model: CashuRedeemModel, onFinished: (() -> Unit)?) {
    val haptics = LocalHapticFeedback.current
    var showScanner by remember { mutableStateOf(false) }
    val wallet = model.wallet

    LaunchedEffect(model) {
        snapshotFlow { model.token }.drop(1).collect { model.decode() }
    }
    LaunchedEffect(model.redeemedAmount) {
        if (model.redeemedAmount == null) return@LaunchedEffect
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        val finished = onFinished ?: return@LaunchedEffect
        delay(800)
        finished()
    }
    LaunchedEffect(model.error) { if (model.error != null) haptics.performHapticFeedback(HapticFeedbackType.LongPress) }
    LaunchedEffect(Unit) { wallet.refreshCashuBalance() }

    FormSection(
        footer = {
            if (model.decoded == null && model.isInvalid) NoticeLabel(L("cashuInvalidToken"), Icons.Outlined.ErrorOutline, AppColors.error)
            if (!wallet.isConnected) NoticeLabel(L("cashuNoWallet"), Icons.Outlined.FlashOff, AppColors.error)
            model.error?.let { Text(it, color = AppColors.error, modifier = Modifier.testTag("cashu-error")) }
            Text(L("walletCashuRedeemDescription"))
        },
    ) {
        FormTextField(model.token, { model.token = it }, L("cashuTokenHint"), Modifier.testTag("cashu-token"), minLines = 3, maxLines = 6, monospace = true)
        SectionDivider()
        ActionRow(L("walletPaste"), Icons.Outlined.ContentPaste, "cashu-paste") { model.paste() }
        SectionDivider()
        ActionRow(L("walletScan"), Icons.Outlined.QrCodeScanner, "cashu-scan") { showScanner = true }
        model.decoded?.let { decoded ->
            Column(Modifier.testTag("cashu-decoded")) {
                SectionDivider()
                LabeledRow(L("amount")) { SatsText(decoded.amountSats) }
                SectionDivider()
                LabeledRow(L("cashuMintUrl")) {
                    Text(
                        decoded.mintUrl,
                        style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                        color = AppColors.textSecondary,
                        textAlign = TextAlign.End,
                        maxLines = 2,
                    )
                }
            }
        }
        if (!model.hasToken && wallet.cashuBalanceSats > 0) {
            SectionDivider()
            NoticeLabel(
                L("walletCashuPending", "amount" to Sats.format(wallet.cashuBalanceSats)),
                Icons.Outlined.Payments,
                AppColors.textSecondary,
                Modifier.padding(16.dp),
            )
        }
        SectionDivider()
        val title = when {
            wallet.isRedeemingCashu -> L("cashuRedeeming")
            model.hasToken || wallet.cashuBalanceSats == 0L -> L("cashuRedeem")
            else -> L("cashuMeltAll")
        }
        ActionRow(
            title,
            Icons.Outlined.Download,
            "cashu-redeem",
            enabled = model.canRedeem,
            trailing = if (wallet.isRedeemingCashu) {
                { CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) }
            } else {
                null
            },
        ) { model.submit() }
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
    if (showScanner) {
        QRScannerDialog(onScan = { model.token = it }, onDismiss = { showScanner = false })
    }
}

@Composable
fun CashuRedeemSheet(initialToken: String?, onDismiss: () -> Unit) {
    ScopedViewModels {
        val model: CashuRedeemModel = viewModel { CashuRedeemModel(initialToken) }
        Column(Modifier.fillMaxWidth().imePadding()) {
            SheetTopBar(L("cashuToken"), onCancel = onDismiss, cancelEnabled = !model.wallet.isRedeemingCashu, cancelTag = "cashu-cancel")
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
                CashuRedeemForm(model, onDismiss)
            }
        }
    }
}
