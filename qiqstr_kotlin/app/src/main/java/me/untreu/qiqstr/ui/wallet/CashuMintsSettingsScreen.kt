package me.untreu.qiqstr.ui.wallet

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.*
import me.untreu.qiqstr.data.services.*
import me.untreu.qiqstr.ui.settings.*

class CashuMintsSettingsViewModel : ViewModel() {
    fun load() = viewModelScope.launch { NutzapService.load(); WalletService.refreshCashuBalance() }
    fun refreshBalance() = viewModelScope.launch { WalletService.refreshCashuBalance() }
    fun setReceiving(enabled: Boolean) = save { NutzapService.setReceiving(enabled) }
    fun toggle(mint: String) {
        val next = if (mint in NutzapService.mints) NutzapService.mints - mint else NutzapService.mints + mint
        save { NutzapService.setReceiving(next.isNotEmpty(), next) }
    }
    fun add(raw: String) {
        val mint = CashuMint.normalized(raw)
        if (mint in NutzapService.mints) return
        save { NutzapService.lookup(mint); NutzapService.setReceiving(true, NutzapService.mints + mint) }
    }
    private fun save(work: suspend () -> Unit) {
        if (!ReadOnlyGate.check()) return
        viewModelScope.launch { try { work() } catch (error: Exception) { ToastCenter.error(error) } }
    }
}

@Composable
fun CashuMintsSettingsScreen() {
    val model: CashuMintsSettingsViewModel = viewModel()
    var showAdd by remember { mutableStateOf(false) }
    var newMint by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { model.load() }
    LaunchedEffect(NutzapService.receivedTick) { model.refreshBalance() }
    SettingsScaffold(L("nutzapTitle"), tag = "nutzap-settings") {
        settingsSection("receive", footer = L("nutzapReceiveFooter")) {
            SettingsToggle(L("nutzapReceive"), Icons.Outlined.Payments, NutzapService.isReceiving, Modifier.testTag("nutzap-receive"), enabled = !NutzapService.isSaving) { model.setReceiving(it) }
            if (NutzapService.isSaving) CircularProgressIndicator()
        }
        if (WalletService.cashuBalanceSats > 0) settingsSection("balance", footer = L("cashuUnclaimedFooter")) { SettingsRow(L("cashuUnclaimed"), Icons.Outlined.Payments, Modifier.testTag("nutzap-balance"), value = L("walletSatsAmount", "amount" to Sats.format(WalletService.cashuBalanceSats))) }
        settingsSection("mints", header = L("cashuMints"), footer = L("cashuMintsFooter")) {
            NutzapService.mintOptions.forEach { mint ->
                SettingsRow(CashuMint.displayName(mint), Icons.Outlined.AccountBalance, Modifier.testTag("nutzap-mint-${CashuMint.displayName(mint)}"), enabled = !NutzapService.isSaving, trailing = { if (mint in NutzapService.mints) Icon(Icons.Outlined.Check, null) }) { model.toggle(mint) }
            }
            SettingsRow(L("cashuAddMint"), Icons.Outlined.Add, Modifier.testTag("nutzap-mint-add"), enabled = !NutzapService.isSaving) { newMint = ""; showAdd = true }
        }
    }
    if (showAdd) AlertDialog(onDismissRequest = { showAdd = false }, title = { Text(L("cashuAddMint")) }, text = { OutlinedTextField(newMint, { newMint = it }, placeholder = { Text("mint.example.com") }, singleLine = true, modifier = Modifier.testTag("nutzap-mint-field")) }, confirmButton = { TextButton(onClick = { showAdd = false; model.add(newMint) }, enabled = CashuMint.isValid(newMint)) { Text(L("settingsAdd")) } }, dismissButton = { TextButton(onClick = { showAdd = false }) { Text(L("cancel")) } })
}
