package me.untreu.qiqstr.ui.articles

import android.util.LruCache
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.data.bridge.Nip19

data class MarkdownColors(val link: Color, val codeBackground: Color)

object MarkdownInline {
    private val codeSpan = Regex("`+[^`]*`+")
    private val mention = Regex("""(?<![\w/(\[=:])(?:nostr:)?((?:npub1|nprofile1|note1|nevent1|naddr1)[02-9ac-hj-np-z]{20,})""")
    private val bareURL = Regex("""(?<![(<\["'=\w/])(https?://[^\s<>)\]"']+[^\s<>)\]"'.,;:!?])""")
    private val autolinkPattern = Regex("""^<((?:https?|mailto|tel|nostr):[^\s<>]+)>""")
    private val rendered = LruCache<String, AnnotatedString>(2_000)
    private val plainColors = MarkdownColors(Color.Unspecified, Color.Unspecified)

    fun attributed(text: String, colors: MarkdownColors, onLink: ((String) -> Unit)?, name: (String) -> String?): AnnotatedString {
        val prepared = transformOutsideCode(text) { autolink(linkMentions(it, name)) }
        val key = "${colors.hashCode()}|${onLink != null}|$prepared"
        rendered.get(key)?.let { return it }
        val result = render(prepared, colors, onLink)
        rendered.put(key, result)
        return result
    }

    fun plain(text: String): String = attributed(text, plainColors, null) { null }.text

    private sealed interface Node {
        data class Text(val value: String) : Node
        data class Code(val value: String) : Node
        data class Styled(val bold: Boolean, val italic: Boolean, val strike: Boolean, val children: List<Node>) : Node
        data class Link(val url: String, val children: List<Node>) : Node
    }

    private fun render(prepared: String, colors: MarkdownColors, onLink: ((String) -> Unit)?): AnnotatedString {
        val nodes = parse(prepared, 0)
        return buildAnnotatedString { append(nodes, colors, onLink) }
    }

    private fun AnnotatedString.Builder.append(nodes: List<Node>, colors: MarkdownColors, onLink: ((String) -> Unit)?) {
        for (node in nodes) {
            when (node) {
                is Node.Text -> append(node.value)
                is Node.Code -> withStyle(SpanStyle(fontFamily = FontFamily.Monospace, background = colors.codeBackground)) { append(node.value) }
                is Node.Styled -> withStyle(
                    SpanStyle(
                        fontWeight = if (node.bold) FontWeight.Bold else null,
                        fontStyle = if (node.italic) FontStyle.Italic else null,
                        textDecoration = if (node.strike) TextDecoration.LineThrough else null,
                    ),
                ) { append(node.children, colors, onLink) }
                is Node.Link -> {
                    val nostr = node.url.startsWith("nostr:", ignoreCase = true)
                    val style = SpanStyle(color = colors.link, fontWeight = if (nostr) FontWeight.Bold else null)
                    if (onLink == null) {
                        withStyle(style) { append(node.children, colors, null) }
                    } else {
                        val link = LinkAnnotation.Clickable(node.url, TextLinkStyles(style)) { onLink(node.url) }
                        withLink(link) { append(node.children, colors, onLink) }
                    }
                }
            }
        }
    }

    private const val PUNCTUATION = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"

    private fun parse(text: String, depth: Int): List<Node> {
        val nodes = mutableListOf<Node>()
        val buffer = StringBuilder()
        fun flush() {
            if (buffer.isNotEmpty()) { nodes.add(Node.Text(buffer.toString())); buffer.clear() }
        }
        var i = 0
        while (i < text.length) {
            val c = text[i]
            when {
                c == '\\' && i + 1 < text.length && text[i + 1] in PUNCTUATION -> {
                    buffer.append(text[i + 1]); i += 2
                }
                c == '`' -> {
                    val run = text.substring(i).takeWhile { it == '`' }.length
                    val fence = "`".repeat(run)
                    val close = findRun(text, fence, i + run, '`')
                    if (close < 0) {
                        buffer.append(fence); i += run
                    } else {
                        var code = text.substring(i + run, close)
                        if (code.length >= 2 && code.startsWith(" ") && code.endsWith(" ") && code.isNotBlank()) code = code.substring(1, code.length - 1)
                        flush(); nodes.add(Node.Code(code)); i = close + run
                    }
                }
                c == '<' -> {
                    val match = autolinkPattern.find(text.substring(i))
                    if (match != null) {
                        flush()
                        val url = match.groupValues[1]
                        nodes.add(Node.Link(url, listOf(Node.Text(url))))
                        i += match.value.length
                    } else {
                        buffer.append(c); i++
                    }
                }
                c == '[' && depth < 6 -> {
                    val link = parseLink(text, i)
                    if (link != null) {
                        flush()
                        nodes.add(Node.Link(link.first, parse(link.second, depth + 1)))
                        i = link.third
                    } else {
                        buffer.append(c); i++
                    }
                }
                (c == '*' || c == '_') && depth < 6 -> {
                    val run = minOf(3, text.substring(i).takeWhile { it == c }.length)
                    val delimiter = c.toString().repeat(run)
                    val after = text.getOrNull(i + run)
                    val before = text.getOrNull(i - 1)
                    val opens = after != null && !after.isWhitespace() && (c == '*' || before == null || !before.isLetterOrDigit())
                    val close = if (opens) findEmphasisClose(text, delimiter, i + run, c) else -1
                    if (close < 0) {
                        buffer.append(text, i, i + run); i += run
                    } else {
                        flush()
                        val inner = parse(text.substring(i + run, close), depth + 1)
                        nodes.add(Node.Styled(bold = run >= 2, italic = run != 2, strike = false, children = inner))
                        i = close + run
                    }
                }
                c == '~' && text.startsWith("~~", i) && depth < 6 -> {
                    val close = text.indexOf("~~", i + 2)
                    if (close > i + 2) {
                        flush()
                        nodes.add(Node.Styled(bold = false, italic = false, strike = true, children = parse(text.substring(i + 2, close), depth + 1)))
                        i = close + 2
                    } else {
                        buffer.append("~~"); i += 2
                    }
                }
                else -> { buffer.append(c); i++ }
            }
        }
        flush()
        return nodes
    }

    private fun findRun(text: String, fence: String, from: Int, char: Char): Int {
        var index = text.indexOf(fence, from)
        while (index >= 0) {
            val endOk = text.getOrNull(index + fence.length) != char
            val startOk = text.getOrNull(index - 1) != char || index == from
            if (endOk && startOk) return index
            index = text.indexOf(fence, index + 1)
        }
        return -1
    }

    private fun findEmphasisClose(text: String, delimiter: String, from: Int, char: Char): Int {
        var index = text.indexOf(delimiter, from)
        while (index >= 0) {
            val before = text.getOrNull(index - 1)
            val after = text.getOrNull(index + delimiter.length)
            val closes = index > from && before != null && !before.isWhitespace() && after != char &&
                (char == '*' || after == null || !after.isLetterOrDigit())
            if (closes) return index
            index = text.indexOf(delimiter, index + 1)
        }
        return -1
    }

    private fun parseLink(text: String, start: Int): Triple<String, String, Int>? {
        var depth = 0
        var i = start
        var labelEnd = -1
        while (i < text.length) {
            when (text[i]) {
                '\\' -> i++
                '[' -> depth++
                ']' -> { depth--; if (depth == 0) { labelEnd = i; break } }
            }
            i++
        }
        if (labelEnd < 0 || text.getOrNull(labelEnd + 1) != '(') return null
        var j = labelEnd + 2
        var parens = 1
        while (j < text.length) {
            when (text[j]) {
                '\\' -> j++
                '(' -> parens++
                ')' -> { parens--; if (parens == 0) break }
            }
            j++
        }
        if (j >= text.length) return null
        var target = text.substring(labelEnd + 2, j).trim()
        target = target.split(Regex("\\s+")).firstOrNull().orEmpty().removePrefix("<").removeSuffix(">")
        if (target.isEmpty()) return null
        return Triple(target, text.substring(start + 1, labelEnd), j + 1)
    }

    private fun transformOutsideCode(text: String, transform: (String) -> String): String {
        val output = StringBuilder()
        var cursor = 0
        for (match in codeSpan.findAll(text)) {
            if (match.range.first > cursor) output.append(transform(text.substring(cursor, match.range.first)))
            output.append(match.value)
            cursor = match.range.last + 1
        }
        if (cursor < text.length) output.append(transform(text.substring(cursor)))
        return output.toString()
    }

    private fun linkMentions(text: String, name: (String) -> String?): String {
        if (!text.contains("1")) return text
        return mention.replace(text) { match ->
            val entity = match.groupValues[1]
            "[${escape(label(entity, name))}](nostr:$entity)"
        }
    }

    private fun autolink(text: String): String {
        if (!text.contains("http")) return text
        return bareURL.replace(text) { "<${it.groupValues[1]}>" }
    }

    private fun label(entity: String, name: (String) -> String?): String {
        if (entity.startsWith("npub1") || entity.startsWith("nprofile1")) {
            val value = Nip19.pubkeyHex(entity)?.let(name)
            return if (value != null) "@$value" else "@${entity.take(12)}…"
        }
        if (entity.startsWith("naddr1")) return L("article")
        return "${entity.take(12)}…"
    }

    private fun escape(text: String): String {
        val output = StringBuilder()
        for (char in text) {
            if (char in "\\[]()*_`<>#~") output.append('\\')
            output.append(char)
        }
        return output.toString()
    }
}
