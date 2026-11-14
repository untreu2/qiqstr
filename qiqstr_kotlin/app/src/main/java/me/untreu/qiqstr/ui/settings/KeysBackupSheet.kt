package me.untreu.qiqstr.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.GppBad
import androidx.compose.material.icons.outlined.GppGood
import androidx.compose.material.icons.outlined.GppMaybe
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.data.accounts.Ncryptsec
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.ui.auth.AuthTextField
import me.untreu.qiqstr.ui.auth.ScopedViewModels
import me.untreu.qiqstr.ui.auth.SecureClipboard
import me.untreu.qiqstr.ui.auth.rememberHaptics

enum class KeysPasswordStrength { WEAK, FAIR, STRONG;

    val title: String
        get() = when (this) {
            WEAK -> L("keysBackupStrengthWeak")
            FAIR -> L("keysBackupStrengthFair")
            STRONG -> L("keysBackupStrengthStrong")
        }

    val icon: ImageVector
        get() = when (this) {
            WEAK -> Icons.Outlined.GppBad
            FAIR -> Icons.Outlined.GppMaybe
            STRONG -> Icons.Outlined.GppGood
        }

    companion object {
        fun of(password: String): KeysPasswordStrength {
            val classes = listOf(
                password.any { it.isLowerCase() },
                password.any { it.isUpperCase() },
                password.any { it.isDigit() },
                password.any { !it.isLetterOrDigit() },
            ).count { it }
            val count = password.length
            return when {
                count < Ncryptsec.MINIMUM_PASSWORD_LENGTH || (count < 12 && classes < 2) -> WEAK
                count >= 16 || (count >= 12 && classes >= 3) -> STRONG
                else -> FAIR
            }
        }
    }
}

class KeysBackupModel : ViewModel() {
    var password by mutableStateOf("")
    var confirmation by mutableStateOf("")
    var isEncrypting by mutableStateOf(false)
        private set
    var ncryptsec by mutableStateOf<String?>(null)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set
    var copied by mutableStateOf(false)
        private set
    var copyCount by mutableIntStateOf(0)
        private set

    val strength: KeysPasswordStrength get() = KeysPasswordStrength.of(password)
    val isLongEnough: Boolean get() = password.length >= Ncryptsec.MINIMUM_PASSWORD_LENGTH
    val matches: Boolean get() = confirmation.isNotEmpty() && password == confirmation
    val showMismatch: Boolean get() = confirmation.isNotEmpty() && password != confirmation
    val canEncrypt: Boolean get() = isLongEnough && matches && !isEncrypting

    fun encrypt(privateKeyHex: String) {
        if (!canEncrypt) return
        isEncrypting = true
        errorMessage = null
        viewModelScope.launch {
            try {
                ncryptsec = Ncryptsec.encrypt(privateKeyHex, password)
                password = ""
                confirmation = ""
            } catch (error: Throwable) {
                errorMessage = coreErrorMessage(error)
            } finally {
                isEncrypting = false
            }
        }
    }

    fun copy() {
        val value = ncryptsec ?: return
        SecureClipboard.copy(value, sensitive = true)
        copied = true
        copyCount += 1
        ToastCenter.show(L("copiedToClipboardWithType", "type" to "NCRYPTSEC"), ToastStyle.SUCCESS)
        viewModelScope.launch {
            delay(2000)
            copied = false
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun KeysBackupSheet(privateKeyHex: String, onDismiss: () -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = { true })
    ScopedViewModels {
        val model: KeysBackupModel = viewModel()
        ModalBottomSheet(
            onDismissRequest = { if (!model.isEncrypting) onDismiss() },
            sheetState = state,
            containerColor = AppColors.background,
            modifier = Modifier.testTag("keys-backup-sheet"),
        ) {
            KeysBackupContent(model, privateKeyHex, onDismiss)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun KeysBackupContent(model: KeysBackupModel, privateKeyHex: String, onDismiss: () -> Unit) {
    val haptics = rememberHaptics()
    val focus = LocalFocusManager.current
    val passwordFocus = remember { FocusRequester() }
    val confirmFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { passwordFocus.requestFocus() } }
    LaunchedEffect(model.copyCount) { if (model.copyCount > 0) haptics.success() }
    LaunchedEffect(model.ncryptsec) { if (model.ncryptsec != null) haptics.success() }
    val encrypt = {
        if (model.canEncrypt) {
            focus.clearFocus()
            model.encrypt(privateKeyHex)
        }
    }
    val result = model.ncryptsec
    Column(Modifier.fillMaxWidth().navigationBarsPadding().imePadding()) {
        TopAppBar(
            title = { Text(L("keysBackupTitle")) },
            navigationIcon = {
                if (result == null) IconButton(onClick = onDismiss, enabled = !model.isEncrypting) { Icon(Icons.Filled.Close, L("cancel")) }
            },
            actions = {
                when {
                    result != null -> IconButton(onClick = onDismiss, modifier = Modifier.testTag("keys-backup-done")) { Icon(Icons.Filled.Check, L("done")) }
                    model.isEncrypting -> CircularProgressIndicator(Modifier.padding(end = 16.dp).size(22.dp), strokeWidth = 2.dp, color = AppColors.textPrimary)
                    else -> Box(Modifier.testTag("keys-backup-encrypt")) { TextAction(L("keysBackupEncrypt"), { encrypt() }, enabled = model.canEncrypt) }
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background),
        )
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (result != null) {
                Box(Modifier.fillMaxWidth().padding(vertical = 8.dp), contentAlignment = Alignment.Center) { SettingsQRCode(result) }
                Text(L("keysBackupResultHeader"), style = MaterialTheme.typography.labelLarge, color = AppColors.textSecondary)
                SelectionContainer {
                    Text(result, fontFamily = FontFamily.Monospace, modifier = Modifier.testTag("keys-backup-value"))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    androidx.compose.material3.FilledTonalButton(onClick = { model.copy() }, modifier = Modifier.testTag("keys-backup-copy")) {
                        Icon(if (model.copied) Icons.Filled.Check else Icons.Outlined.ContentCopy, null, Modifier.size(18.dp))
                        Text("  " + if (model.copied) L("copied") else L("copy"))
                    }
                    androidx.compose.material3.FilledTonalButton(onClick = { SettingsShare.text(result) }, modifier = Modifier.testTag("keys-backup-share")) {
                        Icon(Icons.Outlined.Share, null, Modifier.size(18.dp))
                        Text("  " + L("share"))
                    }
                }
                Text(L("keysBackupResultFooter"), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
            } else {
                AuthTextField(
                    value = model.password,
                    onValueChange = { model.password = it },
                    placeholder = L("keysBackupPassword"),
                    secure = true,
                    imeAction = ImeAction.Next,
                    onSubmit = { runCatching { confirmFocus.requestFocus() } },
                    enabled = !model.isEncrypting,
                    modifier = Modifier.focusRequester(passwordFocus).testTag("keys-backup-password"),
                )
                AuthTextField(
                    value = model.confirmation,
                    onValueChange = { model.confirmation = it },
                    placeholder = L("keysBackupConfirm"),
                    secure = true,
                    imeAction = ImeAction.Done,
                    onSubmit = { encrypt() },
                    enabled = !model.isEncrypting,
                    modifier = Modifier.focusRequester(confirmFocus).testTag("keys-backup-confirm"),
                )
                if (model.password.isNotEmpty()) {
                    val strength = model.strength
                    val tint = when (strength) {
                        KeysPasswordStrength.WEAK -> AppColors.error
                        KeysPasswordStrength.FAIR -> Color(0xFFFF9500)
                        KeysPasswordStrength.STRONG -> AppColors.success
                    }
                    Row(Modifier.fillMaxWidth().testTag("keys-backup-strength"), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(L("keysBackupStrength"), modifier = Modifier.weight(1f), maxLines = 1)
                        Icon(strength.icon, null, Modifier.size(18.dp), tint = tint)
                        Text(strength.title, color = tint, maxLines = 1)
                    }
                }
                when {
                    model.showMismatch -> Text(L("keysBackupMismatch"), color = AppColors.error, style = MaterialTheme.typography.bodySmall)
                    model.password.isNotEmpty() && !model.isLongEnough ->
                        Text(L("keysBackupTooShort", "count" to Ncryptsec.MINIMUM_PASSWORD_LENGTH), color = AppColors.error, style = MaterialTheme.typography.bodySmall)
                }
                model.errorMessage?.let { Text(it, color = AppColors.error, style = MaterialTheme.typography.bodySmall) }
                Text(L("keysBackupPasswordFooter", "count" to Ncryptsec.MINIMUM_PASSWORD_LENGTH), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
                if (model.isEncrypting) {
                    Row(Modifier.testTag("keys-backup-progress"), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = AppColors.textSecondary)
                        Text(L("keysBackupEncrypting"), color = AppColors.textSecondary)
                    }
                }
            }
        }
    }
}
