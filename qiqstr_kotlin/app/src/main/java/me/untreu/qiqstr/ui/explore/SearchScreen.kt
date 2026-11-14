package me.untreu.qiqstr.ui.explore

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.data.services.ExploreService
import me.untreu.qiqstr.data.services.LiveService
import me.untreu.qiqstr.ui.live.LiveNowSectionModel

@Composable
fun SearchScreen() {
    val model: SearchViewModel = viewModel()
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var section by rememberSaveable { mutableStateOf(ExploreSection.FOR_YOU) }
    var mediaSelection by rememberSaveable { mutableStateOf<Int?>(null) }
    var searchFocused by rememberSaveable { mutableStateOf(false) }
    val launch: Launch = { block -> scope.launch { block() } }

    LaunchedEffect(Unit) { model.start() }
    LaunchedEffect(Unit) { LiveNowSectionModel.load() }
    LaunchedEffect(Unit) {
        ExploreService.refreshPinnedIfNeeded()
        ExploreService.loadAll()
    }
    LaunchedEffect(model.opened) { if (model.opened > 0) haptics.performHapticFeedback(HapticFeedbackType.LongPress) }

    Scaffold(
        modifier = Modifier.fillMaxSize().testTag("search-list"),
        containerColor = AppColors.background,
        contentWindowInsets = WindowInsets(0),
        topBar = {
            Column(Modifier.statusBarsPadding()) {
                Text(
                    L("feedExplore"),
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    color = AppColors.textPrimary,
                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 4.dp),
                )
                ExploreSearchField(
                    model.query,
                    model::updateQuery,
                    L("searchPrompt"),
                    onSearch = model::submit,
                    onFocusChange = { searchFocused = it },
                )
                if (model.trimmedQuery.isEmpty() && !searchFocused) {
                    ExploreChipBar(section) { section = it }
                } else {
                    ScopeBar(model.scope) { model.scope = it }
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when {
                model.trimmedQuery.isNotEmpty() -> {
                    LazyColumn(Modifier.fillMaxSize()) { searchResultSections(model) }
                    if (model.showsEmptyResults) {
                        EmptyStateView(
                            icon = Icons.Outlined.Search,
                            title = L("noResultsFound"),
                            message = L("trySearchingDifferentTerm"),
                            modifier = Modifier.align(Alignment.Center),
                        )
                    }
                }
                searchFocused && model.recents.isNotEmpty() -> LazyColumn(Modifier.fillMaxSize()) { searchRecentSection(model) }
                section == ExploreSection.MEDIA -> RefreshBox(onRefresh = { ExploreService.loadMedia(force = true) }) {
                    ExploreMediaGrid { mediaSelection = it }
                }
                else -> key(section) {
                    RefreshBox(onRefresh = { refresh(section, model) }) {
                        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 16.dp)) {
                            exploreHubSections(section, model, launch, onSelect = { section = it }, onOpenMedia = { mediaSelection = it })
                        }
                    }
                }
            }
        }
    }
    mediaSelection?.let { index ->
        ExploreMediaViewer(ExploreService.visibleMedia, index) { mediaSelection = null }
    }
}

@Composable
private fun ScopeBar(selection: SearchScope, onSelect: (SearchScope) -> Unit) {
    LazyRow(contentPadding = PaddingValues(horizontal = 16.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(SearchScope.entries.size) { index ->
            val scope = SearchScope.entries[index]
            FilterChip(
                selected = scope == selection,
                onClick = { onSelect(scope) },
                label = { Text(scope.title) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = AppColors.textPrimary,
                    selectedLabelColor = AppColors.background,
                ),
                modifier = Modifier.testTag("search-scope-${scope.raw}"),
            )
        }
    }
}

private suspend fun refresh(section: ExploreSection, model: SearchViewModel) {
    coroutineScope {
        when (section) {
            ExploreSection.FOR_YOU -> {
                launch { LiveService.load(force = true) }
                launch { model.refresh() }
                launch { ExploreService.loadAll(force = true) }
            }
            ExploreSection.FEEDS -> ExploreService.loadFeeds(force = true)
            ExploreSection.PEOPLE -> ExploreService.loadPeople(force = true)
            ExploreSection.ZAPS -> ExploreService.loadZaps(force = true)
            ExploreSection.TOPICS -> ExploreService.loadTopics(force = true)
            ExploreSection.MEDIA -> ExploreService.loadMedia(force = true)
        }
    }
}
