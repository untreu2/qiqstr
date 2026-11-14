package me.untreu.qiqstr.ui.wallet

import android.content.ClipboardManager
import android.content.Context
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle

class ConnectWalletModel(initialUri: String?) : ViewModel() {
    var uri by mutableStateOf(initialUri ?: "")
    var accepted by mutableStateOf(
        initialUri == null && !WalletService.isConnected && Prefs.bool(WalletService.DISCLAIMER_ACCEPTED_KEY),
    )
    var isConnecting by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set
    var connectedTick by mutableIntStateOf(0)
        private set
    var clipboardHasContent by mutableStateOf(false)
        private set
    private var consumedClip = false

    val highlightsPaste: Boolean get() = clipboardHasContent && !isValid

    fun refreshClipboard() {
        clipboardHasContent = !consumedClip && WalletClipboard.hasContent
    }

    fun clipboardChanged() {
        consumedClip = false
        refreshClipboard()
    }

    fun paste() {
        consumedClip = true
        refreshClipboard()
        val text = WalletClipboard.text()?.trim()
        if (text.isNullOrEmpty()) return
        uri = text
        error = null
    }

    fun receive(incoming: String?) {
        if (incoming == null) return
        uri = incoming
        error = null
    }

    val trimmed: String get() = uri.trim()
    val isValid: Boolean get() = trimmed.isNotEmpty() && WalletService.validate(trimmed)
    val showsInvalid: Boolean get() = trimmed.isNotEmpty() && !isValid
    val canConnect: Boolean get() = isValid && accepted && !isConnecting

    fun connect(onConnected: () -> Unit) {
        if (trimmed.isEmpty()) {
            error = L("nwcPleaseEnterConnectionString")
            return
        }
        if (!isValid) {
            error = L("nwcInvalidConnectionString")
            return
        }
        viewModelScope.launch {
            isConnecting = true
            try {
                WalletService.connect(trimmed)
                connectedTick += 1
                ToastCenter.show(L("nwcConnectionSaved"), ToastStyle.SUCCESS)
                onConnected()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                this@ConnectWalletModel.error = coreErrorMessage(error)
            } finally {
                isConnecting = false
            }
        }
    }
}

@Composable
fun ConnectWalletSheet(initialUri: String?, onDismiss: () -> Unit) {
    ScopedViewModels {
        val model: ConnectWalletModel = viewModel { ConnectWalletModel(initialUri) }
        ConnectWalletContent(model, onDismiss)
    }
}

@Composable
private fun ConnectWalletContent(model: ConnectWalletModel, onDismiss: () -> Unit) {
    val wallet = WalletService
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    var showScanner by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { model.receive(wallet.consumeIncomingConnectURI()) }
    LaunchedEffect(wallet.incomingConnectURI) {
        if (wallet.incomingConnectURI != null) model.receive(wallet.consumeIncomingConnectURI())
    }
    LifecycleResumeEffect(Unit) {
        model.refreshClipboard()
        onPauseOrDispose {}
    }
    DisposableEffect(Unit) {
        val manager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val listener = ClipboardManager.OnPrimaryClipChangedListener { model.clipboardChanged() }
        manager.addPrimaryClipChangedListener(listener)
        onDispose { manager.removePrimaryClipChangedListener(listener) }
    }
    val valid = model.isValid
    LaunchedEffect(valid) { if (valid) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove) }
    LaunchedEffect(model.connectedTick) { if (model.connectedTick > 0) haptics.performHapticFeedback(HapticFeedbackType.LongPress) }

    Column(Modifier.fillMaxWidth().imePadding()) {
        SheetTopBar(L("nwcTitle"), onCancel = onDismiss, cancelTag = "wallet-connect-cancel") {
            Button(
                onClick = { model.connect(onDismiss) },
                enabled = model.canConnect && !model.isConnecting,
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
                modifier = Modifier.padding(end = 8.dp).testTag("wallet-connect-submit"),
            ) {
                if (model.isConnecting) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = AppColors.background)
                } else {
                    Text(L("nwcConnect"), fontWeight = FontWeight.SemiBold)
                }
            }
        }
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).animateContentSize().padding(bottom = 24.dp)) {
            FormSection(
                header = L("nwcConnectionString"),
                footer = {
                    when {
                        model.showsInvalid -> NoticeLabel(L("nwcInvalidConnectionString"), Icons.Outlined.ErrorOutline, AppColors.error)
                        model.isValid -> NoticeLabel(L("walletConnectionLooksGood"), Icons.Outlined.CheckCircle, AppColors.success)
                        model.highlightsPaste -> Text(L("walletClipboardReady"))
                        else -> Text(L("walletNwcConnectDescription"))
                    }
                },
            ) {
                FormTextField(model.uri, { model.uri = it }, L("nwcConnectionString"), Modifier.testTag("wallet-connect-uri"), minLines = 3, maxLines = 6, monospace = true)
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    val pasteModifier = Modifier.weight(1f).heightIn(min = 48.dp).testTag("wallet-connect-paste")
                    if (model.highlightsPaste) {
                        FilledTonalButton(onClick = { model.paste() }, shape = CircleShape, modifier = pasteModifier) {
                            Icon(Icons.Outlined.ContentPaste, null, Modifier.size(18.dp))
                            Text(L("walletPaste"), Modifier.padding(start = 8.dp))
                        }
                    } else {
                        OutlinedButton(onClick = { model.paste() }, shape = CircleShape, modifier = pasteModifier) {
                            Icon(Icons.Outlined.ContentPaste, null, Modifier.size(18.dp))
                            Text(L("walletPaste"), Modifier.padding(start = 8.dp))
                        }
                    }
                    OutlinedButton(
                        onClick = { showScanner = true },
                        shape = CircleShape,
                        modifier = Modifier.weight(1f).heightIn(min = 48.dp).testTag("wallet-connect-scan-sheet"),
                    ) {
                        Icon(Icons.Outlined.QrCodeScanner, null, Modifier.size(18.dp))
                        Text(L("walletScan"), Modifier.padding(start = 8.dp))
                    }
                }
            }
            if (wallet.isConnected) {
                FormSection {
                    NoticeLabel(
                        L("walletReplaceWarning", "wallet" to (wallet.walletName ?: wallet.lightningAddress ?: L("wallet"))),
                        Icons.Outlined.WarningAmber,
                        AppColors.error,
                        Modifier.padding(16.dp).testTag("wallet-connect-replace-warning"),
                    )
                }
            }
            if (!model.isValid) {
                FormSection(header = L("walletConnectWithApp"), footer = { Text(L("walletConnectWithAppFooter")) }) {
                    WalletProvider.oneTap.forEachIndexed { index, provider ->
                        if (index > 0) SectionDivider()
                        WalletProviderRow(provider)
                    }
                }
            }
            FormSection(
                footer = {
                    Text(L("nwcDisclaimer"))
                    model.error?.let { Text(it, color = AppColors.error, modifier = Modifier.testTag("wallet-connect-error")) }
                },
            ) {
                ListItem(
                    headlineContent = { Text(L("nwcAccept")) },
                    trailingContent = {
                        Switch(
                            checked = model.accepted,
                            onCheckedChange = { model.accepted = it },
                            colors = SwitchDefaults.colors(checkedTrackColor = AppColors.switchActive),
                            modifier = Modifier.testTag("wallet-connect-accept"),
                        )
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
            }
        }
    }

    if (showScanner) {
        QRScannerDialog(onScan = { model.uri = it }, onDismiss = { showScanner = false })
    }
}
