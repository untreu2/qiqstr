package me.untreu.qiqstr.app

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Modifier
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.ui.articles.ArticleDetailScreen
import me.untreu.qiqstr.ui.auth.FollowPackScreen
import me.untreu.qiqstr.ui.auth.SuggestedFollowsScreen
import me.untreu.qiqstr.ui.bookmarks.BookmarksScreen
import me.untreu.qiqstr.ui.dm.DMChatScreen
import me.untreu.qiqstr.ui.dm.DMConversationsScreen
import me.untreu.qiqstr.ui.explore.DiscoverFeedScreen
import me.untreu.qiqstr.ui.explore.DiscoverFeedsScreen
import me.untreu.qiqstr.ui.explore.ExploreScreen
import me.untreu.qiqstr.ui.explore.SearchScreen
import me.untreu.qiqstr.ui.explore.UserSearchScreen
import me.untreu.qiqstr.ui.feed.FeedScreen
import me.untreu.qiqstr.ui.feed.HashtagFeedScreen
import me.untreu.qiqstr.ui.followsets.FollowSetDetailScreen
import me.untreu.qiqstr.ui.followsets.FollowSetsScreen
import me.untreu.qiqstr.ui.live.LiveListScreen
import me.untreu.qiqstr.ui.live.LiveStreamScreen
import me.untreu.qiqstr.ui.notifications.NotificationsScreen
import me.untreu.qiqstr.ui.profile.EditProfileScreen
import me.untreu.qiqstr.ui.profile.FollowListScreen
import me.untreu.qiqstr.ui.profile.ProfileScreen
import me.untreu.qiqstr.ui.settings.SettingsPageScreen
import me.untreu.qiqstr.ui.settings.SettingsScreen
import me.untreu.qiqstr.ui.thread.NoteStatisticsScreen
import me.untreu.qiqstr.ui.thread.QuotesScreen
import me.untreu.qiqstr.ui.thread.ThreadScreen
import me.untreu.qiqstr.ui.wallet.ReceiveScreen
import me.untreu.qiqstr.ui.wallet.WalletScreen

@Composable
fun RouteDestination(route: Route) {
    when (route) {
        is Route.Profile -> ProfileScreen(route.pubkey)
        is Route.Thread -> ThreadScreen(route.noteId)
        is Route.Quotes -> QuotesScreen(route.noteId)
        is Route.NoteStatistics -> NoteStatisticsScreen(route.noteId)
        is Route.FollowList -> FollowListScreen(route.pubkey, route.mode)
        is Route.Hashtag -> HashtagFeedScreen(route.tag)
        is Route.Communities -> me.untreu.qiqstr.ui.communities.CommunitiesScreen(route.relay)
        is Route.RelayGroup -> me.untreu.qiqstr.ui.communities.CommunityChatScreen(route.id)
        is Route.PublicChannel -> me.untreu.qiqstr.ui.communities.CommunityChatScreen(route.id, channel = true)
        is Route.Community -> me.untreu.qiqstr.ui.communities.CommunityScreen(route.coordinate)
        Route.Reads -> ExploreScreen()
        is Route.Article -> ArticleDetailScreen(articleId = route.articleId)
        is Route.ArticleAddress -> ArticleDetailScreen(naddr = route.naddr)
        is Route.ArticleEditor -> me.untreu.qiqstr.ui.articles.ArticleEditorScreen(route.draftId)
        Route.ArticleDrafts -> me.untreu.qiqstr.ui.articles.ArticleDraftsScreen()
        Route.EditProfile -> EditProfileScreen()
        Route.Settings -> SettingsScreen()
        is Route.SettingsPage -> SettingsPageScreen(route.page)
        Route.Bookmarks -> BookmarksScreen()
        Route.FollowSets -> FollowSetsScreen()
        is Route.FollowSet -> FollowSetDetailScreen(route.setId)
        is Route.DMChat -> DMChatScreen(route.pubkey)
        Route.WalletReceive -> ReceiveScreen()
        Route.UserSearch -> UserSearchScreen()
        Route.SuggestedFollows -> SuggestedFollowsScreen(onFinish = null)
        Route.LiveStreams -> LiveListScreen()
        is Route.LiveStream -> LiveStreamScreen(route.coordinate)
        Route.DiscoverFeeds -> DiscoverFeedsScreen()
        is Route.DiscoverFeed -> DiscoverFeedScreen(route.feedId)
        is Route.FollowPack -> FollowPackScreen(route.packId)
    }
}

@Composable
fun TabRoot(tab: AppTab) {
    when (tab) {
        AppTab.FEED -> FeedScreen()
        AppTab.DM -> DMConversationsScreen()
        AppTab.WALLET -> WalletScreen()
        AppTab.NOTIFICATIONS -> NotificationsScreen()
        AppTab.SEARCH -> SearchScreen()
    }
}

private class EntryOwner(override val viewModelStore: ViewModelStore) : ViewModelStoreOwner

@Composable
fun TabNavHost(tab: AppTab, modifier: Modifier = Modifier) {
    val stack = Router.stack(tab)
    val holder = rememberSaveableStateHolder()
    val rootStore = remember(tab) { ViewModelStore() }
    BackHandler(enabled = stack.isNotEmpty()) { Router.pop() }
    val top = stack.lastOrNull()
    AnimatedContent(
        targetState = top,
        transitionSpec = {
            val forward = (targetState?.id ?: 0) > (initialState?.id ?: 0)
            if (forward) {
                (slideInHorizontally(tween(260)) { it / 3 } + fadeIn(tween(200))) togetherWith fadeOut(tween(160))
            } else {
                fadeIn(tween(200)) togetherWith (slideOutHorizontally(tween(260)) { it / 3 } + fadeOut(tween(200)))
            }
        },
        contentKey = { it?.id ?: -1L },
        modifier = modifier.fillMaxSize(),
        label = "nav-$tab",
    ) { entry ->
        Box(Modifier.fillMaxSize().background(AppColors.background)) {
            val owner = remember(entry?.id) { EntryOwner(entry?.viewModelStore ?: rootStore) }
            holder.SaveableStateProvider(entry?.id?.toString() ?: "root-$tab") {
                CompositionLocalProvider(LocalViewModelStoreOwner provides owner) {
                    if (entry == null) TabRoot(tab) else RouteDestination(entry.route)
                }
            }
        }
    }
}
