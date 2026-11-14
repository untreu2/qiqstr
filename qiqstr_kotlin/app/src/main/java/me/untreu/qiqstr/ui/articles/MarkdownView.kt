package me.untreu.qiqstr.ui.articles

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckBox
import androidx.compose.material.icons.outlined.CheckBoxOutlineBlank
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.FormatQuote
import androidx.compose.material.icons.outlined.Highlight
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.RemoteImage
import me.untreu.qiqstr.data.sync.ProfileCache

class MarkdownHighlighting(
    val passages: List<String>,
    val onHighlight: (String) -> Unit,
    val onShowHighlights: () -> Unit,
) {
    val segments: List<String> = passages.flatMap { passage ->
        val lines = passage.split("\n").map { it.trimWs() }
        if (lines.size == 1) lines.filter { it.length >= 3 } else lines.filter { it.length >= 8 }
    }
}

class MarkdownAnchors {
    var content: LayoutCoordinates? = null
    val offsets = HashMap<Int, Float>()

    fun record(index: Int, coordinates: LayoutCoordinates) {
        val root = content ?: return
        if (!root.isAttached || !coordinates.isAttached) return
        offsets[index] = root.localPositionOf(coordinates, androidx.compose.ui.geometry.Offset.Zero).y
    }
}

val LocalMarkdownQuoted = staticCompositionLocalOf { false }
val LocalMarkdownHighlighting = staticCompositionLocalOf<MarkdownHighlighting?> { null }

object MarkdownLinkHandler {
    fun open(url: String) {
        val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return
        when (uri.scheme?.lowercase()) {
            "nostr", "http", "https", "mailto", "tel" -> Router.open(uri)
        }
    }
}

@Composable
fun MarkdownView(blocks: List<MarkdownBlock>, modifier: Modifier = Modifier, anchors: MarkdownAnchors? = null) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        blocks.forEachIndexed { index, block ->
            val blockModifier = if (anchors != null) Modifier.onGloballyPositioned { anchors.record(index, it) } else Modifier
            Box(blockModifier) { MarkdownBlockView(block) }
        }
    }
}

@Composable
fun MarkdownBlockView(block: MarkdownBlock) {
    when (block) {
        is MarkdownBlock.Heading -> {
            val style = when (block.level) {
                1 -> MaterialTheme.typography.headlineMedium
                2 -> MaterialTheme.typography.headlineSmall
                3 -> MaterialTheme.typography.titleLarge
                else -> MaterialTheme.typography.titleMedium
            }
            MarkdownText(
                block.text,
                style = style,
                weight = if (block.level <= 3) FontWeight.Bold else FontWeight.SemiBold,
                modifier = Modifier.padding(top = if (block.level <= 2) 10.dp else 4.dp).semantics { heading() },
            )
        }
        is MarkdownBlock.Paragraph -> MarkdownText(block.text)
        is MarkdownBlock.Code -> MarkdownCodeBlock(block.language, block.code)
        is MarkdownBlock.Quote -> {
            Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.width(3.dp).fillMaxHeight().clip(RoundedCornerShape(2.dp)).background(AppColors.textTertiary))
                CompositionLocalProvider(LocalMarkdownQuoted provides true) {
                    MarkdownView(block.blocks, Modifier.weight(1f))
                }
            }
        }
        is MarkdownBlock.ListBlock -> MarkdownListView(block.ordered, block.start, block.items)
        is MarkdownBlock.Image -> MarkdownImage(block.url, block.alt, block.link)
        is MarkdownBlock.Table -> MarkdownTable(block.header, block.rows)
        is MarkdownBlock.Nostr -> NostrEmbedView(block.entity)
        MarkdownBlock.Rule -> HorizontalDivider(Modifier.padding(vertical = 8.dp), color = AppColors.divider)
    }
}

@Composable
private fun readerTextStyle(base: TextStyle, weight: FontWeight?, isBody: Boolean): TextStyle {
    val reader = LocalReaderStyle.current
    val size = base.fontSize.value * reader.textScale
    val spacing = (if (isBody) 6f else 2f) * reader.lineSpacingScale
    return base.copy(
        fontSize = size.sp,
        lineHeight = (size * 1.25f + spacing).sp,
        fontWeight = weight ?: base.fontWeight,
        fontFamily = reader.fontFamily ?: base.fontFamily,
    )
}

@Composable
fun MarkdownText(
    text: String,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.bodyLarge,
    weight: FontWeight? = null,
) {
    val quoted = LocalMarkdownQuoted.current
    val highlighting = LocalMarkdownHighlighting.current
    val colors = MarkdownColors(AppColors.link, AppColors.inputFill)
    val rendered = MarkdownInline.attributed(text, colors, MarkdownLinkHandler::open) { ProfileCache.profiles[it]?.bestName }
    val textStyle = readerTextStyle(style, weight, style == MaterialTheme.typography.bodyLarge)
    val color = if (quoted) AppColors.textSecondary else AppColors.textPrimary
    if (highlighting == null) {
        SelectionContainer(modifier.fillMaxWidth()) { Text(rendered, style = textStyle, color = color) }
        return
    }
    val markColor = AppColors.link.copy(alpha = 0.18f)
    val marked = remember(rendered, highlighting.segments, markColor) { mark(rendered, highlighting.segments, SpanStyle(background = markColor)) }
    var menu by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val barColor = AppColors.link.copy(alpha = 0.55f)
    Box(modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
        Text(
            marked.first,
            style = textStyle,
            color = color,
            modifier = Modifier.fillMaxWidth().pointerInput(highlighting) {
                detectTapGestures(onLongPress = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    menu = true
                })
            },
        )
        if (marked.second) {
            Box(
                Modifier
                    .offset(x = (-20).dp)
                    .width(15.dp)
                    .fillMaxHeight()
                    .clickable(onClick = highlighting.onShowHighlights)
                    .semantics { contentDescription = L("highlightsTitle") }
                    .testTag("article-highlight-mark"),
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.width(3.dp).fillMaxHeight().clip(RoundedCornerShape(2.dp)).background(barColor))
            }
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            MenuItem(L("copy"), Icons.Outlined.ContentCopy) { menu = false; ArticleActions.copy(rendered.text, toast = false) }
            MenuItem(L("highlightAction"), Icons.Outlined.Highlight) { menu = false; highlighting.onHighlight(rendered.text) }
            if (marked.second) {
                MenuItem(L("highlightsTitle"), Icons.Outlined.FormatQuote) { menu = false; highlighting.onShowHighlights() }
            }
        }
    }
}

private fun mark(source: AnnotatedString, segments: List<String>, style: SpanStyle): Pair<AnnotatedString, Boolean> {
    if (segments.isEmpty()) return source to false
    val ranges = mutableListOf<IntRange>()
    for (segment in segments) {
        var start = source.text.indexOf(segment)
        while (start >= 0) {
            ranges.add(start until start + segment.length)
            start = source.text.indexOf(segment, start + segment.length)
        }
    }
    if (ranges.isEmpty()) return source to false
    val builder = AnnotatedString.Builder(source)
    ranges.forEach { builder.addStyle(style, it.first, it.last + 1) }
    return builder.toAnnotatedString() to true
}

@Composable
fun MarkdownListView(ordered: Boolean, start: Int, items: List<MarkdownListItem>) {
    val markerStyle = readerTextStyle(MaterialTheme.typography.bodyLarge, FontWeight.Medium, true)
    Column(Modifier.padding(start = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        items.forEachIndexed { index, item ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.widthIn(min = 18.dp), contentAlignment = Alignment.TopEnd) {
                    when {
                        item.checked != null -> Icon(
                            if (item.checked) Icons.Outlined.CheckBox else Icons.Outlined.CheckBoxOutlineBlank,
                            null,
                            tint = if (item.checked) AppColors.textPrimary else AppColors.textSecondary,
                            modifier = Modifier.size(20.dp).padding(top = 2.dp),
                        )
                        ordered -> Text("${start + index}.", style = markerStyle.copy(fontFeatureSettings = "tnum"), color = AppColors.textSecondary)
                        else -> Text("•", style = markerStyle.copy(fontWeight = FontWeight.SemiBold), color = AppColors.textSecondary)
                    }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    item.blocks.forEach { MarkdownBlockView(it) }
                }
            }
        }
    }
}

@Composable
fun MarkdownCodeBlock(language: String, code: String) {
    val haptics = LocalHapticFeedback.current
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(AppColors.inputFill).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (language.isNotEmpty()) {
                Text(language.lowercase(), style = MaterialTheme.typography.labelMedium, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, color = AppColors.textSecondary)
            }
            Box(Modifier.weight(1f))
            IconButton(
                onClick = {
                    ArticleActions.copy(code)
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                },
                modifier = Modifier.size(32.dp).testTag("markdown-copy-code"),
            ) {
                Icon(Icons.Outlined.ContentCopy, L("exploreCopyCode"), Modifier.size(18.dp), tint = AppColors.textSecondary)
            }
        }
        SelectionContainer(Modifier.horizontalScroll(rememberScrollState())) {
            Text(
                code,
                style = readerTextStyle(MaterialTheme.typography.bodyMedium, null, false).copy(fontFamily = FontFamily.Monospace, letterSpacing = 0.em),
                color = AppColors.textPrimary,
                softWrap = false,
            )
        }
    }
}

@Composable
fun MarkdownImage(url: String, alt: String, link: String?) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        RemoteImage(
            url,
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(14.dp))
                .clickable { MarkdownLinkHandler.open(link ?: url) },
            contentScale = ContentScale.FillWidth,
            contentDescription = alt.ifEmpty { L("exploreImage") },
        )
        if (alt.contains(" ")) {
            Text(alt, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
        }
    }
}

@Composable
fun MarkdownTable(header: List<String>, rows: List<List<String>>) {
    val headerStyle = MaterialTheme.typography.bodyMedium
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(AppColors.inputFill.copy(alpha = 0.6f))) {
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(14.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            header.forEachIndexed { column, cell ->
                Column(Modifier.width(IntrinsicSize.Max), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    MarkdownTableCell(cell, headerStyle, FontWeight.SemiBold)
                    HorizontalDivider(Modifier.fillMaxWidth(), color = AppColors.divider)
                    rows.forEach { row -> MarkdownTableCell(row.getOrElse(column) { "" }, headerStyle, null) }
                }
            }
        }
    }
}

@Composable
private fun MarkdownTableCell(text: String, style: TextStyle, weight: FontWeight?) {
    val colors = MarkdownColors(AppColors.link, AppColors.inputFill)
    val rendered = MarkdownInline.attributed(text, colors, MarkdownLinkHandler::open) { ProfileCache.profiles[it]?.bestName }
    Text(rendered, style = readerTextStyle(style, weight, false), color = AppColors.textPrimary, softWrap = false)
}
