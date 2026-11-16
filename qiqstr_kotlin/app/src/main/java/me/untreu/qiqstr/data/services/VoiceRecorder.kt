package me.untreu.qiqstr.data.services

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaMetadataRetriever
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import java.io.File
import java.util.Locale
import java.util.UUID
import kotlin.math.ceil
import kotlin.math.roundToInt
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App

data class VoiceRecording(val path: String, val duration: Double, val waveform: List<Int>)

class VoiceRecorder {
    sealed interface State {
        object Idle : State
        object Recording : State
        data class Finished(val recording: VoiceRecording) : State
        object Denied : State
        object Failed : State
    }

    var state by mutableStateOf<State>(State.Idle)
        private set
    var elapsed by mutableDoubleStateOf(0.0)
        private set
    val levels = mutableStateListOf<Float>()
    private var recorder: MediaRecorder? = null
    private var file: File? = null
    private var meter: Job? = null
    private var startedAt = 0L

    val isRecording: Boolean get() = state == State.Recording

    fun deny() {
        state = State.Denied
    }

    fun start() {
        if (state == State.Recording) return
        if (!hasPermission) {
            state = State.Denied
            return
        }
        AudioPlayback.stop()
        val output = File(App.context.cacheDir, "voice-${UUID.randomUUID()}.m4a")
        @Suppress("DEPRECATION")
        val created = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(App.context) else MediaRecorder()
        try {
            created.setAudioSource(MediaRecorder.AudioSource.MIC)
            created.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            created.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            created.setAudioChannels(1)
            created.setAudioSamplingRate(44_100)
            created.setAudioEncodingBitRate(64_000)
            created.setMaxDuration((MAX_DURATION * 1000).toInt())
            created.setOutputFile(output.absolutePath)
            created.setOnInfoListener { _, what, _ -> if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED) finish() }
            created.prepare()
            created.start()
        } catch (_: Throwable) {
            runCatching { created.release() }
            output.delete()
            state = State.Failed
            return
        }
        recorder = created
        file = output
        levels.clear()
        elapsed = 0.0
        startedAt = SystemClock.elapsedRealtime()
        state = State.Recording
        meter = App.scope.launch {
            while (isActive) {
                delay(80)
                val active = recorder ?: return@launch
                val amplitude = runCatching { active.maxAmplitude }.getOrDefault(0)
                levels.add((amplitude / 32767f * GAIN).coerceIn(0f, 1f))
                elapsed = (SystemClock.elapsedRealtime() - startedAt) / 1000.0
            }
        }
    }

    fun stop() {
        if (state != State.Recording) return
        finish()
    }

    fun cancel() {
        meter?.cancel()
        meter = null
        recorder?.let { active ->
            runCatching { active.stop() }
            runCatching { active.release() }
        }
        file?.delete()
        (state as? State.Finished)?.let { File(it.recording.path).delete() }
        recorder = null
        file = null
        levels.clear()
        elapsed = 0.0
        state = State.Idle
    }

    private fun finish() {
        meter?.cancel()
        meter = null
        val active = recorder ?: return
        val output = file
        val measured = maxOf((SystemClock.elapsedRealtime() - startedAt) / 1000.0, elapsed)
        val stopped = runCatching { active.stop() }.isSuccess
        runCatching { active.release() }
        recorder = null
        file = null
        val duration = if (stopped && output != null) recordedDuration(output) ?: measured else 0.0
        if (output == null || duration < 0.5) {
            output?.delete()
            levels.clear()
            elapsed = 0.0
            state = State.Idle
            return
        }
        elapsed = duration
        state = State.Finished(VoiceRecording(output.absolutePath, duration, waveform(levels)))
    }

    private fun recordedDuration(file: File): Double? = runCatching {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()?.let { it / 1000.0 }
        } finally {
            runCatching { retriever.release() }
        }
    }.getOrNull()?.takeIf { it > 0 }

    companion object {
        const val MAX_DURATION = 300.0
        const val WAVEFORM_BARS = 48
        private const val GAIN = 1.4f

        val hasPermission: Boolean
            get() = ContextCompat.checkSelfPermission(App.context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

        fun waveform(levels: List<Float>, bars: Int = WAVEFORM_BARS): List<Int> {
            if (levels.isEmpty()) return emptyList()
            val bucket = maxOf(1, ceil(levels.size.toDouble() / bars).toInt())
            return levels.chunked(bucket).map { (it.max() * 100).roundToInt() }
        }

        fun format(seconds: Double): String {
            val total = maxOf(0L, Math.round(seconds))
            return String.format(Locale.US, "%d:%02d", total / 60, total % 60)
        }
    }
}

object AudioPlayback {
    var currentURL by mutableStateOf<String?>(null)
        private set
    var isPlaying by mutableStateOf(false)
        private set
    var progress by mutableDoubleStateOf(0.0)
        private set
    var duration by mutableDoubleStateOf(0.0)
        private set
    private var player: ExoPlayer? = null
    private var ticker: Job? = null

    fun isCurrent(url: String) = currentURL == url

    fun toggle(url: String) {
        val existing = player
        if (currentURL == url && existing != null) {
            if (isPlaying) existing.pause() else existing.play()
            isPlaying = !isPlaying
            return
        }
        stop()
        val uri = if (url.startsWith("/")) Uri.fromFile(File(url)) else runCatching { Uri.parse(url) }.getOrNull() ?: return
        val created = ExoPlayer.Builder(App.context).build()
        created.setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_SPEECH).build(), true)
        created.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED && player === created) stop()
            }

            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                if (player === created) isPlaying = playWhenReady
            }

            override fun onPlayerError(error: PlaybackException) {
                if (player === created) stop()
            }
        })
        created.setMediaItem(MediaItem.fromUri(uri))
        created.prepare()
        created.play()
        player = created
        currentURL = url
        progress = 0.0
        duration = 0.0
        isPlaying = true
        ticker = App.scope.launch {
            while (isActive) {
                delay(100)
                val total = created.duration
                if (total != C.TIME_UNSET && total > 0) {
                    duration = total / 1000.0
                    progress = (created.currentPosition.toDouble() / total).coerceIn(0.0, 1.0)
                }
            }
        }
    }

    fun seek(url: String, fraction: Double) {
        val existing = player ?: return
        if (currentURL != url || duration <= 0) return
        val clamped = fraction.coerceIn(0.0, 1.0)
        existing.seekTo((duration * clamped * 1000).toLong())
        progress = clamped
    }

    fun stop() {
        ticker?.cancel()
        ticker = null
        player?.release()
        player = null
        currentURL = null
        isPlaying = false
        progress = 0.0
        duration = 0.0
    }
}
