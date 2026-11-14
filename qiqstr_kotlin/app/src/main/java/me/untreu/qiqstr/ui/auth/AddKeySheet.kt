package me.untreu.qiqstr.ui.auth

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
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
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.data.accounts.Ncryptsec
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Profile

class AddKeyViewModel : ViewModel() {
    var input by mutableStateOf("")
    var isRevealed by mutableStateOf(false)
    var isSaving by mutableStateOf(false)
        private set
    var isDecrypting by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
    var password by mutableStateOf("")
    var passwordError by mutableStateOf<String?>(null)
    var failureCount by mutableIntStateOf(0)
        private set
    var successCount by mutableIntStateOf(0)
        private set

    val isEncryptedInput: Boolean get() = Ncryptsec.matches(input)
    val canSubmit: Boolean get() = input.isNotBlank() && !isSaving && (!isEncryptedInput || password.isNotEmpty())

    fun paste() {
        val text = SecureClipboard.paste() ?: return
        input = text
        errorMessage = null
    }

    fun applyScanned(value: String) {
        input = Nip19.stripScheme(value.trim())
        errorMessage = null
    }

    fun submit(onDone: () -> Unit) {
        if (!canSubmit) return
        isSaving = true
        errorMessage = null
        passwordError = null
        viewModelScope.launch {
            try {
                var key = input
                if (isEncryptedInput) {
                    isDecrypting = true
                    key = try {
                        Ncryptsec.decrypt(input, password)
                    } catch (error: Throwable) {
                        passwordError = coreErrorMessage(error)
                        failureCount += 1
                        return@launch
                    }
                    isDecrypting = false
                    password = ""
                }
                try {
                    Session.addKey(key)
                    successCount += 1
                    ToastCenter.show(L("addKeySuccess"), ToastStyle.SUCCESS)
                    onDone()
                } catch (error: Throwable) {
                    errorMessage = coreErrorMessage(error)
                    failureCount += 1
                }
            } finally {
                isSaving = false
                isDecrypting = false
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddKeySheet(onDismiss: () -> Unit) {
    ScopedViewModels { AddKeyContent(onDismiss) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddKeyContent(onDismiss: () -> Unit) {
    val model: AddKeyViewModel = viewModel()
    val focus = LocalFocusManager.current
    val inputFocus = remember { FocusRequester() }
    val passwordFocus = remember { FocusRequester() }
    val haptics = rememberHaptics()
    val scan = rememberQrScanner { model.applyScanned(it) }
    val pubkey = Session.pubkey
    val accountName = pubkey?.let { ProfileCache.profiles[it]?.bestName ?: Profile.shortNpub(it) } ?: ""
    var previousLength by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { runCatching { inputFocus.requestFocus() } }
    LaunchedEffect(model.failureCount) { if (model.failureCount > 0) haptics.error() }
    LaunchedEffect(model.successCount) { if (model.successCount > 0) haptics.success() }
    LaunchedEffect(model.input) {
        if (model.isEncryptedInput && model.input.length - previousLength > 1) runCatching { passwordFocus.requestFocus() }
        previousLength = model.input.length
    }
    LaunchedEffect(model.password) { model.passwordError = null }
    val submit = {
        focus.clearFocus()
        model.submit(onDismiss)
    }
    Column(Modifier.fillMaxWidth().imePadding().testTag("add-key-sheet")) {
        TopAppBar(
            title = { Text(L("addKeyTitle")) },
            navigationIcon = { IconButton(onClick = onDismiss, enabled = !model.isSaving) { Icon(Icons.Filled.Close, L("cancel")) } },
            actions = {
                if (model.isSaving) {
                    CircularProgressIndicator(Modifier.padding(end = 16.dp).size(22.dp), strokeWidth = 2.dp, color = AppColors.textPrimary)
                } else {
                    IconButton(onClick = { submit() }, enabled = model.canSubmit, modifier = Modifier.testTag("add-key-submit")) {
                        Icon(Icons.Filled.Check, L("done"))
                    }
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background),
        )
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(L("privateKeyNsec"), style = MaterialTheme.typography.labelLarge, color = AppColors.textSecondary)
            AuthTextField(
                value = model.input,
                onValueChange = { model.input = it },
                placeholder = L("addKeyPlaceholder"),
                secure = !model.isRevealed,
                singleLine = !model.isRevealed,
                imeAction = ImeAction.Done,
                onSubmit = { submit() },
                enabled = !model.isSaving,
                modifier = Modifier.focusRequester(inputFocus).testTag("add-key-input"),
                trailing = {
                    IconButton(onClick = { model.isRevealed = !model.isRevealed }) {
                        Icon(
                            if (model.isRevealed) Icons.Outlined.Visibility else Icons.Outlined.VisibilityOff,
                            if (model.isRevealed) L("hideKey") else L("showKey"),
                            tint = AppColors.textSecondary,
                        )
                    }
                },
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = { model.paste() }) {
                    Icon(Icons.Outlined.ContentPaste, null, Modifier.size(18.dp), tint = AppColors.textPrimary)
                    Text("  " + L("authPaste"), color = AppColors.textPrimary, fontWeight = FontWeight.SemiBold)
                }
                TextButton(onClick = scan) {
                    Icon(Icons.Outlined.QrCodeScanner, null, Modifier.size(18.dp), tint = AppColors.textPrimary)
                    Text("  " + L("scanQRCode"), color = AppColors.textPrimary, fontWeight = FontWeight.SemiBold)
                }
            }
            model.errorMessage?.let { AuthErrorText(it) }
            Text(L("addKeySubtitle", "name" to accountName), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
            AnimatedVisibility(model.isEncryptedInput) {
                Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(L("authNcryptsecPasswordHeader"), style = MaterialTheme.typography.labelLarge, color = AppColors.textSecondary)
                    AuthTextField(
                        value = model.password,
                        onValueChange = { model.password = it },
                        placeholder = L("authNcryptsecPassword"),
                        secure = true,
                        imeAction = ImeAction.Done,
                        onSubmit = { submit() },
                        enabled = !model.isSaving,
                        modifier = Modifier.focusRequester(passwordFocus).testTag("add-key-ncryptsec-password"),
                    )
                    if (model.isDecrypting) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = AppColors.textSecondary)
                            Text(L("authDecrypting"), color = AppColors.textSecondary)
                        }
                    }
                    val error = model.passwordError
                    if (error != null) {
                        AuthErrorText(error, tag = "add-key-ncryptsec-error")
                    } else {
                        Text(L("authNcryptsecDetected"), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
                    }
                }
            }
        }
    }
}
