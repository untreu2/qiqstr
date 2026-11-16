package me.untreu.qiqstr.ui.wallet

import android.content.Intent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.ui.Alignment
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.*
import me.untreu.qiqstr.data.services.*
import me.untreu.qiqstr.ui.note.NoteActionHandler

class CashuSendModel : ViewModel() {
    var amountText by mutableStateOf("")
    var mint by mutableStateOf(NutzapService.sendMint)
    var isCreating by mutableStateOf(false)
        private set
    var created by mutableStateOf<SentCashuToken?>(null)
        private set
    var error by mutableStateOf<String?>(null)
        private set
    val amount: Long? get() = amountText.filter(Char::isDigit).toLongOrNull()?.takeIf { it > 0 && SatsAmount.msat(it) != null }
    val canCreate: Boolean get() = amount != null && !isCreating && WalletService.isConnected
    fun create() {
        val amount = amount ?: return
        if (!canCreate || !ReadOnlyGate.check()) return
        isCreating = true
        App.scope.launch {
            error = null
            try { NutzapService.sendMint = mint; created = NutzapService.createToken(mint, amount); amountText = "" }
            catch (failure: Exception) { error = coreErrorMessage(failure) }
            finally { isCreating = false }
        }
    }
    fun show(token: SentCashuToken) { created = token }
    fun reset() { created = null }
    fun forget(token: SentCashuToken) = NutzapService.forget(token)
    fun load() = viewModelScope.launch { if (!NutzapService.isLoaded) NutzapService.load() }
}

@Composable
fun CashuSendSheet(onDismiss: () -> Unit, onCreatingChanged: (Boolean) -> Unit = {}) {
    val model: CashuSendModel = viewModel()
    val context = LocalContext.current
    LaunchedEffect(Unit) { model.load() }
    LaunchedEffect(model.isCreating) { onCreatingChanged(model.isCreating) }
    var mintMenu by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().imePadding().testTag("cashu-send-sheet")) {
        SheetTopBar(L("cashuSendTitle"), onCancel = onDismiss, cancelEnabled = !model.isCreating, cancelTag = "cashu-send-close")
        Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())) {
            val token = model.created
            if (token != null) {
                FormSection(footer = { Text(L("cashuTokenFooter")) }) {
                    Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        Text(L("walletSatsAmount", "amount" to Sats.format(token.amountSats)), style = MaterialTheme.typography.headlineSmall)
                        QRCodeView(token.token, 240.dp)
                        Text(token.token, maxLines = 3, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall)
                    }
                }
                FormSection {
                    TextButton(onClick = { NoteActionHandler.copy(context, token.token) }, modifier = Modifier.testTag("cashu-token-copy")) { Text(L("copy")) }
                    TextButton(onClick = { context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, token.token), null)) }, modifier = Modifier.testTag("cashu-token-share")) { Text(L("share")) }
                    TextButton(onClick = model::reset, modifier = Modifier.testTag("cashu-send-new")) { Text(L("cashuNewToken")) }
                }
            } else {
                FormSection(footer = { Text(L("cashuSendFooter")); model.error?.let { Text(it, color = AppColors.error, modifier = Modifier.testTag("cashu-send-error")) } }) {
                    LabeledRow(L("amount")) { SatsAmountField(model.amountText, { model.amountText = it }, Modifier.testTag("cashu-send-amount")) }
                    Box {
                        TextButton(onClick = { mintMenu = true }, enabled = !model.isCreating, modifier = Modifier.testTag("cashu-send-mint")) { Text("${L("cashuMint")}: ${CashuMint.displayName(model.mint)}") }
                        DropdownMenu(mintMenu, { mintMenu = false }) {
                            (listOf(model.mint) + NutzapService.mintOptions).distinct().forEach { mint -> DropdownMenuItem(text = { Text(CashuMint.displayName(mint)) }, onClick = { model.mint = mint; mintMenu = false }) }
                        }
                    }
                }
                if (NutzapService.sentTokens.isNotEmpty()) FormSection(header = L("cashuSentTokens")) {
                    NutzapService.sentTokens.forEach { sent ->
                        key(sent.token) {
                            val dismiss = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
                                if (value == SwipeToDismissBoxValue.EndToStart) model.forget(sent)
                                false
                            })
                            SwipeToDismissBox(state = dismiss, enableDismissFromStartToEnd = false, backgroundContent = {
                                Box(Modifier.fillMaxSize().background(AppColors.error).padding(16.dp), contentAlignment = Alignment.CenterEnd) { Icon(Icons.Outlined.Delete, L("delete"), tint = MaterialTheme.colorScheme.onError) }
                            }) {
                                ListItem(
                                    headlineContent = { Text(L("walletSatsAmount", "amount" to Sats.format(sent.amountSats))) },
                                    supportingContent = { Text("${CashuMint.displayName(sent.mint)} · ${TimeFormat.relative(sent.createdAt)}") },
                                    trailingContent = { IconButton(onClick = { model.forget(sent) }) { Icon(Icons.Outlined.Delete, L("delete")) } },
                                    modifier = Modifier.clickable { model.show(sent) }.testTag("cashu-sent-row"),
                                    colors = ListItemDefaults.colors(containerColor = AppColors.background),
                                )
                            }
                        }
                    }
                }
            }
        }
        if (model.created == null) Button(onClick = model::create, enabled = model.canCreate, modifier = Modifier.fillMaxWidth().padding(20.dp).navigationBarsPadding().testTag("cashu-send-create")) {
            if (model.isCreating) CircularProgressIndicator(Modifier.size(20.dp)) else Text(L("cashuCreateToken"))
        }
    }
}
