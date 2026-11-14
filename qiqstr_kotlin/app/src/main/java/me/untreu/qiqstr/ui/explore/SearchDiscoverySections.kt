package me.untreu.qiqstr.ui.explore

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.History
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.ui.live.liveNowSection
import me.untreu.qiqstr.ui.note.NoteRow
import me.untreu.qiqstr.ui.profile.UserRow

fun LazyListScope.searchDiscoverySections(
    model: SearchViewModel,
    onRetryTrending: () -> Unit,
    showsHashtags: Boolean = true,
    showsRecents: Boolean = true,
    showsLive: Boolean = true,
    showsPeople: Boolean = true,
) {
    if (showsRecents && model.recents.isNotEmpty()) searchRecentSection(model)
    if (showsHashtags && model.trendingHashtags.isNotEmpty()) {
        item(key = "trending-hashtags-header") { SearchSectionHeader(L("searchTrendingHashtags")) }
        item(key = "trending-hashtags") { TopicChips(model.trendingHashtags) }
    }
    if (showsLive) liveNowSection()
    if (showsPeople && model.suggestions.isNotEmpty()) {
        item(key = "suggested-people-header") { SearchSectionHeader(L("searchSuggestedPeople")) { Router.push(Route.UserSearch) } }
        items(model.suggestions.take(5), key = { "suggested-${it.pubkey}" }) { profile ->
            UserRow(profile.pubkey, Modifier.testTag("search-suggested-people"))
        }
    }
    item(key = "trending-notes-header") { SearchSectionHeader(L("searchTrendingNotes")) }
    if (model.trendingNotes.isEmpty()) {
        if (model.isLoadingTrending) {
            items(4, key = { "trending-skeleton-$it" }) { SearchNoteSkeletonRow(if (it % 2 == 0) 3 else 2) }
        } else if (model.trendingFailed) {
            item(key = "trending-failed") { RetryRow(L("searchTrendingUnavailable"), onRetryTrending) }
        }
    } else {
        items(model.trendingNotes, key = { "trending-${it.listId}" }) { note ->
            NoteRow(note, Modifier.testTag("search-trending-notes"))
        }
    }
}

fun LazyListScope.searchRecentSection(model: SearchViewModel) {
    item(key = "recents-header") {
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 16.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(L("searchRecent"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            TextButton(onClick = { model.clearRecents() }, modifier = Modifier.testTag("search-clear-recents")) {
                Text(L("searchClearRecent"), color = AppColors.textPrimary)
            }
        }
    }
    items(model.recents.take(8), key = { "recent-$it" }) { term -> RecentRow(term, model) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RecentRow(term: String, model: SearchViewModel) {
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) {
            model.removeRecent(term)
            true
        } else {
            false
        }
    })
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        modifier = Modifier.testTag("search-recents"),
        backgroundContent = {
            Box(Modifier.fillMaxSize().background(AppColors.error).padding(horizontal = 24.dp), contentAlignment = Alignment.CenterEnd) {
                Icon(Icons.Outlined.Delete, L("searchRemoveRecent"), tint = Color.White)
            }
        },
    ) {
        Row(
            Modifier.fillMaxWidth().background(AppColors.background).clickable { model.useRecent(term) }.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(Icons.Outlined.History, null, tint = AppColors.textSecondary)
            Text(term, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}
