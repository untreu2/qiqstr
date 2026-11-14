package me.untreu.qiqstr.ui.live

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.data.services.LiveService
import me.untreu.qiqstr.ui.explore.SearchSectionHeader

object LiveNowSectionModel {
    val streams get() = LiveService.snapshot.live.take(10)

    suspend fun load(force: Boolean = false) {
        LiveService.load(force)
    }
}

fun LazyListScope.liveNowSection() {
    val streams = LiveNowSectionModel.streams
    if (streams.isEmpty()) return
    item(key = "live-now-header") { SearchSectionHeader(L("liveNow")) { Router.push(Route.LiveStreams) } }
    item(key = "live-now") {
        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.Top,
            modifier = Modifier.testTag("search-live-now"),
        ) {
            items(streams, key = { it.coordinate }) { stream ->
                LiveStreamCard(
                    stream,
                    compact = true,
                    modifier = Modifier.width(250.dp)
                        .clickable { Router.push(Route.LiveStream(stream.coordinate)) }
                        .testTag("search-live-${stream.identifier}"),
                )
            }
        }
    }
}
