package me.untreu.qiqstr.ui.articles

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Article
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.RemoteImage
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Profile

@Composable
fun ContinueReadingSection(modifier: Modifier = Modifier, limit: Int = 3) {
    val entries = ReadingProgressStore.continueReading(limit)
    if (entries.isEmpty()) return
    Column(modifier.fillMaxWidth().testTag("continue-reading-section")) {
        Text(
            L("articleContinueReading"),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = AppColors.textPrimary,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
        entries.forEach { entry ->
            key(entry.key) {
                val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
                    if (value == SwipeToDismissBoxValue.EndToStart) {
                        ReadingProgressStore.remove(entry)
                        true
                    } else {
                        false
                    }
                })
                SwipeToDismissBox(
                    state = state,
                    enableDismissFromStartToEnd = false,
                    backgroundContent = {
                        Box(Modifier.fillMaxSize().background(AppColors.error).padding(horizontal = 20.dp), contentAlignment = Alignment.CenterEnd) {
                            Icon(Icons.Outlined.Close, L("articleRemoveFromContinue"), tint = androidx.compose.ui.graphics.Color.White)
                        }
                    },
                ) {
                    ContinueReadingRow(entry, Modifier.background(AppColors.background))
                }
            }
        }
    }
}

@Composable
fun ContinueReadingRow(entry: ReadingProgressEntry, modifier: Modifier = Modifier) {
    val authorName = ProfileCache.profiles[entry.authorPubkey]?.bestName ?: entry.authorName ?: Profile.shortNpub(entry.authorPubkey)
    val percent = L("articlePercentRead", "percent" to (entry.progress * 100).roundToInt())
    Row(
        modifier
            .fillMaxWidth()
            .clickable {
                val naddr = entry.naddr
                if (naddr != null) Router.push(Route.ArticleAddress(naddr)) else Router.push(Route.Article(entry.articleId))
            }
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .semantics { stateDescription = percent }
            .testTag("continue-reading-${entry.articleId}"),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val thumb = Modifier.size(56.dp).clip(RoundedCornerShape(12.dp))
        if (entry.image != null) {
            RemoteImage(entry.image, thumb)
        } else {
            Box(thumb.background(AppColors.tile), contentAlignment = Alignment.Center) {
                Icon(Icons.Outlined.Article, null, tint = AppColors.textSecondary)
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(entry.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(
                "$authorName · ${L("articleMinutesLeft", "count" to entry.minutesLeft)}",
                style = MaterialTheme.typography.bodyMedium,
                color = AppColors.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            LinearProgressIndicator(
                progress = { entry.progress.toFloat() },
                modifier = Modifier.fillMaxWidth().padding(top = 2.dp).semantics { contentDescription = "" },
                color = AppColors.textPrimary,
                trackColor = AppColors.tile,
            )
        }
    }
}
