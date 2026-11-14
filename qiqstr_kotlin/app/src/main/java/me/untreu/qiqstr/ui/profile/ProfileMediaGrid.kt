package me.untreu.qiqstr.ui.profile

import android.view.ViewGroup
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.OpenInFull
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import coil3.compose.AsyncImage
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L

fun LazyListScope.profileMediaGrid(entries: List<ProfileMediaEntry>, onOpen: (Int) -> Unit) {
    val rows = entries.withIndex().chunked(3)
    items(rows.size, key = { "media-row-${rows[it].first().value.id}" }) { rowIndex ->
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 2.dp).padding(bottom = 2.dp).testTag("profile-photos"),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            val row = rows[rowIndex]
            row.forEach { (index, entry) -> ProfileMediaTile(entry, Modifier.weight(1f)) { onOpen(index) } }
            repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ProfileMediaTile(entry: ProfileMediaEntry, modifier: Modifier, onOpen: () -> Unit) {
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    var menu by remember { mutableStateOf(false) }
    val label = entry.alt ?: L(if (entry.isVideo) "videoTapToPlay" else "profileViewImage")
    Box(
        modifier.aspectRatio(1f).background(AppColors.tile)
            .combinedClickable(onClick = onOpen, onLongClick = { haptics.performHapticFeedback(HapticFeedbackType.LongPress); menu = true })
            .semantics { contentDescription = label }
            .testTag("profile-photo-tile"),
    ) {
        AsyncImage(
            model = if (entry.isVideo) entry.poster ?: entry.url else entry.url,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        if (entry.isVideo) {
            Icon(
                Icons.Filled.PlayArrow,
                null,
                tint = Color.White,
                modifier = Modifier.align(Alignment.TopEnd).padding(6.dp).size(18.dp),
            )
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(
                text = { Text(label) },
                leadingIcon = { Icon(Icons.Outlined.OpenInFull, null) },
                onClick = { menu = false; onOpen() },
            )
            DropdownMenuItem(
                text = { Text(L("profileOpenNote")) },
                leadingIcon = { Icon(Icons.AutoMirrored.Outlined.Chat, null) },
                onClick = { menu = false; Router.push(Route.Thread(entry.noteId)) },
            )
            DropdownMenuItem(
                text = { Text(L("share")) },
                leadingIcon = { Icon(Icons.Outlined.Share, null) },
                onClick = { menu = false; ProfileSharing.share(context, entry.url) },
            )
        }
    }
}

@Composable
fun ProfileMediaPager(entries: List<ProfileMediaEntry>, startIndex: Int, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val pager = rememberPagerState(initialPage = startIndex.coerceIn(0, (entries.size - 1).coerceAtLeast(0))) { entries.size }
    val haptics = LocalHapticFeedback.current
    var chromeVisible by remember { mutableStateOf(true) }
    LaunchedEffect(pager.currentPage) { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove) }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black).testTag("profile-media-pager")) {
            HorizontalPager(pager, Modifier.fillMaxSize(), key = { entries[it].id }) { page ->
                val entry = entries[page]
                if (entry.isVideo) {
                    ProfileMediaVideoPage(entry.url, isCurrent = page == pager.currentPage)
                } else {
                    ZoomableImage(entry.url, Modifier.fillMaxSize(), onTap = { chromeVisible = !chromeVisible }, onDismiss = onDismiss)
                }
            }
            if (chromeVisible) {
                val current = entries.getOrNull(pager.currentPage)
                val chromeColors = IconButtonDefaults.filledTonalIconButtonColors(containerColor = Color.White.copy(alpha = 0.16f), contentColor = Color.White)
                Row(
                    Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    FilledTonalIconButton(onClick = onDismiss, colors = chromeColors, modifier = Modifier.testTag("profile-media-close")) {
                        Icon(Icons.Outlined.Close, L("closeDialog"))
                    }
                    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                        if (entries.size > 1) {
                            Surface(shape = CircleShape, color = Color.White.copy(alpha = 0.16f), contentColor = Color.White) {
                                Text(
                                    "${pager.currentPage + 1} / ${entries.size}",
                                    style = MaterialTheme.typography.labelLarge.copy(shadow = Shadow(Color.Black.copy(alpha = 0.4f))),
                                    fontWeight = FontWeight.SemiBold,
                                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
                                )
                            }
                        }
                    }
                    if (current != null) {
                        FilledTonalIconButton(
                            onClick = { ProfileSharing.share(context, current.url) },
                            colors = chromeColors,
                            modifier = Modifier.testTag("profile-media-share"),
                        ) { Icon(Icons.Outlined.Share, L("share")) }
                    }
                }
                if (current != null) {
                    FilledTonalButton(
                        onClick = {
                            onDismiss()
                            Router.push(Route.Thread(current.noteId))
                        },
                        colors = ButtonDefaults.filledTonalButtonColors(containerColor = Color.White.copy(alpha = 0.16f), contentColor = Color.White),
                        modifier = Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 12.dp).testTag("profile-media-open-note"),
                    ) {
                        Icon(Icons.AutoMirrored.Outlined.Chat, null, Modifier.size(18.dp))
                        Spacer(Modifier.size(8.dp))
                        Text(L("profileOpenNote"), fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
}

@Composable
private fun ProfileMediaVideoPage(url: String, isCurrent: Boolean) {
    val context = LocalContext.current
    val player = remember(url) {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(url))
            prepare()
        }
    }
    LaunchedEffect(isCurrent) { if (isCurrent) player.play() else player.pause() }
    DisposableEffect(player) { onDispose { player.release() } }
    Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    this.player = player
                    setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)
                }
            },
            modifier = Modifier.fillMaxSize(),
        )
    }
}
