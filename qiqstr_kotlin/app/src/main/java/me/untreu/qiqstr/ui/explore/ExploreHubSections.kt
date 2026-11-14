package me.untreu.qiqstr.ui.explore

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.PersonSearch
import androidx.compose.material.icons.outlined.Sensors
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.IconTile
import me.untreu.qiqstr.data.services.DiscoverFeedContent
import me.untreu.qiqstr.data.services.ExploreService
import me.untreu.qiqstr.ui.live.liveNowSection

typealias Launch = (suspend () -> Unit) -> Unit

fun LazyListScope.exploreHubSections(
    section: ExploreSection,
    model: SearchViewModel,
    launch: Launch,
    onSelect: (ExploreSection) -> Unit,
    onOpenMedia: (Int) -> Unit,
) {
    when (section) {
        ExploreSection.FOR_YOU -> forYou(model, launch, onSelect, onOpenMedia)
        ExploreSection.FEEDS -> discoverFeedSections(launch)
        ExploreSection.PEOPLE -> people(launch)
        ExploreSection.ZAPS -> zaps(launch)
        ExploreSection.TOPICS -> topics(launch)
        ExploreSection.MEDIA -> Unit
    }
}

private fun topicTags(model: SearchViewModel): List<String> {
    val tags = ExploreService.topics.take(16).map { it.tag }
    return tags.ifEmpty { model.trendingHashtags }
}

private fun LazyListScope.forYou(model: SearchViewModel, launch: Launch, onSelect: (ExploreSection) -> Unit, onOpenMedia: (Int) -> Unit) {
    liveNowSection()
    val tags = topicTags(model)
    if (tags.isNotEmpty()) {
        item(key = "topics-header") { SearchSectionHeader(L("exploreTrendingTopics")) { onSelect(ExploreSection.TOPICS) } }
        item(key = "topics-chips") { TopicChips(tags) }
    }
    val feeds = ExploreService.feeds
    if (feeds.isNotEmpty()) {
        item(key = "feeds-header") { SearchSectionHeader(L("explorePopularFeeds")) { onSelect(ExploreSection.FEEDS) } }
        item(key = "feeds-carousel") {
            Box(Modifier.testTag("explore-popular-feeds")) {
                ExploreCarousel { items(feeds.take(10), key = { it.id }) { DiscoverFeedCard(it) } }
            }
        }
    }
    val media = ExploreService.visibleMedia
    if (media.isNotEmpty()) {
        item(key = "media-header") { SearchSectionHeader(L("exploreTrendingMedia")) { onSelect(ExploreSection.MEDIA) } }
        item(key = "media-strip") {
            Box(Modifier.testTag("explore-media-strip")) { ExploreMediaStrip(media.take(12), onOpenMedia) }
        }
    }
    val people = ExploreService.visiblePeople
    if (people.isNotEmpty()) {
        item(key = "people-header") { SearchSectionHeader(L("exploreRisingPeople")) { onSelect(ExploreSection.PEOPLE) } }
        item(key = "people-carousel") {
            Box(Modifier.testTag("explore-rising-people")) {
                ExploreCarousel { items(people.take(12), key = { it.pubkey }) { RisingPersonCard(it) } }
            }
        }
    }
    val zaps = ExploreService.visibleZaps
    if (zaps.isNotEmpty()) {
        item(key = "zaps-header") { SearchSectionHeader(L("exploreTopZaps")) { onSelect(ExploreSection.ZAPS) } }
        items(zaps.take(3), key = { "zap-${it.id}" }) { zap -> TopZapRow(zap, zap.noteId?.let { ExploreService.zapNotes[it] }) }
    }
    item(key = "more-header") { SearchSectionHeader(L("exploreMore")) }
    item(key = "link-reads") {
        ExploreLink(L("reads"), L("exploreReadsSubtitle"), Icons.Outlined.Description, "explore-link-reads") { Router.push(Route.Reads) }
    }
    item(key = "link-live") {
        ExploreLink(L("liveTitle"), L("exploreLiveSubtitle"), Icons.Outlined.Sensors, "explore-link-live") { Router.push(Route.LiveStreams) }
    }
    item(key = "link-people") {
        ExploreLink(L("exploreFindPeople"), L("exploreFindPeopleSubtitle"), Icons.Outlined.PersonSearch, "explore-link-people") { Router.push(Route.UserSearch) }
    }
    searchDiscoverySections(
        model,
        onRetryTrending = { launch { model.loadTrending(force = true) } },
        showsHashtags = false,
        showsRecents = false,
        showsLive = false,
        showsPeople = people.isEmpty(),
    )
}

@Composable
private fun ExploreLink(title: String, subtitle: String, icon: ImageVector, tag: String, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title, fontWeight = FontWeight.SemiBold) },
        supportingContent = { Text(subtitle, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, maxLines = 2, overflow = TextOverflow.Ellipsis) },
        leadingContent = { IconTile(icon, size = 40.dp) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.clickable(onClick = onClick).testTag(tag),
    )
}

private fun LazyListScope.people(launch: Launch) {
    val people = ExploreService.visiblePeople
    item(key = "people-list-header") { SearchSectionHeader(L("exploreRisingPeople")) }
    if (people.isEmpty()) {
        if (ExploreService.isLoading("people")) {
            exploreLoadingRows("people", 5, person = true)
        } else {
            item(key = "people-retry") { RetryRow(L("exploreUnavailable")) { launch { ExploreService.loadPeople(force = true) } } }
        }
    } else {
        items(people.take(15), key = { "rising-${it.pubkey}" }) { RisingPersonRow(it) }
        item(key = "people-footer") { SectionFooter(L("exploreRisingFooter")) }
    }
}

private fun LazyListScope.zaps(launch: Launch) {
    val zaps = ExploreService.visibleZaps
    item(key = "zaps-list-header") { SearchSectionHeader(L("exploreTopZapsToday")) }
    if (zaps.isEmpty()) {
        if (ExploreService.isLoading("zaps")) {
            exploreLoadingRows("zaps", 4)
        } else {
            item(key = "zaps-retry") { RetryRow(L("exploreUnavailable")) { launch { ExploreService.loadZaps(force = true) } } }
        }
    } else {
        items(zaps, key = { "zap-list-${it.id}" }) { zap -> TopZapRow(zap, zap.noteId?.let { ExploreService.zapNotes[it] }) }
    }
}

private fun LazyListScope.topics(launch: Launch) {
    val topics = ExploreService.topics
    item(key = "topics-list-header") { SearchSectionHeader(L("exploreTrendingTopics")) }
    if (topics.isEmpty()) {
        if (ExploreService.isLoading("topics")) {
            exploreLoadingRows("topics", 6, person = true)
        } else {
            item(key = "topics-retry") { RetryRow(L("exploreUnavailable")) { launch { ExploreService.loadTopics(force = true) } } }
        }
    } else {
        itemsIndexed(topics, key = { _, topic -> "topic-${topic.tag}" }) { index, topic -> TopicRow(topic, index + 1) }
        item(key = "topics-footer") { SectionFooter(L("exploreTopicsFooter")) }
    }
}

fun LazyListScope.discoverFeedSections(launch: Launch) {
    val feeds = ExploreService.feeds
    val pinned = ExploreService.pinnedFeeds
    val pinnedIds = pinned.map { it.id }.toSet()
    val notesFeeds = feeds.filter { it.content == DiscoverFeedContent.NOTES && it.id !in pinnedIds }
    val readsFeeds = feeds.filter { it.content == DiscoverFeedContent.READS }
    if (pinned.isNotEmpty()) {
        item(key = "pinned-header") { SearchSectionHeader(L("exploreFeedsOnHome")) }
        items(pinned, key = { "pinned-${it.id}" }) { DiscoverFeedRow(it) }
        item(key = "pinned-footer") { SectionFooter(L("exploreFeedsOnHomeFooter")) }
    }
    if (feeds.isEmpty()) {
        if (ExploreService.isLoading("feeds")) {
            exploreLoadingRows("feeds", 5, person = true)
        } else {
            item(key = "feeds-retry") { RetryRow(L("exploreUnavailable")) { launch { ExploreService.loadFeeds(force = true) } } }
        }
    }
    if (notesFeeds.isNotEmpty()) {
        item(key = "note-feeds-header") { SearchSectionHeader(L("exploreNoteFeeds")) }
        items(notesFeeds, key = { "note-feed-${it.id}" }) { DiscoverFeedRow(it) }
        item(key = "note-feeds-footer") { SectionFooter(L("exploreNoteFeedsFooter")) }
    }
    if (readsFeeds.isNotEmpty()) {
        item(key = "read-feeds-header") { SearchSectionHeader(L("exploreReadFeeds")) }
        items(readsFeeds, key = { "read-feed-${it.id}" }) { DiscoverFeedRow(it) }
    }
}
