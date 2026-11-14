package me.untreu.qiqstr.ui.articles

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.TextDecrease
import androidx.compose.material.icons.outlined.TextIncrease
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.components.TextAction

enum class ReaderLineSpacing(val raw: String, val scale: Float) {
    COMPACT("compact", 0.5f), STANDARD("standard", 1f), RELAXED("relaxed", 1.7f);

    val title: String
        get() = when (this) {
            COMPACT -> L("readerSpacingCompact")
            STANDARD -> L("readerSpacingStandard")
            RELAXED -> L("readerSpacingRelaxed")
        }

    companion object {
        fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: STANDARD
    }
}

data class ReaderStyle(val textScale: Float = 1f, val fontFamily: FontFamily? = null, val lineSpacingScale: Float = 1f)

val LocalReaderStyle = compositionLocalOf { ReaderStyle() }

object ReaderSettings {
    private const val TEXT_SIZE = "reader_text_size_offset"
    private const val SERIF = "reader_serif"
    private const val LINE_SPACING = "reader_line_spacing"
    val sizeRange = -3..5

    var offset by mutableIntStateOf(Prefs.long(TEXT_SIZE, 0).toInt())
        private set
    var serif by mutableStateOf(Prefs.bool(SERIF))
        private set
    var spacing by mutableStateOf(ReaderLineSpacing.from(Prefs.string(LINE_SPACING)))
        private set

    val style: ReaderStyle
        get() = ReaderStyle(1f + offset * 0.08f, if (serif) FontFamily.Serif else null, spacing.scale)

    val isCustomized: Boolean get() = offset != 0 || serif || spacing != ReaderLineSpacing.STANDARD

    fun updateOffset(value: Int) {
        offset = value.coerceIn(sizeRange)
        Prefs.set(TEXT_SIZE, offset.toLong())
    }

    fun updateSerif(value: Boolean) {
        serif = value
        Prefs.set(SERIF, value)
    }

    fun updateSpacing(value: ReaderLineSpacing) {
        spacing = value
        Prefs.set(LINE_SPACING, value.raw)
    }

    fun reset() {
        updateOffset(0)
        updateSerif(false)
        updateSpacing(ReaderLineSpacing.STANDARD)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReaderSettingsPanel() {
    val haptics = LocalHapticFeedback.current
    Column(Modifier.width(320.dp).padding(20.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(L("readerTextSize"), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Outlined.TextDecrease, null, tint = AppColors.textSecondary)
                Slider(
                    value = ReaderSettings.offset.toFloat(),
                    onValueChange = {
                        val next = it.roundToInt()
                        if (next != ReaderSettings.offset) {
                            ReaderSettings.updateOffset(next)
                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        }
                    },
                    valueRange = ReaderSettings.sizeRange.first.toFloat()..ReaderSettings.sizeRange.last.toFloat(),
                    steps = ReaderSettings.sizeRange.last - ReaderSettings.sizeRange.first - 1,
                    colors = SliderDefaults.colors(thumbColor = AppColors.textPrimary, activeTrackColor = AppColors.textPrimary),
                    modifier = Modifier.weight(1f).testTag("reader-text-size"),
                )
                Icon(Icons.Outlined.TextIncrease, null, tint = AppColors.textSecondary)
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(L("readerFont"), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().testTag("reader-font")) {
                listOf(false, true).forEachIndexed { index, serif ->
                    SegmentedButton(
                        selected = ReaderSettings.serif == serif,
                        onClick = { ReaderSettings.updateSerif(serif) },
                        shape = SegmentedButtonDefaults.itemShape(index, 2),
                    ) {
                        Text(if (serif) L("readerFontSerif") else L("readerFontSans"), fontFamily = if (serif) FontFamily.Serif else null)
                    }
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(L("readerLineSpacing"), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().testTag("reader-line-spacing")) {
                ReaderLineSpacing.entries.forEachIndexed { index, option ->
                    SegmentedButton(
                        selected = ReaderSettings.spacing == option,
                        onClick = { ReaderSettings.updateSpacing(option) },
                        shape = SegmentedButtonDefaults.itemShape(index, ReaderLineSpacing.entries.size),
                    ) {
                        Text(option.title, maxLines = 1)
                    }
                }
            }
        }
        if (ReaderSettings.isCustomized) {
            Row(Modifier.testTag("reader-reset")) { TextAction(L("readerReset"), { ReaderSettings.reset() }) }
        }
    }
}
