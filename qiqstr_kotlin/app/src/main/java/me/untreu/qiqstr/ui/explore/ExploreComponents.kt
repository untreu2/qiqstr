package me.untreu.qiqstr.ui.explore

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.outlined.NorthEast
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.Tag
import androidx.compose.material.icons.outlined.WifiOff
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.PillButton
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.RemoteImage
import me.untreu.qiqstr.data.services.DiscoverFeed
import me.untreu.qiqstr.data.services.DiscoverFeedContent
import me.untreu.qiqstr.data.services.ExploreMediaEntry
import me.untreu.qiqstr.data.services.ExploreService
import me.untreu.qiqstr.data.services.HashtagFollowService
import me.untreu.qiqstr.data.services.RisingPerson
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.services.TopZap
import me.untreu.qiqstr.data.services.TrendingTopic
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.live.StreamPlayer
import me.untreu.qiqstr.ui.profile.FollowButton

enum class ExploreSection(val raw: String) {
    FOR_YOU("forYou"), FEEDS("feeds"), MEDIA("media"), PEOPLE("people"), ZAPS("zaps"), TOPICS("topics");

    val title: String
        get() = when (this) {
            FOR_YOU -> L("exploreForYou")
            FEEDS -> L("exploreFeeds")
            MEDIA -> L("exploreMedia")
            PEOPLE -> L("explorePeople")
            ZAPS -> L("exploreZaps")
            TOPICS -> L("exploreTopics")
        }

    val icon: ImageVector
        get() = when (this) {
            FOR_YOU -> Icons.Outlined.AutoAwesome
            FEEDS -> Icons.Outlined.Layers
            MEDIA -> Icons.Outlined.PhotoLibrary
            PEOPLE -> Icons.Outlined.People
            ZAPS -> Icons.Outlined.Bolt
            TOPICS -> Icons.Outlined.Tag
        }
}

private fun personName(pubkey: String): String = ProfileCache.profiles[pubkey]?.bestName?.ifEmpty { null } ?: Profile.shortNpub(pubkey)

@Composable
fun ExploreChipBar(selection: ExploreSection, onSelect: (ExploreSection) -> Unit) {
    val state = rememberLazyListState()
    LaunchedEffect(selection) { state.animateScrollToItem(maxOf(0, selection.ordinal - 1)) }
    LazyRow(
        state = state,
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.testTag("explore-sections"),
    ) {
        items(ExploreSection.entries.size) { index ->
            val section = ExploreSection.entries[index]
            val selected = section == selection
            FilterChip(
                selected = selected,
                onClick = { onSelect(section) },
                label = { Text(section.title, fontWeight = FontWeight.SemiBold) },
                leadingIcon = { Icon(section.icon, null, Modifier.size(FilterChipDefaults.IconSize)) },
                shape = CircleShape,
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = AppColors.textPrimary,
                    selectedLabelColor = AppColors.background,
                    selectedLeadingIconColor = AppColors.background,
                ),
                modifier = Modifier.testTag("explore-section-${section.raw}"),
            )
        }
    }
}

@Composable
fun SearchSectionHeader(title: String, isLoading: Boolean = false, seeAll: (() -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 16.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        if (isLoading) CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp, color = AppColors.textSecondary)
        Spacer(Modifier.weight(1f))
        if (seeAll != null) TextButton(onClick = seeAll) { Text(L("exploreSeeAll"), color = AppColors.textPrimary) }
    }
}

@Composable
fun SectionFooter(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
}

@Composable
private fun SkeletonBar(width: Dp, height: Dp = 12.dp) {
    Box(Modifier.width(width).height(height).clip(RoundedCornerShape(4.dp)).background(AppColors.tile))
}

@Composable
fun SearchPersonSkeletonRow() {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(46.dp).clip(CircleShape).background(AppColors.tile))
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            SkeletonBar(130.dp, 14.dp)
            SkeletonBar(160.dp)
        }
    }
}

@Composable
fun SearchNoteSkeletonRow(lines: Int = 2) {
    Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(40.dp).clip(CircleShape).background(AppColors.tile))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SkeletonBar(120.dp, 14.dp)
            repeat(lines) { index ->
                Box(Modifier.fillMaxWidth(if (index == lines - 1) 0.6f else 1f).height(12.dp).clip(RoundedCornerShape(4.dp)).background(AppColors.tile))
            }
        }
    }
}

@Composable
fun SearchInlineMessage(text: String, icon: ImageVector = Icons.Outlined.WifiOff, modifier: Modifier = Modifier) {
    Row(modifier.padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, null, Modifier.size(16.dp), tint = AppColors.textSecondary)
        Text(text, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
    }
}

@Composable
fun RetryRow(text: String, onRetry: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        SearchInlineMessage(text, modifier = Modifier.weight(1f))
        TextButton(onClick = onRetry) { Text(L("retry"), color = AppColors.textPrimary) }
    }
}

fun LazyListScope.exploreLoadingRows(key: String, count: Int = 3, person: Boolean = false) {
    items(count, key = { "$key-skeleton-$it" }) { index ->
        if (person) SearchPersonSkeletonRow() else SearchNoteSkeletonRow(if (index % 2 == 0) 3 else 2)
    }
}

@Composable
fun ExploreCarousel(content: LazyListScope.() -> Unit) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
        content = content,
    )
}

@Composable
fun DiscoverFeedArtwork(feed: DiscoverFeed, size: Dp = 48.dp) {
    Box(Modifier.size(size).clip(RoundedCornerShape(size * 0.26f)).background(AppColors.tile), contentAlignment = Alignment.Center) {
        if (!feed.image.isNullOrEmpty()) {
            RemoteImage(feed.image, Modifier.fillMaxSize())
        } else {
            Icon(if (feed.content == DiscoverFeedContent.READS) Icons.Outlined.Description else Icons.Outlined.Layers, null, Modifier.size(size * 0.4f), tint = AppColors.textSecondary)
        }
    }
}

@Composable
fun DiscoverFeedPinButton(feed: DiscoverFeed) {
    val pinned = ExploreService.isPinned(feed)
    PillButton(
        title = L(if (pinned) "exploreFeedOnHome" else "exploreFeedAddToHome"),
        icon = if (pinned) Icons.Outlined.Check else Icons.Outlined.Add,
        filled = !pinned,
        modifier = Modifier.testTag("discover-feed-pin-${feed.dTag}"),
        onClick = {
            ExploreService.togglePin(feed)
            ToastCenter.show(L(if (pinned) "exploreFeedUnpinned" else "exploreFeedPinned", "name" to feed.name), ToastStyle.SUCCESS)
        },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiscoverFeedRow(feed: DiscoverFeed) {
    val pinned = ExploreService.isPinned(feed)
    val content: @Composable () -> Unit = {
        LongPressMenuBox(
            onClick = { Router.push(Route.DiscoverFeed(feed.id)) },
            modifier = Modifier.background(AppColors.background).testTag("discover-feed-${feed.dTag}"),
            menu = { dismiss ->
                if (feed.content == DiscoverFeedContent.NOTES) {
                    MenuAction(L(if (pinned) "exploreFeedRemoveFromHome" else "exploreFeedAddToHome"), if (pinned) Icons.Outlined.PushPin else Icons.Filled.PushPin) {
                        dismiss()
                        ExploreService.togglePin(feed)
                    }
                }
                MenuAction(L("exploreOpenProfile"), Icons.Outlined.AccountCircle) {
                    dismiss()
                    Router.push(Route.Profile(feed.pubkey))
                }
            },
        ) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                DiscoverFeedArtwork(feed, 52.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(feed.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                        if (pinned) Icon(Icons.Filled.PushPin, L("exploreFeedOnHome"), Modifier.size(14.dp), tint = AppColors.textSecondary)
                    }
                    if (feed.about.isNotEmpty()) Text(feed.about, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
    if (feed.content != DiscoverFeedContent.NOTES) {
        content()
        return
    }
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) ExploreService.togglePin(feed)
        false
    })
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(Modifier.fillMaxSize().background(if (pinned) AppColors.textSecondary else AppColors.textPrimary).padding(horizontal = 24.dp), contentAlignment = Alignment.CenterEnd) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(if (pinned) Icons.Outlined.PushPin else Icons.Filled.PushPin, null, tint = AppColors.background)
                    Text(L(if (pinned) "exploreFeedRemoveFromHome" else "exploreFeedAddToHome"), color = AppColors.background, fontWeight = FontWeight.SemiBold)
                }
            }
        },
    ) { content() }
}

@Composable
fun DiscoverFeedCard(feed: DiscoverFeed) {
    Column(
        Modifier.width(230.dp).clip(RoundedCornerShape(22.dp)).background(AppColors.tile)
            .clickable { Router.push(Route.DiscoverFeed(feed.id)) }
            .padding(14.dp)
            .testTag("discover-feed-card-${feed.dTag}"),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            DiscoverFeedArtwork(feed, 44.dp)
            Spacer(Modifier.weight(1f))
            if (feed.content == DiscoverFeedContent.READS) {
                Text(
                    L("reads"),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = AppColors.textSecondary,
                    modifier = Modifier.clip(CircleShape).background(AppColors.overlayLight).padding(horizontal = 8.dp, vertical = 3.dp),
                )
            }
        }
        Text(feed.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(feed.about.ifEmpty { " " }, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 2, minLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun RisingIncrease(count: Long, style: androidx.compose.ui.text.TextStyle = MaterialTheme.typography.bodySmall) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        Icon(Icons.Outlined.NorthEast, null, Modifier.size(12.dp), tint = AppColors.repost)
        Text(L("exploreRisingIncrease", "count" to Sats.compact(count)), style = style, color = AppColors.repost, maxLines = 1)
    }
}

@Composable
fun RisingStat(person: RisingPerson) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        if (person.increase > 0) {
            RisingIncrease(person.increase)
            Text("·", style = MaterialTheme.typography.bodySmall, color = AppColors.textTertiary)
        }
        Text(L("exploreFollowerCount", "count" to Sats.compact(person.followers)), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, maxLines = 1)
    }
}

@Composable
fun RisingPersonRow(person: RisingPerson) {
    LongPressMenuBox(
        onClick = { Router.push(Route.Profile(person.pubkey)) },
        modifier = Modifier.testTag("explore-rising-${person.pubkey.take(8)}"),
        menu = { dismiss -> ExploreUserMenu(person.pubkey, dismiss) },
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ProfileAvatar(person.pubkey, size = 46.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(personName(person.pubkey), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                RisingStat(person)
            }
            FollowButton(person.pubkey, compact = true)
        }
    }
}

@Composable
fun RisingPersonCard(person: RisingPerson) {
    LongPressMenuBox(
        onClick = { Router.push(Route.Profile(person.pubkey)) },
        modifier = Modifier.width(140.dp).clip(RoundedCornerShape(22.dp)).background(AppColors.tile),
        menu = { dismiss -> ExploreUserMenu(person.pubkey, dismiss) },
    ) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 14.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            ProfileAvatar(person.pubkey, size = 64.dp)
            Text(personName(person.pubkey), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (person.increase > 0) {
                RisingIncrease(person.increase, MaterialTheme.typography.labelSmall)
            } else {
                Text(L("exploreFollowerCount", "count" to Sats.compact(person.followers)), style = MaterialTheme.typography.labelSmall, color = AppColors.textSecondary, maxLines = 1)
            }
            Spacer(Modifier.height(2.dp))
            FollowButton(person.pubkey, compact = true)
        }
    }
}

@Composable
fun TopZapRow(zap: TopZap, note: Note?) {
    LongPressMenuBox(
        onClick = { zap.noteId?.let { Router.push(Route.Thread(it)) } ?: Router.push(Route.Profile(zap.receiver)) },
        modifier = Modifier.testTag("explore-zap-${zap.id.take(8)}"),
        menu = { dismiss ->
            MenuAction(L("exploreViewSender"), Icons.Outlined.Person) { dismiss(); Router.push(Route.Profile(zap.sender)) }
            MenuAction(L("exploreViewReceiver"), Icons.Filled.Person) { dismiss(); Router.push(Route.Profile(zap.receiver)) }
        },
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box {
                ProfileAvatar(zap.sender, size = 44.dp)
                ProfileAvatar(
                    zap.receiver,
                    size = 22.dp,
                    modifier = Modifier.align(Alignment.BottomEnd).offset(4.dp, 4.dp).border(2.dp, AppColors.background, CircleShape),
                )
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(Icons.Filled.Bolt, null, Modifier.size(18.dp), tint = AppColors.zap)
                    Text(Sats.format(zap.sats), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = AppColors.zap)
                    Spacer(Modifier.weight(1f))
                    Text(TimeFormat.relative(zap.createdAt), style = MaterialTheme.typography.labelSmall, color = AppColors.textTertiary)
                }
                Text(
                    L("exploreZapFromTo", "sender" to "⁨${personName(zap.sender)}⁩", "receiver" to "⁨${personName(zap.receiver)}⁩"),
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                if (zap.comment.isNotEmpty()) {
                    Text(zap.comment, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
                if (note != null && note.content.isNotEmpty()) {
                    Text(
                        note.content,
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textSecondary,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(AppColors.tile).padding(10.dp),
                    )
                }
            }
        }
    }
}

@Composable
fun TopicRow(topic: TrendingTopic, rank: Int? = null) {
    val scope = rememberCoroutineScope()
    val following = HashtagFollowService.isFollowing(topic.tag)
    Row(
        Modifier.fillMaxWidth().clickable { Router.push(Route.Hashtag(topic.tag)) }.padding(horizontal = 16.dp, vertical = 8.dp).testTag("explore-topic-${topic.tag}"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (rank != null) {
            Text("$rank", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = AppColors.textTertiary, modifier = Modifier.widthIn(min = 22.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("#${topic.tag}", style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(L("exploreTopicNotes", "count" to topic.count), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
        }
        PillButton(
            title = if (following) L("following") else L("follow"),
            filled = !following,
            enabled = !HashtagFollowService.isPending(topic.tag),
            onClick = {
                scope.launch {
                    runCatching { if (following) HashtagFollowService.unfollow(topic.tag) else HashtagFollowService.follow(topic.tag) }
                        .onFailure(ToastCenter::error)
                }
            },
        )
    }
}

@Composable
fun TopicChips(tags: List<String>, tagPrefix: String = "search-trending-tag") {
    LazyRow(contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(tags.size, key = { tags[it] }) { index ->
            val tag = tags[index]
            AssistChip(
                onClick = { Router.push(Route.Hashtag(tag)) },
                label = { Text("#$tag") },
                shape = CircleShape,
                modifier = Modifier.testTag("$tagPrefix-$tag"),
            )
        }
    }
}

@Composable
fun ExploreMediaThumb(entry: ExploreMediaEntry, modifier: Modifier = Modifier) {
    Box(modifier.background(AppColors.tile)) {
        if (entry.isVideo) {
            Icon(Icons.Filled.PlayArrow, L("videoTapToPlay"), Modifier.align(Alignment.TopEnd).padding(6.dp).size(18.dp), tint = AppColors.textPrimary)
        } else {
            RemoteImage(entry.url, Modifier.fillMaxSize(), contentDescription = L("profileViewImage"))
        }
    }
}

@Composable
fun ExploreMediaStrip(entries: List<ExploreMediaEntry>, onOpen: (Int) -> Unit) {
    LazyRow(contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        itemsIndexed(entries, key = { _, entry -> entry.id }) { index, entry ->
            ExploreMediaThumb(entry, Modifier.width(120.dp).height(160.dp).clip(RoundedCornerShape(14.dp)).clickable { onOpen(index) })
        }
    }
}

@Composable
fun ExploreMediaGrid(onOpen: (Int) -> Unit) {
    val media = ExploreService.visibleMedia
    if (media.isEmpty()) {
        if (ExploreService.isLoading("media")) {
            Box(Modifier.fillMaxSize().padding(top = 80.dp), contentAlignment = Alignment.TopCenter) { CircularProgressIndicator(color = AppColors.textPrimary) }
        } else {
            val scope = rememberCoroutineScope()
            EmptyStateView(icon = Icons.Outlined.PhotoLibrary, title = L("exploreUnavailable"), actionTitle = L("retry"), modifier = Modifier.padding(top = 60.dp)) {
                scope.launch { ExploreService.loadMedia(force = true) }
            }
        }
        return
    }
    LazyVerticalGrid(columns = GridCells.Fixed(3), modifier = Modifier.fillMaxSize().testTag("explore-media-grid"), horizontalArrangement = Arrangement.spacedBy(2.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        itemsIndexed(media, key = { _, entry -> entry.id }) { index, entry ->
            ExploreMediaThumb(entry, Modifier.aspectRatio(1f).clickable { onOpen(index) })
        }
        if (!ExploreService.mediaExhausted) {
            item(span = { GridItemSpan(maxLineSpan) }, key = "media-more") {
                LaunchedEffect(media.size) { ExploreService.loadMoreMedia() }
                Box(Modifier.fillMaxWidth().padding(vertical = 24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(24.dp), color = AppColors.textPrimary) }
            }
        }
    }
}

@Composable
fun ExploreMediaViewer(entries: List<ExploreMediaEntry>, startIndex: Int, onDismiss: () -> Unit) {
    if (entries.isEmpty()) return
    val pager = rememberPagerState(initialPage = startIndex.coerceIn(0, entries.lastIndex)) { entries.size }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            HorizontalPager(state = pager, modifier = Modifier.fillMaxSize(), key = { entries[it].id }) { page ->
                val entry = entries[page]
                if (entry.isVideo) {
                    StreamPlayer(entry.url, Modifier.fillMaxSize(), playing = pager.currentPage == page)
                } else {
                    RemoteImage(entry.url, Modifier.fillMaxSize().background(Color.Black), contentScale = ContentScale.Fit)
                }
            }
            Row(Modifier.fillMaxWidth().padding(8.dp).align(Alignment.TopCenter)) {
                IconButton(onClick = onDismiss) { Icon(Icons.Outlined.Close, L("close"), tint = Color.White) }
                Spacer(Modifier.weight(1f))
                IconButton(onClick = {
                    val entry = entries.getOrNull(pager.currentPage) ?: return@IconButton
                    onDismiss()
                    Router.push(Route.Thread(entry.noteId))
                }) { Icon(Icons.AutoMirrored.Outlined.OpenInNew, L("searchOpenNote"), tint = Color.White) }
            }
        }
    }
}
