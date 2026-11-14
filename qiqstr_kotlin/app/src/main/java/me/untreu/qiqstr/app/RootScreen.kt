package me.untreu.qiqstr.app

import androidx.compose.animation.Crossfade
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.ThemeState
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.LoadingView
import me.untreu.qiqstr.core.components.PillButton
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.core.components.ToastHost
import me.untreu.qiqstr.data.services.ListConfirmation
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SessionPhase
import me.untreu.qiqstr.ui.auth.AuthFlowScreen
import me.untreu.qiqstr.ui.auth.OnboardingGate

@Composable
fun RootScreen() {
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { if (Session.phase == SessionPhase.Launching) Session.launch() }
    key(ThemeState.language) {
        Box(Modifier.fillMaxSize().background(AppColors.background)) {
            Crossfade(Session.phase, label = "phase") { phase ->
                when (phase) {
                    SessionPhase.Launching, SessionPhase.Starting -> LoadingView(Modifier.testTag("splash"))
                    SessionPhase.SignedOut -> AuthFlowScreen()
                    SessionPhase.Ready -> key(Session.account?.npub) { OnboardingGate { HomeScreen() } }
                    is SessionPhase.Failed -> Column(
                        Modifier.fillMaxSize().safeDrawingPadding().padding(bottom = 32.dp),
                        verticalArrangement = Arrangement.Center,
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        EmptyStateView(icon = Icons.Outlined.WarningAmber, title = L("errorLoadingProfile"), message = phase.message, actionTitle = L("retry")) {
                            scope.launch { Session.launch() }
                        }
                        PillButton(L("launchResetCache"), { scope.launch { Session.recoverFromLaunchFailure() } }, filled = false, modifier = Modifier.testTag("launch-reset-cache"))
                        TextAction(L("logout"), { scope.launch { Session.logout() } }, color = AppColors.error)
                    }
                }
            }
            ToastHost(Modifier.align(Alignment.TopCenter))
            ListConfirmation.pendingKind?.let { kind ->
                AlertDialog(
                    onDismissRequest = { ListConfirmation.respond(false) },
                    title = { Text(L("listNotFoundTitle")) },
                    text = { Text(L("listNotFoundMessage", "list" to ListConfirmation.name(kind))) },
                    confirmButton = { TextAction(L("listStartNew"), { ListConfirmation.respond(true) }) },
                    dismissButton = { TextAction(L("cancel"), { ListConfirmation.respond(false) }) },
                )
            }
        }
    }
}
