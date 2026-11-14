package me.untreu.qiqstr.ui.wallet

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.AppSheet
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.domain.Note

data class ZapButtonState(val isZapped: Boolean, val isPending: Boolean, val addedSats: Long)

fun zapButtonState(note: Note, hasZapped: Boolean = note.hasZapped): ZapButtonState {
    val pending = ZapService.pendingSats[note.id]
    return ZapButtonState(
        isZapped = hasZapped || pending != null || ZapService.hasZapped(note.id),
        isPending = pending != null,
        addedSats = ZapService.optimisticSats(note.id) + (pending ?: 0L),
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ZapButton(
    note: Note,
    modifier: Modifier = Modifier,
    hasZapped: Boolean = note.hasZapped,
    label: @Composable (ZapButtonState) -> Unit,
) {
    val haptics = LocalHapticFeedback.current
    val state = zapButtonState(note, hasZapped)
    fun openSheet() = Router.present(AppSheet.Zap(note))
    fun tap() {
        if (Router.sheet != null) return
        if (!ZapService.prefersQuickZap || ZapService.defaultAmount > ZapService.QUICK_ZAP_LIMIT) {
            openSheet()
            return
        }
        if (ZapService.isPending(note.id)) return
        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        App.scope.launch {
            when (ZapService.quickZap(note)) {
                is QuickZapResult.Zapped, is QuickZapResult.Failed -> haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                QuickZapResult.NeedsSheet -> openSheet()
            }
        }
    }
    val hint = if (ZapService.prefersQuickZap) L("walletQuickZapHint", "amount" to Sats.format(ZapService.defaultAmount)) else null
    Box(
        modifier
            .combinedClickable(
                onClickLabel = hint ?: L("zap"),
                onClick = { tap() },
                onLongClickLabel = L("walletZapCustom"),
                onLongClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    openSheet()
                },
            )
            .semantics {
                stateDescription = if (state.isZapped) L("walletZappedState") else ""
                customActions = listOf(CustomAccessibilityAction(L("walletZapCustom")) { openSheet(); true })
            }
            .testTag("note-zap"),
        contentAlignment = Alignment.Center,
    ) {
        label(state)
    }
}

@Composable
fun ZapButton(note: Note, modifier: Modifier = Modifier, hasZapped: Boolean = note.hasZapped, zapAmount: Long = 0) {
    ZapButton(note, modifier, hasZapped) { state -> ZapButtonLabel(state, zapAmount) }
}

@Composable
fun ZapButtonLabel(state: ZapButtonState, baseAmount: Long = 0) {
    val total = baseAmount + state.addedSats
    val color = if (state.isZapped) AppColors.zap else AppColors.textSecondary
    Row(
        Modifier.alpha(if (state.isPending) 0.7f else 1f).padding(4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(if (state.isZapped) Icons.Filled.Bolt else Icons.Outlined.Bolt, L("zap"), Modifier.size(18.dp), tint = color)
        if (total > 0) Text(Sats.compact(total), style = MaterialTheme.typography.bodyMedium, color = color)
    }
}

@Composable
fun BoxScope.ZapRetryToast(modifier: Modifier = Modifier) {
    val failure = ZapService.failure
    DisposableEffect(Unit) {
        ZapService.registerFailureHost()
        onDispose { ZapService.unregisterFailureHost() }
    }
    LaunchedEffect(failure?.id) {
        val shown = failure ?: return@LaunchedEffect
        delay(6000)
        if (ZapService.failure?.id == shown.id) ZapService.dismissFailure()
    }
    val lastShown = remember { arrayOfNulls<ZapFailure>(1) }
    if (failure != null) lastShown[0] = failure
    AnimatedVisibility(
        visible = failure != null,
        enter = fadeIn() + slideInVertically { it },
        exit = fadeOut() + slideOutVertically { it },
        modifier = modifier.align(Alignment.BottomCenter).padding(horizontal = 20.dp).padding(bottom = 72.dp),
    ) {
        lastShown[0]?.let { ZapRetryBanner(it) }
    }
}

@Composable
fun ZapRetryBanner(failure: ZapFailure) {
    val haptics = LocalHapticFeedback.current
    Surface(
        onClick = { ZapService.dismissFailure() },
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surfaceContainerHighest,
        shadowElevation = 6.dp,
        modifier = Modifier.fillMaxWidth().testTag("zap-retry-toast"),
    ) {
        Row(
            Modifier.padding(start = 18.dp, end = 10.dp, top = 10.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(Icons.Filled.Error, null, tint = AppColors.error)
            Column(Modifier.weight(1f)) {
                Text(L("walletZapFailed", "amount" to Sats.format(failure.amountSats)), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                Text(failure.message, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, maxLines = 2)
            }
            if (!failure.mayHaveSettled) {
                FilledTonalButton(
                    onClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        App.scope.launch { ZapService.retry(failure) }
                    },
                    shape = CircleShape,
                    modifier = Modifier.testTag("zap-retry"),
                ) {
                    Text(L("retry"))
                }
            }
        }
    }
}
