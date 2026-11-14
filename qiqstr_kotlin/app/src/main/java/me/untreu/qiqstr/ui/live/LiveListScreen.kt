package me.untreu.qiqstr.ui.live

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Sensors
import androidx.compose.material.icons.outlined.Share
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.data.services.LiveService
import me.untreu.qiqstr.data.services.LiveSnapshot
import me.untreu.qiqstr.data.services.LiveStream
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.ui.explore.ExploreLargeScaffold
import me.untreu.qiqstr.ui.explore.LongPressMenuBox
import me.untreu.qiqstr.ui.explore.MenuAction
import me.untreu.qiqstr.ui.explore.PaddedBox
import me.untreu.qiqstr.ui.explore.RefreshBox
import me.untreu.qiqstr.ui.explore.SearchSectionHeader

class LiveListViewModel : ViewModel() {
    var loaded by mutableStateOf(false)
        private set

    val snapshot: LiveSnapshot get() = LiveService.snapshot
    val isLoading: Boolean get() = LiveService.isLoading && snapshot.isEmpty

    suspend fun load(force: Boolean = false) {
        LiveService.load(force)
        loaded = true
    }

    suspend fun refreshProfiles() {
        val hosts = (snapshot.live + snapshot.recordings).map { it.host }
        ProfileCache.load(hosts, fetchMissing = false)
    }
}

fun shareText(context: Context, text: String) {
    val intent = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    runCatching { context.startActivity(Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

@Composable
fun LiveListScreen() {
    val model: LiveListViewModel = viewModel()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    LaunchedEffect(Unit) { model.load() }
    LaunchedEffect(DataBus.profileVersion) { model.refreshProfiles() }
    ExploreLargeScaffold(title = L("liveTitle"), modifier = Modifier.testTag("live-list")) { padding ->
        PaddedBox(padding) {
            RefreshBox(onRefresh = { model.load(force = true) }) {
                LazyColumn(Modifier.fillMaxSize()) {
                    if (model.isLoading) {
                        items(3, key = { "live-skeleton-$it" }) { LiveCardSkeleton() }
                    } else {
                        streamSection(L("liveFollowing"), model.snapshot.following, "live-following", context)
                        streamSection(L("livePopular"), model.snapshot.popular, "live-popular", context)
                        streamSection(L("liveRecordings"), model.snapshot.recordings, "live-recordings", context)
                    }
                }
                if (model.loaded && !model.isLoading && model.snapshot.isEmpty) {
                    EmptyStateView(
                        icon = Icons.Outlined.Sensors,
                        title = L("liveEmptyTitle"),
                        message = L("liveEmptyMessage"),
                        actionTitle = L("retry"),
                        modifier = Modifier.align(Alignment.Center),
                    ) { scope.launch { model.load(force = true) } }
                }
            }
        }
    }
}

private fun LazyListScope.streamSection(title: String, streams: List<LiveStream>, identifier: String, context: Context) {
    if (streams.isEmpty()) return
    item(key = "$identifier-header") { SearchSectionHeader(title) }
    items(streams, key = { "$identifier-${it.coordinate}" }) { stream ->
        LongPressMenuBox(
            onClick = { Router.push(Route.LiveStream(stream.coordinate)) },
            modifier = Modifier.testTag(identifier),
            menu = { dismiss ->
                stream.naddr?.let { naddr ->
                    MenuAction(L("share"), Icons.Outlined.Share) {
                        dismiss()
                        shareText(context, "nostr:$naddr")
                    }
                }
                MenuAction(L("exploreOpenProfile"), Icons.Outlined.Person) {
                    dismiss()
                    Router.push(Route.Profile(stream.host))
                }
            },
        ) {
            LiveStreamCard(stream, Modifier.padding(horizontal = 16.dp, vertical = 10.dp))
        }
    }
}

@Composable
fun LiveCardSkeleton() {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(14.dp)).background(AppColors.tile))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(36.dp).clip(CircleShape).background(AppColors.tile))
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.width(180.dp).height(14.dp).clip(RoundedCornerShape(4.dp)).background(AppColors.tile))
                Box(Modifier.width(100.dp).height(12.dp).clip(RoundedCornerShape(4.dp)).background(AppColors.tile))
            }
        }
    }
}
