package me.untreu.qiqstr.ui.live

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.annotation.OptIn
import androidx.compose.runtime.*
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.data.services.LiveStream
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Profile

@OptIn(UnstableApi::class)
object LivePlayback {
    var player by mutableStateOf<MediaController?>(null)
        private set
    var failed by mutableStateOf(false)
        private set
    var isPlaying by mutableStateOf(false)
        private set
    private var connection: ListenableFuture<MediaController>? = null
    private var currentStream: LiveStream? = null
    private var url: String? = null
    private var generation = 0
    private val listener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) { LivePlayback.isPlaying = isPlaying }
        override fun onPlayerError(error: PlaybackException) { failed = true }
    }
    fun owns(coordinate: String) = currentStream?.coordinate == coordinate
    fun play(stream: LiveStream, url: String) {
        currentStream = stream
        val changed = this.url != url || player?.currentMediaItem?.mediaId != stream.coordinate
        this.url = url
        failed = false
        player?.let { controller ->
            if (changed) { controller.setMediaItem(item(stream, url)); controller.prepare() } else update(stream)
            controller.play()
            return
        }
        if (connection != null) return
        val gen = generation
        val future = MediaController.Builder(App.context, SessionToken(App.context, ComponentName(App.context, LivePlaybackService::class.java))).buildAsync()
        connection = future
        future.addListener({
            if (gen == generation && connection === future) {
                connection = null
                runCatching { future.get() }.onSuccess { controller ->
                    player = controller
                    controller.addListener(listener)
                    val latest = currentStream
                    val source = this.url
                    if (latest != null && source != null) {
                        controller.setMediaItem(item(latest, source)); controller.prepare(); controller.play()
                    }
                }.onFailure { failed = true }
            }
        }, ContextCompat.getMainExecutor(App.context))
    }
    fun update(stream: LiveStream) {
        if (!owns(stream.coordinate)) return
        currentStream = stream
        val controller = player ?: return
        val source = url ?: return
        if (controller.mediaItemCount > 0) controller.replaceMediaItem(0, item(stream, source))
    }
    fun resume() { player?.play() }
    fun pause() { player?.pause() }
    fun stop(coordinate: String? = null) {
        if (coordinate != null && !owns(coordinate)) return
        generation++
        connection?.let(MediaController::releaseFuture)
        connection = null
        player?.let { it.removeListener(listener); it.stop(); it.clearMediaItems(); it.release() }
        player = null; currentStream = null; url = null; isPlaying = false; failed = false
        App.context.stopService(Intent(App.context, LivePlaybackService::class.java))
    }
    private fun item(stream: LiveStream, url: String): MediaItem {
        val metadata = MediaMetadata.Builder().setTitle(stream.title.ifEmpty { L("liveTitle") })
            .setArtist(ProfileCache.profile(stream.host)?.bestName ?: Profile.shortNpub(stream.host))
            .setArtworkUri(stream.image?.let(Uri::parse))
            .setExtras(Bundle().apply { putString("naddr", stream.naddr) }).build()
        return MediaItem.Builder().setMediaId(stream.coordinate).setUri(url).setMediaMetadata(metadata).apply {
            if (url.substringBefore('?').lowercase().endsWith(".m3u8")) setMimeType(MimeTypes.APPLICATION_M3U8)
        }.build()
    }
}
