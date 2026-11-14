package me.untreu.qiqstr.ui.explore

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.HowToReg
import androidx.compose.material.icons.outlined.PersonSearch
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.domain.Profile

class UserSearchViewModel : ViewModel() {
    val search = UserSearchModel(viewModelScope)

    fun updateQuery(value: String) {
        val old = search.query
        search.updateQuery(value)
        if (value.length - old.length > 20) openResolved()
    }

    fun openResolved() {
        val pubkey = UserSearchService.pubkey(search.query) ?: return
        Router.push(Route.Profile(pubkey))
    }
}

@Composable
fun UserSearchScreen() {
    val model: UserSearchViewModel = viewModel()
    val search = model.search
    val clipboard = LocalClipboardManager.current
    LaunchedEffect(Unit) { search.loadSuggestions() }
    ExploreLargeScaffold(
        title = L("users"),
        actions = {
            IconButton(
                onClick = {
                    val text = clipboard.getText()?.text?.trim()
                    if (!text.isNullOrEmpty()) model.updateQuery(text)
                },
                modifier = Modifier.testTag("user-search-paste"),
            ) { Icon(Icons.Outlined.ContentPaste, L("explorePaste")) }
        },
        below = {
            ExploreSearchField(search.query, model::updateQuery, L("searchByNameOrNpub"), onSearch = model::openResolved)
        },
    ) { padding ->
        PaddedBox(padding) {
            LazyColumn(Modifier.fillMaxSize().testTag("user-search-list")) {
                if (search.trimmedQuery.isEmpty()) suggestionsSection(search) else resultsSection(search)
            }
            if (search.trimmedQuery.isNotEmpty() && search.results.isEmpty()) {
                if (search.isSearching) {
                    Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        CircularProgressIndicator(color = AppColors.textPrimary)
                        Text(L("searchingForUsers"), color = AppColors.textSecondary)
                    }
                } else if (search.hasSearched) {
                    EmptyStateView(
                        icon = Icons.Outlined.PersonSearch,
                        title = L("noUsersFound"),
                        message = L("trySearchingDifferentTerm"),
                        actionTitle = L("retry"),
                        modifier = Modifier.align(Alignment.Center),
                    ) { search.retry() }
                }
            }
        }
    }
}

private fun LazyListScope.suggestionsSection(search: UserSearchModel) {
    item(key = "hint") {
        Text(L("exploreSearchHint"), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
    }
    if (search.suggestions.isNotEmpty()) {
        item(key = "suggested-header") { SearchSectionHeader(L("exploreSuggested")) }
        items(search.suggestions, key = { "s-${it.pubkey}" }) { UserSearchRow(it) }
    }
}

private fun LazyListScope.resultsSection(search: UserSearchModel) {
    search.resolvedPubkey?.let { pubkey ->
        item(key = "resolved") {
            ListItem(
                headlineContent = { Text(L("exploreOpenProfile"), fontWeight = FontWeight.SemiBold) },
                leadingContent = { Icon(Icons.Outlined.HowToReg, null) },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                modifier = Modifier.clickable { Router.push(Route.Profile(pubkey)) }.testTag("user-search-open-resolved"),
            )
        }
    }
    items(search.results, key = { "r-${it.pubkey}" }) { UserSearchRow(it) }
    if (search.isSearching && search.results.isNotEmpty()) {
        item(key = "searching") {
            Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = AppColors.textSecondary)
                Text(L("searchingForUsers"), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, modifier = Modifier.padding(start = 8.dp))
            }
        }
    }
}

@Composable
private fun UserSearchRow(profile: Profile) {
    LongPressMenuBox(
        onClick = { Router.push(Route.Profile(profile.pubkey)) },
        menu = { dismiss -> ExploreUserMenu(profile.pubkey, dismiss) },
    ) {
        Box(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) { ExploreUserRow(profile) }
    }
}
