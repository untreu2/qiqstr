package me.untreu.qiqstr.ui.note

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.data.services.WebOfTrustService

object SensitiveContentStore {
    const val PREFERENCE_KEY = WebOfTrustService.SHOW_SENSITIVE_CONTENT_KEY
    private var revealed by mutableStateOf<Set<String>>(emptySet())

    fun isRevealed(noteId: String) = noteId in revealed

    fun reveal(noteId: String) { revealed = revealed + noteId }
}

@Composable
fun NoteSensitiveCover(
    noteId: String,
    reason: String?,
    modifier: Modifier = Modifier,
    compact: Boolean = false,
    content: @Composable () -> Unit,
) {
    val hidden = reason != null && !WebOfTrustService.showsSensitiveContent && !SensitiveContentStore.isRevealed(noteId)
    if (!hidden) {
        Box(modifier) { content() }
        return
    }
    val shape = RoundedCornerShape(if (compact) 12.dp else 16.dp)
    Box(modifier.fillMaxWidth().heightIn(min = if (compact) 72.dp else 112.dp).clip(shape)) {
        val supportsBlur = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
        Box(
            Modifier.fillMaxWidth()
                .then(if (supportsBlur) Modifier.blur(if (compact) 18.dp else 28.dp) else Modifier)
                .clearAndSetSemantics {},
        ) { content() }
        NoteSensitiveOverlay(
            reason = reason ?: "",
            compact = compact,
            opaque = !supportsBlur,
            onReveal = { SensitiveContentStore.reveal(noteId) },
        )
    }
}

@Composable
private fun BoxScope.NoteSensitiveOverlay(reason: String, compact: Boolean, opaque: Boolean, onReveal: () -> Unit) {
    val title = if (reason.isEmpty()) L("feedSensitiveContent") else L("feedSensitiveContentReason", "reason" to reason)
    Box(
        Modifier.matchParentSize()
            .background(if (opaque) AppColors.inputFill else AppColors.tile.copy(alpha = 0.55f))
            .then(if (opaque) Modifier.background(AppColors.surface.copy(alpha = 0.92f)) else Modifier)
            .pointerInput(Unit) { detectTapGestures {} }
            .testTag("note-sensitive-cover"),
        contentAlignment = Alignment.Center,
    ) {
        val label: @Composable () -> Unit = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Outlined.VisibilityOff, null, Modifier.size(18.dp), tint = AppColors.textSecondary)
                Text(
                    title,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = AppColors.textSecondary,
                    maxLines = 2,
                    textAlign = TextAlign.Center,
                )
            }
        }
        val button: @Composable () -> Unit = {
            FilledTonalButton(onClick = onReveal, modifier = Modifier.testTag("note-sensitive-show")) {
                Text(L("feedSensitiveShow"), fontWeight = FontWeight.SemiBold)
            }
        }
        if (compact) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) { label() }
                Spacer(Modifier.width(8.dp))
                button()
            }
        } else {
            Column(Modifier.padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                label()
                button()
            }
        }
    }
}
