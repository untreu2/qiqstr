package me.untreu.qiqstr.ui.profile

import androidx.compose.material.icons.outlined.BrokenImage
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.size
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil3.compose.SubcomposeAsyncImage
import kotlin.math.abs
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.L

@Composable
fun ProfileImageViewer(url: String, onDismiss: () -> Unit) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            ZoomableImage(url, Modifier.fillMaxSize().testTag("image-viewer"), onDismiss = onDismiss)
            FilledTonalIconButton(
                onClick = onDismiss,
                colors = IconButtonDefaults.filledTonalIconButtonColors(containerColor = Color.White.copy(alpha = 0.16f), contentColor = Color.White),
                modifier = Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(16.dp).testTag("image-viewer-close"),
            ) { Icon(Icons.Outlined.Close, L("done")) }
        }
    }
}

@Composable
internal fun ZoomableImage(url: String, modifier: Modifier = Modifier, onTap: (() -> Unit)? = null, onDismiss: (() -> Unit)? = null) {
    val scope = rememberCoroutineScope()
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    val dismissOffset = remember { Animatable(0f) }
    Box(
        modifier
            .pointerInput(url) {
                detectTapGestures(
                    onTap = { onTap?.invoke() },
                    onDoubleTap = {
                        if (scale > 1f) { scale = 1f; offset = Offset.Zero } else scale = 2.5f
                    },
                )
            }
            .pointerInput(url) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    do {
                        val event = awaitPointerEvent()
                        val zoom = event.calculateZoom()
                        val pan = event.calculatePan()
                        val next = (scale * zoom).coerceIn(1f, 6f)
                        scale = next
                        if (next > 1f) {
                            offset += pan
                            event.changes.forEach { if (it.positionChanged()) it.consume() }
                        } else {
                            offset = Offset.Zero
                            if (onDismiss != null && event.changes.size == 1 && (dismissOffset.value != 0f || abs(pan.y) > abs(pan.x))) {
                                scope.launch { dismissOffset.snapTo(dismissOffset.value + pan.y) }
                                event.changes.forEach { if (it.positionChanged()) it.consume() }
                            }
                        }
                    } while (event.changes.any { it.pressed })
                    if (onDismiss != null && abs(dismissOffset.value) > 120 * density) {
                        onDismiss()
                    } else if (dismissOffset.value != 0f) {
                        scope.launch { dismissOffset.animateTo(0f) }
                    }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        SubcomposeAsyncImage(
            model = url,
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
                translationY = offset.y + dismissOffset.value
            },
        )
    }
}
