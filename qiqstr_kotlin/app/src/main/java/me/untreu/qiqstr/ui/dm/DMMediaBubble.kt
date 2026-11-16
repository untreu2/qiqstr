package me.untreu.qiqstr.ui.dm

import androidx.annotation.OptIn
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateOffsetAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.InsertDriveFile
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.NoEncryption
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import coil3.compose.AsyncImage
import java.io.File
import kotlin.math.abs
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.RemoteImage

private sealed interface MediaPhase {
    object Loading : MediaPhase
    data class Image(val file: File, val ratio: Float) : MediaPhase
    data class Video(val file: File?) : MediaPhase
    data class FileReady(val file: File) : MediaPhase
    data class Failed(val reason: String) : MediaPhase
}

@Composable
fun DMMediaBubble(message: DMMessage, shape: Shape, openMenu: () -> Unit) {
    val file = message.file
    val mine = message.isMine
    val foreground = if (mine) AppColors.background else AppColors.textPrimary
    val secondary = if (mine) AppColors.background.copy(alpha = 0.7f) else AppColors.textSecondary
    val fill = if (mine) AppColors.textPrimary else AppColors.tile
    var phase by remember(message.id) { mutableStateOf<MediaPhase>(MediaPhase.Loading) }
    var isOpeningVideo by remember { mutableStateOf(false) }
    var viewerImage by remember { mutableStateOf<File?>(null) }
    var videoFile by remember { mutableStateOf<File?>(null) }
    var reloadToken by remember { mutableStateOf(0) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(message.id, reloadToken) {
        if (file == null || !file.isEncrypted) return@LaunchedEffect
        if (reloadToken == 0 && phase != MediaPhase.Loading) return@LaunchedEffect
        phase = MediaPhase.Loading
        if (file.isVideo) {
            phase = MediaPhase.Video(null)
            return@LaunchedEffect
        }
        phase = try {
            val decrypted = DMService.decryptedFile(message)
            if (file.isImage) {
                val size = withContext(Dispatchers.IO) { DMMediaPrep.imageSize(decrypted) }
                if (size != null) MediaPhase.Image(decrypted, size.second.toFloat() / size.first.coerceAtLeast(1)) else MediaPhase.FileReady(decrypted)
            } else {
                MediaPhase.FileReady(decrypted)
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            MediaPhase.Failed(DMService.errorMessage(error))
        }
    }

    val longPress = Modifier.pointerInput(message.id) { detectTapGestures(onLongPress = { openMenu() }) }

    if (file?.isEncrypted == false) {
        if (file.isImage || DMText.isImageURL(message.content)) {
            RemoteImage(message.content, Modifier.size(240.dp).clip(shape).then(longPress), contentScale = ContentScale.Crop)
        } else {
            Placeholder(100.dp, shape, fill, longPress) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Outlined.WarningAmber, null, tint = secondary)
                    Text(L("legacyUnencryptedMedia"), style = MaterialTheme.typography.labelSmall, color = secondary)
                }
            }
        }
        return
    }

    when (val current = phase) {
        MediaPhase.Loading -> Placeholder(if (file?.isVideo == true) 160.dp else 220.dp, shape, fill, longPress) {
            CircularProgressIndicator(Modifier.size(24.dp), color = secondary, strokeWidth = 2.dp)
        }
        is MediaPhase.Image -> {
            val height = (240f * current.ratio).coerceIn(120f, 340f).dp
            AsyncImage(
                model = current.file,
                contentDescription = L("dmSpokenPhoto", "sender" to message.spokenSender),
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .size(240.dp, height)
                    .clip(shape)
                    .background(fill)
                    .pointerInput(current.file) { detectTapGestures(onTap = { viewerImage = current.file }, onLongPress = { openMenu() }) }
                    .testTag("dm-media-image"),
            )
        }
        is MediaPhase.Video -> {
            val open: () -> Unit = {
                val cached = current.file
                if (cached != null) {
                    videoFile = cached
                } else if (!isOpeningVideo) {
                    isOpeningVideo = true
                    scope.launch {
                        try {
                            val decrypted = DMService.decryptedFile(message)
                            phase = MediaPhase.Video(decrypted)
                            videoFile = decrypted
                        } catch (error: CancellationException) {
                            throw error
                        } catch (error: Throwable) {
                            phase = MediaPhase.Failed(DMService.errorMessage(error))
                        } finally {
                            isOpeningVideo = false
                        }
                    }
                }
            }
            Placeholder(
                160.dp,
                shape,
                fill,
                Modifier
                    .pointerInput(message.id) { detectTapGestures(onTap = { open() }, onLongPress = { openMenu() }) }
                    .semantics { contentDescription = L("dmSpokenVideo", "sender" to message.spokenSender) }
                    .testTag("dm-media-video"),
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.size(56.dp).background(foreground.copy(alpha = 0.15f), CircleShape), contentAlignment = Alignment.Center) {
                        if (isOpeningVideo) {
                            CircularProgressIndicator(Modifier.size(22.dp), color = foreground, strokeWidth = 2.dp)
                        } else {
                            Icon(Icons.Filled.PlayArrow, null, Modifier.size(30.dp), tint = foreground)
                        }
                    }
                    Text(L("videoTapToPlay"), style = MaterialTheme.typography.bodySmall, color = secondary)
                }
            }
        }
        is MediaPhase.FileReady -> if (message.file?.isAudio == true) {
            me.untreu.qiqstr.ui.note.AudioPlayerView(
                url = current.file.path, duration = message.file.duration, waveform = message.file.waveform,
                tint = foreground, playbackKey = message.id,
                modifier = Modifier.width(260.dp).clip(shape).background(fill).then(longPress).padding(horizontal = 12.dp, vertical = 10.dp).testTag("dm-media-audio"),
            )
        } else Row(
            Modifier.clip(shape).background(fill).then(longPress).padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Icon(Icons.Filled.InsertDriveFile, null, tint = foreground)
            Text(L("fileType", "type" to current.file.extension.uppercase()), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = foreground)
        }
        is MediaPhase.Failed -> Placeholder(
            120.dp,
            shape,
            fill,
            Modifier.pointerInput(message.id) { detectTapGestures(onTap = { reloadToken += 1 }, onLongPress = { openMenu() }) },
        ) {
            Column(Modifier.padding(horizontal = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Outlined.NoEncryption, null, tint = secondary)
                Text(L("failedToDecryptMedia"), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = secondary)
                Text(current.reason, style = MaterialTheme.typography.labelSmall, color = secondary, maxLines = 2, textAlign = TextAlign.Center)
            }
        }
    }

    viewerImage?.let { DMImageViewer(it) { viewerImage = null } }
    videoFile?.let { DMVideoPlayer(it) { videoFile = null } }
}

@Composable
private fun Placeholder(height: Dp, shape: Shape, fill: Color, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(Modifier.width(240.dp).height(height).clip(shape).background(fill).then(modifier), contentAlignment = Alignment.Center) { content() }
}

@Composable
private fun CloseButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    IconButton(
        onClick = onClick,
        colors = IconButtonDefaults.iconButtonColors(containerColor = Color.White.copy(alpha = 0.15f), contentColor = Color.White),
        modifier = modifier.size(44.dp),
    ) { Icon(Icons.Outlined.Close, L("closeDialog")) }
}

@Composable
fun DMImageViewer(file: File, onDismiss: () -> Unit) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        var scale by remember { mutableFloatStateOf(1f) }
        var offset by remember { mutableStateOf(Offset.Zero) }
        var animate by remember { mutableStateOf(false) }
        val shownScale by animateFloatAsState(scale, label = "scale")
        val shownOffset by animateOffsetAsState(offset, label = "offset")
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            AsyncImage(
                model = file,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .fillMaxSize()
                    .graphicsLayer {
                        val s = if (animate) shownScale else scale
                        val o = if (animate) shownOffset else offset
                        scaleX = s
                        scaleY = s
                        translationX = o.x
                        translationY = o.y
                    }
                    .pointerInput(Unit) {
                        detectTapGestures(onDoubleTap = {
                            animate = true
                            if (scale > 1f) {
                                scale = 1f
                                offset = Offset.Zero
                            } else {
                                scale = 2.5f
                            }
                        })
                    }
                    .pointerInput(Unit) {
                        awaitDismissOrTransform(
                            scaleProvider = { scale },
                            onTransform = { pan, zoom ->
                                animate = false
                                scale = (scale * zoom).coerceIn(1f, 6f)
                                offset = if (scale > 1f) offset + pan else Offset(0f, offset.y + pan.y)
                            },
                            onEnd = {
                                if (scale <= 1f) {
                                    if (abs(offset.y) > 120.dp.toPx()) {
                                        onDismiss()
                                    } else {
                                        animate = true
                                        offset = Offset.Zero
                                    }
                                }
                            },
                        )
                    }
                    .testTag("dm-image-viewer"),
            )
            CloseButton(onDismiss, Modifier.statusBarsPadding().padding(16.dp).testTag("dm-image-viewer-close"))
        }
    }
}

private suspend fun PointerInputScope.awaitDismissOrTransform(
    scaleProvider: () -> Float,
    onTransform: (Offset, Float) -> Unit,
    onEnd: () -> Unit,
) {
    awaitEachGesture {
        awaitFirstDown(requireUnconsumed = false)
        do {
            val event = awaitPointerEvent()
            val zoom = event.calculateZoom()
            val pan = event.calculatePan()
            if (zoom != 1f || pan != Offset.Zero) {
                onTransform(pan, zoom)
                if (scaleProvider() > 1f || event.changes.size > 1 || abs(pan.y) > 0f) event.changes.forEach { it.consume() }
            }
        } while (event.changes.any { it.pressed })
        onEnd()
    }
}

@OptIn(UnstableApi::class)
@Composable
fun DMVideoPlayer(file: File, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val player = remember(file) {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(android.net.Uri.fromFile(file)))
            prepare()
            playWhenReady = true
        }
    }
    DisposableEffect(player) { onDispose { player.release() } }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            AndroidView(
                factory = { PlayerView(it).apply { this.player = player; useController = true } },
                modifier = Modifier.fillMaxSize(),
            )
            CloseButton(onDismiss, Modifier.statusBarsPadding().padding(16.dp).testTag("dm-video-close"))
        }
    }
}
