package me.untreu.qiqstr.ui.explore

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Article
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.ui.articles.ArticleCard
import me.untreu.qiqstr.ui.articles.ArticleCardSkeleton
import me.untreu.qiqstr.ui.articles.ContinueReadingSection

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExploreScreen() {
    val model: ExploreViewModel = viewModel()
    val scope = rememberCoroutineScope()
    var started by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        if (started) return@LaunchedEffect
        started = true
        model.start()
    }
    LaunchedEffect(DataBus.feedVersion) {
        if (!started) return@LaunchedEffect
        delay(300)
        model.reload()
    }
    ExploreLargeScaffold(
        title = L("reads"),
        subtitle = if (model.scope == ExploreScope.FOLLOWING) L("readsSubtitle") else L("exploreGlobalSubtitle"),
        modifier = Modifier.testTag("explore-list"),
        actions = {
            IconButton(onClick = { Router.push(Route.UserSearch) }, modifier = Modifier.testTag("explore-user-search")) {
                Icon(Icons.Outlined.People, L("users"))
            }
        },
        below = {
            ExploreSearchField(model.query, model::updateQuery, L("exploreSearchPrompt"))
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp).testTag("explore-scope-picker")) {
                ExploreScope.entries.forEachIndexed { index, value ->
                    SegmentedButton(
                        selected = model.scope == value,
                        onClick = { model.updateScope(value) },
                        shape = SegmentedButtonDefaults.itemShape(index, ExploreScope.entries.size),
                        icon = { Icon(if (value == ExploreScope.FOLLOWING) Icons.Outlined.People else Icons.Outlined.Public, null, Modifier.size(SegmentedButtonDefaults.IconSize)) },
                        label = { Text(value.title) },
                    )
                }
            }
        },
    ) { padding ->
        PaddedBox(padding) {
            RefreshBox(onRefresh = { model.refresh() }) {
                val articles = model.visibleArticles
                val users = model.users
                LazyColumn(Modifier.fillMaxSize()) {
                    if (model.trimmedQuery.isNotEmpty() && (users.results.isNotEmpty() || users.isSearching)) {
                        item(key = "users-header") {
                            SearchSectionHeader(L("users"), isLoading = users.isSearching) { Router.push(Route.UserSearch) }
                        }
                        items(users.results, key = { "user-${it.pubkey}" }) { profile ->
                            LongPressMenuBox(
                                onClick = { Router.push(Route.Profile(profile.pubkey)) },
                                modifier = Modifier.testTag("explore-users-section"),
                                menu = { dismiss -> ExploreUserMenu(profile.pubkey, dismiss) },
                            ) {
                                Box(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) { ExploreUserRow(profile) }
                            }
                        }
                    }
                    if (model.trimmedQuery.isEmpty()) item(key = "continue-reading") { ContinueReadingSection() }
                    if (model.isLoading && articles.isEmpty()) {
                        items(3, key = { "article-skeleton-$it" }) { ArticleCardSkeleton(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) }
                    } else if (articles.isNotEmpty()) {
                        if (model.trimmedQuery.isNotEmpty()) item(key = "articles-header") { SearchSectionHeader(L("articles")) }
                        items(articles, key = { "article-${it.id}" }) { article ->
                            ArticleCard(article, Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                            if (article.id == articles.lastOrNull()?.id) LaunchedEffect(article.id) { model.loadMore() }
                        }
                        if (model.isLoadingMore) {
                            item(key = "loading-more") {
                                Box(Modifier.fillMaxWidth().padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
                                    CircularProgressIndicator(Modifier.size(24.dp), color = AppColors.textPrimary)
                                }
                            }
                        }
                    }
                }
                if (!model.isLoading && articles.isEmpty()) {
                    if (model.trimmedQuery.isEmpty()) {
                        EmptyStateView(
                            icon = Icons.Outlined.Article,
                            title = L("noArticlesYet"),
                            message = if (model.scope == ExploreScope.FOLLOWING) L("longFormContentDescription") else null,
                            actionTitle = L("refresh"),
                            modifier = Modifier.align(Alignment.Center),
                        ) { scope.launch { model.refresh() } }
                    } else if (users.results.isEmpty() && !users.isSearching) {
                        EmptyStateView(
                            icon = Icons.Outlined.Search,
                            title = L("noResultsFound"),
                            message = L("trySearchingDifferentTerm"),
                            modifier = Modifier.align(Alignment.Center),
                        )
                    }
                }
            }
        }
    }
}
