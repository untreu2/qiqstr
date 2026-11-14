package me.untreu.qiqstr.ui.auth

import android.app.Activity
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SessionPhase
import me.untreu.qiqstr.ui.settings.LocalNotificationService
import me.untreu.qiqstr.ui.settings.NotificationPrompt

sealed interface OnboardingStep {
    object Profile : OnboardingStep
    object Interests : OnboardingStep
    data class Follows(val interests: Set<FollowInterest>) : OnboardingStep
}

@Composable
fun OnboardingGate(content: @Composable () -> Unit) {
    var presented by remember { mutableStateOf(Session.isNewAccount && Session.phase == SessionPhase.Ready) }
    val activity = LocalContext.current as? Activity
    LaunchedEffect(activity) { LocalNotificationService.handleLaunch(activity?.intent) }
    Box(Modifier.fillMaxSize()) {
        content()
        if (presented) {
            Surface(Modifier.fillMaxSize(), color = AppColors.background) {
                OnboardingFlow {
                    Session.isNewAccount = false
                    presented = false
                }
            }
        } else {
            NotificationPrompt()
        }
    }
}

@Composable
private fun OnboardingFlow(onFinish: () -> Unit) {
    val path = remember { mutableStateListOf<OnboardingStep>() }
    LaunchedEffect(Unit) { FollowPackService.prefetch() }
    BackHandler { if (path.isNotEmpty()) path.removeAt(path.lastIndex) }
    val pop = { if (path.isNotEmpty()) path.removeAt(path.lastIndex) }
    AnimatedContent(
        targetState = path.lastOrNull() to path.size,
        transitionSpec = {
            if (targetState.second > initialState.second) {
                (slideInHorizontally(tween(260)) { it / 3 } + fadeIn(tween(200))) togetherWith fadeOut(tween(160))
            } else {
                fadeIn(tween(200)) togetherWith (slideOutHorizontally(tween(260)) { it / 3 } + fadeOut(tween(200)))
            }
        },
        label = "onboarding",
    ) { (step, _) ->
        ScopedViewModels {
            when (step) {
                null -> OnboardingKeysScreen { path.add(OnboardingStep.Profile) }
                OnboardingStep.Profile -> OnboardingProfileScreen(onBack = { pop() }) { path.add(OnboardingStep.Interests) }
                OnboardingStep.Interests -> OnboardingInterestsScreen(
                    onBack = { pop() },
                    onSkip = { path.add(OnboardingStep.Follows(emptySet())) },
                    onContinue = { path.add(OnboardingStep.Follows(it)) },
                )
                is OnboardingStep.Follows -> SuggestedFollowsContent(step.interests, onFinish = onFinish, onBack = { pop() })
            }
        }
    }
}
