package me.untreu.qiqstr.ui.explore

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Tag
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.data.services.SearchKind
import me.untreu.qiqstr.ui.articles.ArticleCard
import me.untreu.qiqstr.ui.articles.ArticleCardSkeleton
import me.untreu.qiqstr.ui.note.NoteRow
import me.untreu.qiqstr.ui.profile.UserRow

fun LazyListScope.searchResultSections(model: SearchViewModel) {
    val hex = model.resolvedHex
    if (hex != null) {
        resolvedSection(hex)
        return
    }
    when (model.scope) {
        SearchScope.TOP -> {
            peopleSection(model, 3, true)
            hashtagSection(model, 3, true)
            articlesSection(model, 2, true)
            notesSection(model, 20, true)
        }
        SearchScope.PEOPLE -> peopleSection(model, SearchViewModel.PEOPLE_LIMIT, false)
        SearchScope.NOTES -> notesSection(model, SearchViewModel.NOTES_LIMIT, false)
        SearchScope.HASHTAGS -> hashtagSection(model, 30, false)
        SearchScope.ARTICLES -> articlesSection(model, SearchViewModel.ARTICLES_LIMIT, false)
    }
    if (model.remoteFailed) item(key = "remote-failed") { SearchInlineMessage(L("searchRelaysUnavailable")) }
}

private fun LazyListScope.resolvedSection(hex: String) {
    item(key = "resolved-profile") {
        ListItem(
            headlineContent = { Text(L("exploreOpenProfile")) },
            leadingContent = { Icon(Icons.Outlined.AccountCircle, null) },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            modifier = Modifier.clickable { Router.push(Route.Profile(hex)) }.testTag("search-open-profile"),
        )
    }
    item(key = "resolved-note") {
        ListItem(
            headlineContent = { Text(L("searchOpenNote")) },
            leadingContent = { Icon(Icons.Outlined.ChatBubbleOutline, null) },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            modifier = Modifier.clickable { Router.push(Route.Thread(hex)) }.testTag("search-open-note"),
        )
    }
}

private fun seeAll(model: SearchViewModel, scope: SearchScope, count: Int, limit: Int): (() -> Unit)? =
    if (count > limit) ({ model.scope = scope }) else null

private fun LazyListScope.searchingHeader(key: String) {
    item(key = key) {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp, color = AppColors.textSecondary)
            Text(L("searchSearchingRelays"), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
        }
    }
}

private fun LazyListScope.peopleSection(model: SearchViewModel, limit: Int, header: Boolean) {
    val loading = SearchKind.PEOPLE in model.pending || model.isSearchingLocal
    if (model.people.isEmpty() && !loading) return
    if (header) {
        item(key = "people-header") {
            SearchSectionHeader(L("searchScopePeople"), loading && model.people.isNotEmpty(), seeAll(model, SearchScope.PEOPLE, model.people.size, limit))
        }
    } else if (loading && model.people.isNotEmpty()) {
        searchingHeader("people-searching")
    }
    if (model.people.isEmpty()) {
        items(if (header) 2 else 5, key = { "people-skeleton-$it" }) { SearchPersonSkeletonRow() }
    } else {
        items(model.people.take(limit), key = { "people-${it.pubkey}" }) { profile ->
            UserRow(profile.pubkey, Modifier.testTag("search-people-section"), onClick = {
                model.remember()
                Router.push(Route.Profile(profile.pubkey))
            })
        }
    }
}

private fun LazyListScope.hashtagSection(model: SearchViewModel, limit: Int, header: Boolean) {
    val matches = model.hashtags
    if (matches.isEmpty()) return
    if (header) {
        item(key = "hashtags-header") { SearchSectionHeader(L("searchScopeHashtags"), seeAll = seeAll(model, SearchScope.HASHTAGS, matches.size, limit)) }
    }
    items(matches.take(limit), key = { "hashtag-${it.tag}" }) { match ->
        ListItem(
            headlineContent = { Text("#${match.tag}") },
            leadingContent = { Icon(Icons.Outlined.Tag, null, tint = AppColors.textSecondary) },
            trailingContent = { if (match.count > 0) Text(Sats.format(match.count.toLong()), color = AppColors.textSecondary) },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            modifier = Modifier
                .clickable {
                    model.remember()
                    Router.push(Route.Hashtag(match.tag))
                }
                .testTag(if (match.tag == model.queryHashtag) "search-hashtag" else "search-hashtag-${match.tag}"),
        )
    }
}

private fun LazyListScope.articlesSection(model: SearchViewModel, limit: Int, header: Boolean) {
    val loading = SearchKind.ARTICLES in model.pending || model.isSearchingLocal
    if (model.articles.isEmpty() && !(loading && !header)) return
    if (header) {
        item(key = "articles-header") {
            SearchSectionHeader(L("searchScopeArticles"), loading, seeAll(model, SearchScope.ARTICLES, model.articles.size, limit))
        }
    } else if (loading && model.articles.isNotEmpty()) {
        searchingHeader("articles-searching")
    }
    if (model.articles.isEmpty()) {
        items(2, key = { "articles-skeleton-$it" }) { ArticleCardSkeleton(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) }
    } else {
        items(model.articles.take(limit), key = { "article-${it.id}" }) { article ->
            ArticleCard(
                article,
                Modifier.padding(horizontal = 16.dp, vertical = 8.dp).testTag("search-articles-section"),
            )
        }
    }
}

private fun LazyListScope.notesSection(model: SearchViewModel, limit: Int, header: Boolean) {
    val loading = SearchKind.NOTES in model.pending || model.isSearchingLocal
    if (model.notes.isEmpty() && !loading) return
    if (header) {
        item(key = "notes-header") {
            SearchSectionHeader(L("searchScopeNotes"), loading && model.notes.isNotEmpty(), seeAll(model, SearchScope.NOTES, model.notes.size, limit))
        }
    } else if (loading && model.notes.isNotEmpty()) {
        searchingHeader("notes-searching")
    }
    if (model.notes.isEmpty()) {
        items(3, key = { "notes-skeleton-$it" }) { SearchNoteSkeletonRow(if (it == 1) 3 else 2) }
    } else {
        items(model.notes.take(limit), key = { "note-${it.listId}" }) { note ->
            NoteRow(note, Modifier.testTag("search-notes-section"), onClick = {
                model.remember()
                Router.push(Route.Thread(note.id))
            })
        }
    }
}
