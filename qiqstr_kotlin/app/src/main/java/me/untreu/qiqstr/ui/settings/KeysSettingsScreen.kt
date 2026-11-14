package me.untreu.qiqstr.ui.settings

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.EnhancedEncryption
import androidx.compose.material.icons.outlined.SettingsSuggest
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.ui.auth.SecureClipboard
import me.untreu.qiqstr.ui.auth.SeedGrid
import me.untreu.qiqstr.ui.auth.clickableRow
import me.untreu.qiqstr.ui.auth.rememberHaptics

enum class SettingsSecretKind(val raw: String) {
    NSEC("nsec"), MNEMONIC("mnemonic");

    val title: String get() = if (this == NSEC) L("privateKeyNsec") else L("seedPhrase")
}

class KeysSettingsModel : ViewModel() {
    var npub by mutableStateOf("")
        private set
    var nsec by mutableStateOf<String?>(null)
        private set
    var mnemonic by mutableStateOf<String?>(null)
        private set
    var privateKeyHex by mutableStateOf<String?>(null)
        private set
    var revealed by mutableStateOf<Set<SettingsSecretKind>>(emptySet())
        private set
    var copied by mutableStateOf<String?>(null)
        private set
    var pendingCopy by mutableStateOf<SettingsSecretKind?>(null)
    var isBackupPresented by mutableStateOf(false)
    var showAdvanced by mutableStateOf(false)
    var copyCount by mutableIntStateOf(0)
        private set
    private var authenticatedAt: Long? = null

    fun load() {
        val account = Session.account
        npub = account?.npub ?: ""
        privateKeyHex = account?.signingKey
        nsec = account?.signingKey?.let { Nip19.nsec(it) }
        mnemonic = account?.mnemonic?.ifEmpty { null }
    }

    fun isRevealed(kind: SettingsSecretKind) = kind in revealed

    val isRecentlyAuthenticated: Boolean get() = authenticatedAt?.let { System.currentTimeMillis() - it < 60_000 } ?: false

    fun markAuthenticated() { authenticatedAt = System.currentTimeMillis() }

    fun reveal(kind: SettingsSecretKind) { revealed = revealed + kind }

    fun hide(kind: SettingsSecretKind) { revealed = revealed - kind }

    fun confirmCopy() {
        val kind = pendingCopy ?: return
        pendingCopy = null
        val value = (if (kind == SettingsSecretKind.NSEC) nsec else mnemonic) ?: return
        SecureClipboard.copy(value, sensitive = true)
        markCopied(kind.raw, if (kind == SettingsSecretKind.NSEC) "NSEC" else L("seedPhrase"))
    }

    fun copyNpub() {
        SecureClipboard.copy(npub, sensitive = false)
        markCopied("npub", "NPUB")
    }

    fun hideAll() {
        revealed = emptySet()
        authenticatedAt = null
    }

    private fun markCopied(id: String, label: String) {
        copied = id
        copyCount += 1
        ToastCenter.show(L("copiedToClipboardWithType", "type" to label), ToastStyle.SUCCESS)
        viewModelScope.launch {
            delay(2000)
            if (copied == id) copied = null
        }
    }

    fun isCopied(id: String) = copied == id
}

@Composable
fun rememberDeviceAuthenticator(onAuthenticated: () -> Unit): (String, (Boolean) -> Unit) -> Unit {
    val context = LocalContext.current
    var callback by remember { mutableStateOf<((Boolean) -> Unit)?>(null) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val ok = result.resultCode == Activity.RESULT_OK
        if (ok) onAuthenticated()
        callback?.invoke(ok)
        callback = null
    }
    return { reason, done ->
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        @Suppress("DEPRECATION")
        val intent = if (keyguard.isDeviceSecure) keyguard.createConfirmDeviceCredentialIntent(L("keysTitle"), reason) else null
        if (intent == null) {
            onAuthenticated()
            done(true)
        } else {
            callback = done
            runCatching { launcher.launch(intent) }.onFailure { callback = null; done(false) }
        }
    }
}

@Composable
fun KeysSettingsScreen() {
    val model: KeysSettingsModel = viewModel()
    val haptics = rememberHaptics()
    val authenticator = rememberDeviceAuthenticator { model.markAuthenticated() }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(Unit) { model.load() }
    LaunchedEffect(model.copyCount) { if (model.copyCount > 0) haptics.success() }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) {
                model.hideAll()
                model.isBackupPresented = false
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }

    fun authenticate(reason: String = L("keysAuthenticateReason"), then: () -> Unit) {
        if (model.isRecentlyAuthenticated) then() else authenticator(reason) { if (it) then() }
    }

    fun toggleReveal(kind: SettingsSecretKind) {
        if (model.isRevealed(kind)) model.hide(kind) else authenticate { model.reveal(kind) }
    }

    @Composable
    fun CopyRow(copied: Boolean, tag: String, onClick: () -> Unit) {
        SettingsRow(
            if (copied) L("copied") else L("copy"),
            if (copied) Icons.Filled.Check else Icons.Outlined.ContentCopy,
            modifier = Modifier.testTag(tag),
            onClick = onClick,
        )
    }

    @Composable
    fun SecretRows(kind: SettingsSecretKind, content: @Composable () -> Unit) {
        val revealed = model.isRevealed(kind)
        Box(
            Modifier.clickableRow { if (!revealed) toggleReveal(kind) }.padding(horizontal = 16.dp, vertical = 8.dp)
                .semantics { contentDescription = if (revealed) kind.title else L("keysTapToReveal") },
        ) { content() }
        SettingsRow(
            if (revealed) L("hideKey") else L("showKey"),
            if (revealed) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
            modifier = Modifier.testTag("keys-reveal-${kind.raw}"),
        ) { toggleReveal(kind) }
        CopyRow(model.isCopied(kind.raw), "keys-copy-${kind.raw}") { authenticate { model.pendingCopy = kind } }
    }

    SettingsScaffold(L("keysTitle")) {
        settingsSection("npub", L("publicKeyNpub"), footer = L("shareThisToReceiveMessages")) {
            Text(
                model.npub.ifEmpty { L("loading") },
                style = MaterialTheme.typography.bodyLarge,
                fontFamily = FontFamily.Monospace,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp).testTag("keys-npub"),
            )
            CopyRow(model.isCopied("npub"), "keys-copy-npub") { model.copyNpub() }
        }
        settingsSection("seed", L("seedPhrase"), footer = L("useThisToRecoverAccount")) {
            val mnemonic = model.mnemonic
            if (mnemonic != null) {
                SecretRows(SettingsSecretKind.MNEMONIC) {
                    SeedGrid(
                        mnemonic.split(" ").filter { it.isNotEmpty() },
                        Modifier.testTag("keys-seed-grid"),
                        masked = !model.isRevealed(SettingsSecretKind.MNEMONIC),
                        tiled = false,
                    )
                }
            } else {
                Text(L("notAvailable"), color = AppColors.textSecondary, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
            }
        }
        if (model.privateKeyHex != null) {
            settingsSection("backup", L("keysBackupHeader"), footer = L("keysBackupFooter")) {
                SettingsRow(L("keysBackupCreate"), Icons.Outlined.EnhancedEncryption, modifier = Modifier.testTag("keys-backup-create")) {
                    if (model.privateKeyHex != null) authenticate(L("keysBackupAuthenticateReason")) { model.isBackupPresented = true }
                }
            }
        }
        settingsSection(
            "advanced",
            if (model.showAdvanced) L("privateKeyNsec") else null,
            footer = if (model.showAdvanced) L("keepThisSecret") else null,
        ) {
            val rotation by animateFloatAsState(if (model.showAdvanced) 90f else 0f, label = "chevron")
            SettingsRow(
                L("advanced"),
                Icons.Outlined.SettingsSuggest,
                modifier = Modifier.testTag("keys-advanced"),
                trailing = { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, Modifier.rotate(rotation), tint = AppColors.textTertiary) },
            ) { model.showAdvanced = !model.showAdvanced }
            AnimatedVisibility(model.showAdvanced) {
                androidx.compose.foundation.layout.Column {
                    val nsec = model.nsec
                    if (nsec != null) {
                        SecretRows(SettingsSecretKind.NSEC) {
                            val revealed = model.isRevealed(SettingsSecretKind.NSEC)
                            Text(
                                if (revealed) nsec else "•".repeat(nsec.length),
                                fontFamily = FontFamily.Monospace,
                                color = if (revealed) AppColors.textPrimary else AppColors.textSecondary,
                            )
                        }
                    } else {
                        Text(L("errorEncodingNsec"), color = AppColors.error, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                    }
                }
            }
        }
    }

    val key = model.privateKeyHex
    if (model.isBackupPresented && key != null) KeysBackupSheet(key) { model.isBackupPresented = false }
    if (model.pendingCopy != null) {
        AlertDialog(
            onDismissRequest = { model.pendingCopy = null },
            title = { Text(L("warning")) },
            text = { Text(L("copyKeyWarning")) },
            confirmButton = { Box(Modifier.testTag("keys-copy-confirm")) { TextAction(L("copy"), { model.confirmCopy() }) } },
            dismissButton = { TextAction(L("cancel"), { model.pendingCopy = null }) },
        )
    }
}
