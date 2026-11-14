package me.untreu.qiqstr.ui.explore

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.data.services.ExploreService

@Composable
fun DiscoverFeedsScreen() {
    val scope = rememberCoroutineScope()
    val launch: Launch = { block -> scope.launch { block() } }
    LaunchedEffect(Unit) {
        ExploreService.refreshPinnedIfNeeded()
        ExploreService.loadFeeds()
    }
    ExploreLargeScaffold(title = L("exploreFeeds"), modifier = Modifier.testTag("discover-feeds")) { padding ->
        PaddedBox(padding) {
            RefreshBox(onRefresh = { ExploreService.loadFeeds(force = true) }) {
                LazyColumn(Modifier.fillMaxSize()) { discoverFeedSections(launch) }
            }
        }
    }
}
