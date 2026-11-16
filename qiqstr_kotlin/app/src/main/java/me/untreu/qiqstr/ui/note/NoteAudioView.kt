package me.untreu.qiqstr.ui.note

import android.net.Uri
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlin.math.abs
import kotlin.math.sin
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.data.services.AudioPlayback
import me.untreu.qiqstr.data.services.VoiceRecorder

@Immutable
data class NoteAudioItem(val url: String, val duration: Double?, val waveform: List<Int>) {
    val id: String get() = url

    companion object {
        val extensions = listOf("m4a", "mp3", "aac", "ogg", "oga", "opus", "wav", "flac")

        fun isAudio(url: String, mimeType: String?): Boolean {
            if (mimeType != null) return mimeType.startsWith("audio/")
            val name = runCatching { Uri.parse(url).lastPathSegment }.getOrNull() ?: return false
            val dot = name.lastIndexOf('.')
            if (dot <= 0) return false
            return name.substring(dot + 1).lowercase() in extensions
        }
    }
}

@Composable
fun AudioPlayerView(
    url: String,
    modifier: Modifier = Modifier,
    duration: Double? = null,
    waveform: List<Int> = emptyList(),
    tint: Color = AppColors.textPrimary,
    playbackKey: String = url,
) {
    val isCurrent = AudioPlayback.isCurrent(playbackKey)
    val isPlaying = isCurrent && AudioPlayback.isPlaying
    val progress = if (isCurrent) AudioPlayback.progress else 0.0
    val total = if (isCurrent && AudioPlayback.duration > 0) AudioPlayback.duration else duration
    val label = if (isPlaying) L("voicePause") else L("voicePlay")
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Surface(
            onClick = { AudioPlayback.toggle(url, playbackKey) },
            shape = CircleShape,
            color = tint,
            contentColor = if (tint == AppColors.textPrimary) AppColors.background else AppColors.textPrimary,
            modifier = Modifier.size(40.dp).semantics { contentDescription = label }.testTag("audio-play"),
        ) {
            Box(contentAlignment = Alignment.Center) { Icon(if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow, null) }
        }
        WaveformBars(
            levels = waveform,
            progress = progress,
            tint = tint,
            modifier = Modifier.weight(1f).height(32.dp)
                .pointerInput(playbackKey) { detectTapGestures { AudioPlayback.seek(playbackKey, it.x.toDouble() / maxOf(1, size.width)) } }
                .pointerInput(playbackKey) {
                    var position = 0f
                    detectHorizontalDragGestures(
                        onDragStart = { position = it.x },
                        onDragEnd = { AudioPlayback.seek(playbackKey, position.toDouble() / maxOf(1, size.width)) },
                    ) { change, _ -> position = change.position.x }
                },
        )
        Text(
            VoiceRecorder.format(if (isCurrent) progress * (total ?: 0.0) else total ?: 0.0),
            style = MaterialTheme.typography.bodySmall.copy(fontFeatureSettings = "tnum"),
            color = AppColors.textSecondary,
            maxLines = 1,
        )
    }
}

private val placeholderBars = (0 until 40).map { 28 + (42 * abs(sin(it * 0.55))).toInt() }

@Composable
fun WaveformBars(levels: List<Int>, modifier: Modifier = Modifier, progress: Double = 0.0, tint: Color = AppColors.textPrimary) {
    val bars = levels.ifEmpty { placeholderBars }
    Canvas(modifier.clearAndSetSemantics {}) {
        if (size.width <= 0f || size.height <= 0f) return@Canvas
        val count = maxOf(1, minOf(bars.size, (size.width / 4.dp.toPx()).toInt()))
        val step = bars.size.toDouble() / count
        val gap = 2.dp.toPx()
        val width = maxOf(1f, (size.width - gap * (count - 1)) / count)
        for (index in 0 until count) {
            val level = bars[minOf(bars.size - 1, (index * step).toInt())]
            val height = maxOf(3.dp.toPx(), size.height * level.coerceIn(6, 100) / 100f)
            drawRoundRect(
                color = if (index.toDouble() / count < progress) tint else tint.copy(alpha = 0.28f),
                topLeft = Offset(index * (width + gap), (size.height - height) / 2f),
                size = Size(width, height),
                cornerRadius = CornerRadius(width / 2f),
            )
        }
    }
}

@Composable
fun NoteAudioView(item: NoteAudioItem, modifier: Modifier = Modifier) {
    AudioPlayerView(
        url = item.url,
        duration = item.duration,
        waveform = item.waveform,
        modifier = modifier.widthIn(max = 420.dp).fillMaxWidth()
            .clip(RoundedCornerShape(16.dp)).background(AppColors.inputFill)
            .padding(horizontal = 12.dp, vertical = 10.dp)
            .testTag("note-audio"),
    )
}
