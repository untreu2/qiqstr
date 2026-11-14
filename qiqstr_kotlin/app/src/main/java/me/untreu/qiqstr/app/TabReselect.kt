package me.untreu.qiqstr.app

import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember

/** Scrolls [state] to the top when the user taps the already-selected tab while it shows its root screen. */
@Composable
fun ScrollToTopOnReselect(tab: AppTab, state: LazyListState, onTop: () -> Unit = {}) {
    val token = Router.reselects[tab] ?: 0
    val initial = remember { token }
    LaunchedEffect(token) {
        if (token == initial) return@LaunchedEffect
        onTop()
        state.animateScrollToItem(0)
    }
}
