package me.untreu.qiqstr.ui.wallet

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material.icons.outlined.FlashOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.AppTab
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile

sealed interface ZapTarget {
    val pubkey: String
    val note: Note? get() = null

    data class NoteTarget(override val note: Note) : ZapTarget {
        override val pubkey: String get() = note.pubkey
    }

    data class ProfileTarget(override val pubkey: String) : ZapTarget
}

class ZapViewModel(val target: ZapTarget) : ViewModel() {
    var selectedPreset by mutableStateOf<Long?>(null)
    var customAmount by mutableStateOf("")
    var comment by mutableStateOf("")
    var recipient by mutableStateOf<ZapRecipient?>(null)
        private set
    var isLoadingRecipient by mutableStateOf(true)
        private set
    var isZapping by mutableStateOf(false)
        private set
    var mayHaveSettled by mutableStateOf(false)
        private set
    var zappedTick by mutableIntStateOf(0)
        private set
    var failedTick by mutableIntStateOf(0)
        private set

    init {
        val initial = ZapService.lastAmount ?: ZapService.defaultAmount
        if (initial in ZapService.presetAmounts) selectedPreset = initial else customAmount = initial.toString()
        viewModelScope.launch { load() }
    }

    val canZap: Boolean get() = ZapService.canZap

    val amount: Long?
        get() {
            customAmount.filter(Char::isDigit).toLongOrNull()?.takeIf { it > 0 }?.let { return it }
            return if (customAmount.isEmpty()) selectedPreset else null
        }

    val fiatEstimate: String? get() = amount?.let { BitcoinPriceService.formatted(it) }?.let { L("walletFiatEstimate", "amount" to it) }

    val hasPayDestination: Boolean get() = recipient?.lightningAddress != null || recipient?.lnurl != null
    val canSubmit: Boolean get() = canZap && amount != null && !isZapping && !mayHaveSettled && hasPayDestination

    val recipientName: String
        get() = recipient?.name ?: ProfileCache.profile(target.pubkey)?.bestName ?: Profile.shortNpub(target.pubkey)

    fun select(preset: Long) {
        selectedPreset = preset
        customAmount = ""
    }

    private suspend fun load() {
        viewModelScope.launch { BitcoinPriceService.refreshIfNeeded() }
        recipient = ZapService.recipient(target.pubkey)
        isLoadingRecipient = false
    }

    fun zap(onDone: () -> Unit) {
        val amount = amount ?: return
        if (!canSubmit) return
        App.scope.launch {
            isZapping = true
            val close = try {
                ZapService.zap(target.note, target.pubkey, amount, comment)
                zappedTick += 1
                ZapService.lastAmount = amount
                ToastCenter.show(L("walletZapped", "sats" to Sats.format(amount), "user" to recipientName), ToastStyle.SUCCESS)
                true
            } catch (error: CancellationException) {
                throw error
            } catch (error: WalletError.PaymentPending) {
                mayHaveSettled = true
                failedTick += 1
                ToastCenter.show(L("walletPaymentPending"), ToastStyle.ERROR)
                true
            } catch (error: Exception) {
                failedTick += 1
                ToastCenter.show("${L("failedToZap")}: ${coreErrorMessage(error)}", ToastStyle.ERROR)
                false
            } finally {
                isZapping = false
            }
            if (close) onDone()
        }
    }

    fun openWallet() {
        Router.sheet = null
        Router.selectedTab = AppTab.WALLET
    }
}

@Composable
fun ZapSheet(target: ZapTarget, onDismiss: () -> Unit) {
    key(target) {
        ScopedViewModels {
            val model: ZapViewModel = viewModel { ZapViewModel(target) }
            ZapContent(model, onDismiss)
        }
    }
}

@Composable
private fun ZapContent(model: ZapViewModel, onDismiss: () -> Unit) {
    val haptics = LocalHapticFeedback.current
    val focus = LocalFocusManager.current
    LaunchedEffect(model.zappedTick) { if (model.zappedTick > 0) haptics.performHapticFeedback(HapticFeedbackType.LongPress) }
    LaunchedEffect(model.failedTick) { if (model.failedTick > 0) haptics.performHapticFeedback(HapticFeedbackType.LongPress) }

    Column(Modifier.fillMaxWidth().imePadding().testTag("zap-sheet")) {
        SheetTopBar(L("zapUser", "user" to model.recipientName), onCancel = onDismiss, cancelEnabled = !model.isZapping, cancelTag = "zap-cancel")
        Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())) {
            FormSection { Header(model) }
            when {
                !model.canZap -> ConnectCta(model)
                !model.isLoadingRecipient && !model.hasPayDestination -> FormSection {
                    NoticeLabel(L("userNoLightningAddress"), Icons.Outlined.FlashOff, AppColors.error, Modifier.padding(16.dp).testTag("zap-no-address"))
                }
                else -> {
                    FormSection(
                        header = L("amount"),
                        footer = model.fiatEstimate?.let { fiat -> { Text(fiat) } },
                    ) {
                        Amounts(model) { focus.clearFocus() }
                        SectionDivider()
                        LabeledRow(L("walletCustomAmount")) {
                            SatsAmountField(model.customAmount, { model.customAmount = it }, Modifier.testTag("zap-custom-amount"))
                        }
                    }
                    FormSection {
                        FormTextField(model.comment, { model.comment = it }, L("commentOptional"), Modifier.testTag("zap-comment"), maxLines = 4)
                    }
                }
            }
        }
        if (model.canZap && model.hasPayDestination) {
            val amount = model.amount
            Button(
                onClick = {
                    focus.clearFocus()
                    model.zap(onDismiss)
                },
                enabled = model.canSubmit,
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 8.dp)
                    .navigationBarsPadding()
                    .heightIn(min = 56.dp)
                    .testTag("zap-submit"),
            ) {
                if (model.isZapping) {
                    CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp, color = AppColors.background)
                } else {
                    Icon(Icons.Filled.Bolt, null, Modifier.size(20.dp))
                    Spacer(Modifier.size(8.dp))
                    Text(
                        if (amount == null) L("zap") else L("walletZapAmount", "amount" to Sats.format(amount)),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }
    }
}

@Composable
private fun Header(model: ZapViewModel) {
    val target = model.target
    Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
        ProfileAvatar(target.pubkey, 44.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(model.recipientName, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val address = model.recipient?.lightningAddress
            if (model.isLoadingRecipient && model.canZap) {
                Text(L("loading"), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
            } else if (address != null) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(Icons.Filled.Bolt, null, Modifier.size(14.dp), tint = AppColors.textSecondary)
                    Text(address, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            val note = target.note
            if (note != null && note.content.isNotEmpty()) {
                Text(
                    note.content,
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textSecondary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(top = 2.dp),
                )
            }
        }
    }
}

@Composable
private fun Amounts(model: ZapViewModel, onSelect: () -> Unit) {
    val haptics = LocalHapticFeedback.current
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        ZapService.presetAmounts.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { preset ->
                    val selected = model.customAmount.isEmpty() && model.selectedPreset == preset
                    FilterChip(
                        selected = selected,
                        onClick = {
                            onSelect()
                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            model.select(preset)
                        },
                        label = {
                            Text(
                                Sats.compact(preset),
                                fontWeight = FontWeight.SemiBold,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.fillMaxWidth(),
                            )
                        },
                        leadingIcon = { Icon(Icons.Filled.Bolt, null, Modifier.size(16.dp)) },
                        shape = CircleShape,
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = AppColors.textPrimary,
                            selectedLabelColor = AppColors.background,
                            selectedLeadingIconColor = AppColors.background,
                        ),
                        modifier = Modifier
                            .weight(1f)
                            .heightIn(min = 44.dp)
                            .semantics {
                                contentDescription = "${Sats.format(preset)} ${L("walletSats")}"
                                this.selected = selected
                            }
                            .testTag("zap-amount-$preset"),
                    )
                }
            }
        }
    }
}

@Composable
private fun ConnectCta(model: ZapViewModel) {
    FormSection {
        Column(
            Modifier.fillMaxWidth().padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(Icons.Outlined.FlashOff, null, Modifier.size(40.dp), tint = AppColors.textSecondary)
            Text(L("walletZapConnectTitle"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(L("walletZapConnectMessage"), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, textAlign = TextAlign.Center)
            Button(
                onClick = { model.openWallet() },
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
                modifier = Modifier.padding(top = 4.dp).testTag("zap-connect-wallet"),
            ) {
                Icon(Icons.Outlined.AccountBalanceWallet, null, Modifier.size(18.dp))
                Spacer(Modifier.size(8.dp))
                Text(L("walletConnectWallet"), fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
