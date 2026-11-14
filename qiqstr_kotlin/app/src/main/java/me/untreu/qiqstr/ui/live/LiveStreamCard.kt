package me.untreu.qiqstr.ui.live

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Sensors
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.RemoteImage
import me.untreu.qiqstr.data.services.LiveStream
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Profile

@Composable
private fun OverlayPill(text: String, background: Color, icon: androidx.compose.ui.graphics.vector.ImageVector? = null) {
    Row(
        Modifier.clip(CircleShape).background(background).padding(horizontal = 7.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        if (icon != null) Icon(icon, null, Modifier.size(12.dp), tint = Color.White)
        Text(text, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = Color.White, maxLines = 1)
    }
}

@Composable
fun LivePill() = OverlayPill(L("liveBadge"), Color(0xFFE53935))

@Composable
fun LiveReplayPill() = OverlayPill(L("liveReplay"), Color.Black.copy(alpha = 0.6f), Icons.Filled.PlayArrow)

@Composable
fun LiveViewerCount(count: Long) = OverlayPill(L("liveWatching", "count" to Sats.compact(count)), Color.Black.copy(alpha = 0.55f), Icons.Outlined.Visibility)

@Composable
fun LiveThumbnail(stream: LiveStream, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(14.dp)).background(AppColors.tile)) {
        if (stream.image != null) {
            RemoteImage(stream.image, Modifier.fillMaxSize())
        } else {
            Icon(Icons.Outlined.Sensors, null, Modifier.align(Alignment.Center).size(32.dp), tint = AppColors.textSecondary)
        }
        Box(Modifier.align(Alignment.TopStart).padding(8.dp)) {
            if (stream.isLive) LivePill() else if (stream.canReplay) LiveReplayPill()
        }
        val viewers = stream.participants
        if (stream.isLive && viewers != null && viewers > 0) {
            Box(Modifier.align(Alignment.TopEnd).padding(8.dp)) { LiveViewerCount(viewers) }
        }
    }
}

fun liveHostName(pubkey: String): String = ProfileCache.profiles[pubkey]?.bestName?.ifEmpty { null } ?: Profile.shortNpub(pubkey)

@Composable
fun LiveStreamCard(stream: LiveStream, modifier: Modifier = Modifier, compact: Boolean = false) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        LiveThumbnail(stream)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ProfileAvatar(stream.host, size = if (compact) 28.dp else 36.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    stream.title.ifEmpty { L("liveUntitled") },
                    style = if (compact) MaterialTheme.typography.titleSmall else MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                val time = if (stream.isLive) L("liveStarted", "time" to TimeFormat.relative(stream.startedAt)) else TimeFormat.relative(stream.startedAt)
                Text(
                    "${liveHostName(stream.host)} · $time",
                    style = if (compact) MaterialTheme.typography.bodySmall else MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (!compact && stream.summary.isNotEmpty()) {
                    Text(stream.summary, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}
