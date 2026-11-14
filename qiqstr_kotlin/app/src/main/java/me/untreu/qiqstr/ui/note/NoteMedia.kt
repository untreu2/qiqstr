package me.untreu.qiqstr.ui.note

import androidx.compose.material.icons.outlined.BrokenImage
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.util.LruCache
import android.view.ViewGroup
import androidx.annotation.OptIn
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil3.compose.AsyncImage
import coil3.compose.SubcomposeAsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import coil3.video.videoFrameMillis
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import kotlin.math.abs

@Composable
fun NoteMediaGrid(media: List<NoteMediaItem>, modifier: Modifier = Modifier, maxHeight: Dp = 420.dp) {
    val images = media.filter { !it.isVideo }
    val videos = media.filter { it.isVideo }
    var viewer by remember { mutableStateOf<Int?>(null) }
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (images.isNotEmpty()) ImageGrid(images, maxHeight) { viewer = it }
        videos.forEach { NoteVideoView(it) }
    }
    viewer?.let { index -> NotePhotoViewer(images.map { it.url }, index) { viewer = null } }
}

@Composable
private fun ImageGrid(images: List<NoteMediaItem>, maxHeight: Dp, onOpen: (Int) -> Unit) {
    val spacing = 4.dp
    val shape = RoundedCornerShape(16.dp)
    val tile: @Composable (Int, Modifier) -> Unit = { index, mod -> MediaTile(images[index], mod) { onOpen(index) } }
    when (images.size) {
        1 -> {
            val ratio = (images[0].aspectRatio ?: (4f / 3f)).coerceIn(0.66f, 1.9f)
            Box(Modifier.fillMaxWidth().heightIn(max = maxHeight).aspectRatio(ratio, matchHeightConstraintsFirst = false).clip(shape)) {
                tile(0, Modifier.fillMaxSize())
            }
        }
        2 -> Row(Modifier.fillMaxWidth().height(220.dp).clip(shape), horizontalArrangement = Arrangement.spacedBy(spacing)) {
            tile(0, Modifier.weight(1f).fillMaxHeight())
            tile(1, Modifier.weight(1f).fillMaxHeight())
        }
        3 -> Row(Modifier.fillMaxWidth().height(260.dp).clip(shape), horizontalArrangement = Arrangement.spacedBy(spacing)) {
            tile(0, Modifier.weight(1f).fillMaxHeight())
            Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(spacing)) {
                tile(1, Modifier.weight(1f).fillMaxWidth())
                tile(2, Modifier.weight(1f).fillMaxWidth())
            }
        }
        else -> Column(Modifier.fillMaxWidth().height(280.dp).clip(shape), verticalArrangement = Arrangement.spacedBy(spacing)) {
            Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(spacing)) {
                tile(0, Modifier.weight(1f).fillMaxHeight())
                tile(1, Modifier.weight(1f).fillMaxHeight())
            }
            Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(spacing)) {
                tile(2, Modifier.weight(1f).fillMaxHeight())
                Box(Modifier.weight(1f).fillMaxHeight()) {
                    tile(3, Modifier.fillMaxSize())
                    if (images.size > 4) {
                        Box(Modifier.matchParentSize().background(Color.Black.copy(alpha = 0.45f)), contentAlignment = Alignment.Center) {
                            Text("+${images.size - 4}", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold, color = Color.White)
                        }
                    }
                }
            }
        }
    }
}

private fun Modifier.matchParentSize(): Modifier = this.fillMaxSize()

@Composable
private fun MediaTile(item: NoteMediaItem, modifier: Modifier, onClick: () -> Unit) {
    val description = item.alt ?: L("photos")
    Box(modifier.clickable(onClick = onClick).semantics { contentDescription = description }.testTag("note-media-image")) {
        NoteMediaImage(item, Modifier.fillMaxSize())
        item.alt?.let { NoteAltBadge(it, Modifier.align(Alignment.BottomStart).padding(8.dp)) }
    }
}

@Composable
fun NoteMediaImage(item: NoteMediaItem, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    if (!item.url.startsWith("http")) {
        NoteMediaPlaceholder(item.blurhash, modifier)
        return
    }
    SubcomposeAsyncImage(
        model = ImageRequest.Builder(context).data(item.url).crossfade(200).build(),
        contentDescription = item.alt,
        contentScale = ContentScale.Crop,
        loading = { NoteMediaPlaceholder(item.blurhash, Modifier.fillMaxSize()) },
        error = { NoteMediaPlaceholder(item.blurhash, Modifier.fillMaxSize()) },
        modifier = modifier,
    )
}

@Composable
fun NoteMediaPlaceholder(blurhash: String?, modifier: Modifier = Modifier) {
    val bitmap = remember(blurhash) { blurhash?.let { BlurHash.image(it) } }
    if (bitmap != null) {
        Image(bitmap.asImageBitmap(), null, modifier, contentScale = ContentScale.Crop)
    } else {
        Box(modifier.background(AppColors.tile))
    }
}

@Composable
fun NoteAltBadge(text: String, modifier: Modifier = Modifier) {
    var presented by remember { mutableStateOf(false) }
    Surface(
        onClick = { presented = true },
        shape = CircleShape,
        color = Color.Black.copy(alpha = 0.55f),
        contentColor = Color.White,
        modifier = modifier.semantics { contentDescription = L("feedAltTextTitle") }.testTag("note-media-alt"),
    ) {
        Text(L("feedAltBadge"), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(horizontal = 7.dp, vertical = 3.dp))
    }
    if (presented) {
        AlertDialog(
            onDismissRequest = { presented = false },
            title = { Text(L("feedAltTextTitle")) },
            text = { Text(text, style = MaterialTheme.typography.bodyMedium) },
            confirmButton = { me.untreu.qiqstr.core.components.TextAction(L("done"), { presented = false }) },
        )
    }
}

@Composable
fun NotePhotoViewer(urls: List<String>, startIndex: Int, onDismiss: () -> Unit) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        val pager = rememberPagerState(initialPage = startIndex.coerceIn(0, maxOf(0, urls.size - 1))) { urls.size }
        var chromeVisible by remember { mutableStateOf(true) }
        var zoomed by remember { mutableStateOf(false) }
        val drag = remember { Animatable(0f) }
        val scope = rememberCoroutineScope()
        val dismissDistance = with(LocalDensity.current) { 140.dp.toPx() }
        val context = LocalContext.current
        Box(
            Modifier.fillMaxSize()
                .background(Color.Black.copy(alpha = 1f - minOf(abs(drag.value) / 1200f, 0.7f)))
                .testTag("photo-viewer"),
        ) {
            HorizontalPager(
                state = pager,
                userScrollEnabled = !zoomed,
                modifier = Modifier.fillMaxSize()
                    .graphicsLayer { translationY = drag.value }
                    .draggable(
                        state = rememberDraggableState { delta -> scope.launch { drag.snapTo(drag.value + delta) } },
                        orientation = Orientation.Vertical,
                        enabled = !zoomed,
                        onDragStopped = {
                            if (abs(drag.value) > dismissDistance) onDismiss() else scope.launch { drag.animateTo(0f) }
                        },
                    ),
            ) { page ->
                ZoomableImage(
                    url = urls[page],
                    onZoomChange = { if (page == pager.currentPage) zoomed = it },
                    onSingleTap = { chromeVisible = !chromeVisible },
                )
            }
            AnimatedVisibility(chromeVisible, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.TopCenter)) {
                Row(Modifier.fillMaxWidth().safeDrawingPadding().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    ViewerButton(Icons.Filled.Close, L("closeDialog"), "photo-viewer-close", onDismiss)
                    Spacer(Modifier.weight(1f))
                    if (urls.size > 1) {
                        Surface(shape = CircleShape, color = Color.White.copy(alpha = 0.16f), contentColor = Color.White) {
                            Text(
                                "${pager.currentPage + 1} / ${urls.size}",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
                            )
                        }
                    }
                    Spacer(Modifier.weight(1f))
                    ViewerButton(Icons.Outlined.Share, L("share"), "photo-viewer-share") {
                        val url = urls.getOrNull(pager.currentPage) ?: return@ViewerButton
                        val intent = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, url)
                        runCatching { context.startActivity(Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun ViewerButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, tag: String, onClick: () -> Unit) {
    FilledIconButton(
        onClick = onClick,
        colors = IconButtonDefaults.filledIconButtonColors(containerColor = Color.White.copy(alpha = 0.16f), contentColor = Color.White),
        modifier = Modifier.size(44.dp).testTag(tag),
    ) { Icon(icon, label) }
}

@Composable
private fun ZoomableImage(url: String, onZoomChange: (Boolean) -> Unit, onSingleTap: () -> Unit) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    val context = LocalContext.current
    LaunchedEffect(scale > 1f) { onZoomChange(scale > 1f) }
    Box(
        Modifier.fillMaxSize()
            .pointerInput(Unit) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    do {
                        val event = awaitPointerEvent()
                        if (event.changes.size > 1 || scale > 1f) {
                            scale = (scale * event.calculateZoom()).coerceIn(1f, 5f)
                            offset = if (scale <= 1f) Offset.Zero else offset + event.calculatePan()
                            event.changes.forEach { if (it.positionChanged()) it.consume() }
                        }
                    } while (event.changes.any { it.pressed })
                }
            }
            .pointerInput(Unit) {
                detectTapGestures(
                    onDoubleTap = { point ->
                        if (scale > 1f) {
                            scale = 1f
                            offset = Offset.Zero
                        } else {
                            scale = 2.5f
                            offset = Offset((size.width / 2f - point.x) * 1.5f, (size.height / 2f - point.y) * 1.5f)
                        }
                    },
                    onTap = { onSingleTap() },
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        SubcomposeAsyncImage(
            model = ImageRequest.Builder(context).data(url).build(),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            loading = { Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Color.White) } },
            error = {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    androidx.compose.material3.Icon(androidx.compose.material.icons.Icons.Outlined.BrokenImage, null, Modifier.size(48.dp), tint = Color.White.copy(alpha = 0.6f))
                }
            },
            modifier = Modifier.fillMaxSize().graphicsLayer {
                scaleX = scale
                scaleY = scale
                translationX = offset.x
                translationY = offset.y
            },
        )
    }
}

private object VideoDurations {
    private val cache = LruCache<String, Double>(1000)
    private val failed = HashSet<String>()

    suspend fun duration(url: String): Double? {
        cache.get(url)?.let { return it }
        if (url in failed) return null
        val value = withContext(Dispatchers.IO) {
            runCatching {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(url, HashMap())
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()?.let { it / 1000.0 }
                } finally {
                    runCatching { retriever.release() }
                }
            }.getOrNull()
        }
        if (value != null && value > 0) cache.put(url, value) else {
            if (failed.size > 500) failed.clear()
            failed.add(url)
        }
        return value?.takeIf { it > 0 }
    }
}

private fun formatDuration(seconds: Double): String {
    val total = Math.round(seconds).toInt()
    val hours = total / 3600
    val minutes = (total % 3600) / 60
    val secs = total % 60
    return if (hours > 0) String.format(java.util.Locale.US, "%d:%02d:%02d", hours, minutes, secs) else String.format(java.util.Locale.US, "%d:%02d", minutes, secs)
}

@OptIn(UnstableApi::class)
@Composable
fun NoteVideoView(item: NoteMediaItem, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    var player by remember { mutableStateOf<ExoPlayer?>(null) }
    var isPlaying by remember { mutableStateOf(false) }
    var isMuted by remember { mutableStateOf(true) }
    var duration by remember { mutableStateOf<Double?>(null) }
    var fullScreen by remember { mutableStateOf(false) }
    val inlineView = remember { arrayOfNulls<PlayerView>(1) }
    LaunchedEffect(item.url) { duration = VideoDurations.duration(item.url) }
    DisposableEffect(item.url) {
        onDispose {
            player?.release()
            player = null
            isPlaying = false
        }
    }
    val applyAudio: (ExoPlayer, Boolean) -> Unit = { p, muted ->
        p.volume = if (muted) 0f else 1f
        p.setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), !muted)
    }
    val play = {
        val existing = player
        if (existing != null) {
            existing.play()
        } else {
            val p = ExoPlayer.Builder(context).build()
            applyAudio(p, isMuted)
            p.addListener(object : Player.Listener {
                override fun onIsPlayingChanged(playing: Boolean) { isPlaying = playing }
                override fun onPlaybackStateChanged(state: Int) {
                    if (state == Player.STATE_ENDED) {
                        p.pause()
                        p.seekTo(0)
                    }
                }
            })
            p.setMediaItem(MediaItem.fromUri(item.url))
            p.prepare()
            p.playWhenReady = true
            player = p
        }
        isPlaying = true
    }
    val ratio = (item.aspectRatio ?: (16f / 9f)).coerceIn(0.56f, 1.9f)
    Box(
        modifier.fillMaxWidth().heightIn(max = 460.dp).aspectRatio(ratio, matchHeightConstraintsFirst = false)
            .clip(RoundedCornerShape(16.dp)).background(Color.Black),
    ) {
        val current = player
        if (current != null) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        useController = false
                        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                        layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                        setShutterBackgroundColor(android.graphics.Color.BLACK)
                        inlineView[0] = this
                    }
                },
                update = { view -> if (view.player !== current && !fullScreen) view.player = current },
                onRelease = { view -> if (inlineView[0] === view) inlineView[0] = null },
                modifier = Modifier.fillMaxSize()
                    .clickable { if (isPlaying) current.pause() else current.play() }
                    .semantics { contentDescription = if (isPlaying) L("videoPause") else L("videoTapToPlay") }
                    .testTag("note-media-video-surface"),
            )
            if (!isPlaying) PlayButton(item, duration, play)
            VideoControl(if (isMuted) Icons.AutoMirrored.Filled.VolumeOff else Icons.AutoMirrored.Filled.VolumeUp, if (isMuted) L("unmute") else L("mute"), "note-media-video-mute", Alignment.BottomStart) {
                isMuted = !isMuted
                applyAudio(current, isMuted)
            }
            VideoControl(Icons.Filled.Fullscreen, L("videoFullScreen"), "note-media-video-fullscreen", Alignment.BottomEnd) {
                applyAudio(current, false)
                isMuted = false
                fullScreen = true
                current.play()
            }
        } else {
            NoteMediaPlaceholder(item.blurhash, Modifier.fillMaxSize())
            val thumbnail = item.poster
            AsyncImage(
                model = if (thumbnail != null) {
                    ImageRequest.Builder(context).data(thumbnail).crossfade(200).build()
                } else {
                    ImageRequest.Builder(context).data(item.url).videoFrameMillis(500).crossfade(200).build()
                },
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
            PlayButton(item, duration, play)
            duration?.let {
                Surface(
                    shape = CircleShape,
                    color = Color.Black.copy(alpha = 0.55f),
                    contentColor = Color.White,
                    modifier = Modifier.align(Alignment.BottomEnd).padding(10.dp),
                ) {
                    Text(formatDuration(it), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp))
                }
            }
            item.alt?.let { NoteAltBadge(it, Modifier.align(Alignment.BottomStart).padding(10.dp)) }
        }
    }
    val fullPlayer = player
    if (fullScreen && fullPlayer != null) {
        Dialog(
            onDismissRequest = { fullScreen = false },
            properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
        ) {
            Box(Modifier.fillMaxSize().background(Color.Black)) {
                AndroidView(
                    factory = { ctx ->
                        PlayerView(ctx).apply {
                            useController = true
                            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                            PlayerView.switchTargetView(fullPlayer, inlineView[0], this)
                        }
                    },
                    onRelease = { view ->
                        val inline = inlineView[0]
                        if (inline != null) PlayerView.switchTargetView(fullPlayer, view, inline) else view.player = null
                        isPlaying = fullPlayer.isPlaying
                    },
                    modifier = Modifier.fillMaxSize(),
                )
                FilledIconButton(
                    onClick = { fullScreen = false },
                    colors = IconButtonDefaults.filledIconButtonColors(containerColor = Color.White.copy(alpha = 0.16f), contentColor = Color.White),
                    modifier = Modifier.align(Alignment.TopStart).safeDrawingPadding().padding(16.dp).size(44.dp),
                ) { Icon(Icons.Filled.Close, L("closeDialog")) }
            }
        }
    }
}

@Composable
private fun BoxScope.PlayButton(item: NoteMediaItem, duration: Double?, onPlay: () -> Unit) {
    val label = item.alt?.let { "${L("videoTapToPlay")}, $it" } ?: L("videoTapToPlay")
    val value = duration?.let(::formatDuration) ?: ""
    FilledIconButton(
        onClick = onPlay,
        colors = IconButtonDefaults.filledIconButtonColors(containerColor = Color.Black.copy(alpha = 0.45f), contentColor = Color.White),
        modifier = Modifier.align(Alignment.Center).size(64.dp)
            .semantics { contentDescription = if (value.isEmpty()) label else "$label, $value" }
            .testTag("note-media-video-play"),
    ) { Icon(Icons.Filled.PlayArrow, null, Modifier.size(32.dp)) }
}

@Composable
private fun BoxScope.VideoControl(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    tag: String,
    alignment: Alignment,
    onClick: () -> Unit,
) {
    FilledIconButton(
        onClick = onClick,
        colors = IconButtonDefaults.filledIconButtonColors(containerColor = Color.Black.copy(alpha = 0.35f), contentColor = Color.White),
        modifier = Modifier.align(alignment).padding(10.dp).size(36.dp).testTag(tag),
    ) { Icon(icon, label, Modifier.size(18.dp)) }
}
