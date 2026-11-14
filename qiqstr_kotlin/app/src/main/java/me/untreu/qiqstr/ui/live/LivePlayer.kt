package me.untreu.qiqstr.ui.live

import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.L

@OptIn(UnstableApi::class)
@Composable
fun StreamPlayer(url: String, modifier: Modifier = Modifier, playing: Boolean = true) {
    val context = LocalContext.current
    var failed by remember(url) { mutableStateOf(false) }
    val player = remember(url) {
        val item = MediaItem.Builder().setUri(url).apply {
            if (url.substringBefore('?').lowercase().endsWith(".m3u8")) setMimeType(MimeTypes.APPLICATION_M3U8)
        }.build()
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(item)
            prepare()
        }
    }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                failed = true
            }
        }
        player.addListener(listener)
        onDispose {
            player.removeListener(listener)
            player.release()
        }
    }
    LaunchedEffect(player, playing) { player.playWhenReady = playing }
    Box(modifier.background(Color.Black)) {
        if (failed) {
            Column(
                Modifier.fillMaxSize().padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
            ) {
                Icon(Icons.Outlined.ErrorOutline, null, tint = Color.White)
                TextButton(onClick = { Router.openUrl(url) }) {
                    Text(L("exploreOpenInBrowser"), color = Color.White, style = MaterialTheme.typography.labelLarge, textAlign = TextAlign.Center)
                }
            }
        } else {
            AndroidView(
                factory = { PlayerView(it).apply { this.player = player; useController = true } },
                update = { it.player = player },
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}
