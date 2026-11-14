package me.untreu.qiqstr.ui.articles

import androidx.compose.runtime.Immutable
import me.untreu.qiqstr.data.bridge.Nip19

@Immutable
sealed interface MarkdownBlock {
    data class Heading(val level: Int, val text: String) : MarkdownBlock
    data class Paragraph(val text: String) : MarkdownBlock
    data class Code(val language: String, val code: String) : MarkdownBlock
    data class Quote(val blocks: List<MarkdownBlock>) : MarkdownBlock
    data class ListBlock(val ordered: Boolean, val start: Int, val items: List<MarkdownListItem>) : MarkdownBlock
    data class Image(val url: String, val alt: String, val link: String?) : MarkdownBlock
    data class Table(val header: List<String>, val rows: List<List<String>>) : MarkdownBlock
    data class Nostr(val entity: String) : MarkdownBlock
    object Rule : MarkdownBlock

    val plainText: String
        get() = when (this) {
            is Heading -> MarkdownInline.plain(text)
            is Paragraph -> MarkdownInline.plain(text)
            is Code -> code
            is Quote -> blocks.joinToString("\n") { it.plainText }
            is ListBlock -> items.flatMap { it.blocks }.joinToString("\n") { it.plainText }
            is Table -> (listOf(header) + rows).flatten().joinToString("\n") { MarkdownInline.plain(it) }
            is Image, is Nostr, Rule -> ""
        }
}

@Immutable
data class MarkdownListItem(val checked: Boolean?, val blocks: List<MarkdownBlock>)

internal fun String.trimWs(): String = trim { it == ' ' || it == '\t' || (it.isWhitespace() && it != '\n' && it != '\r') }

object MarkdownParser {
    private const val MAX_DEPTH = 8
    private val pubkeyPattern = Regex("(?:npub1|nprofile1)[02-9ac-hj-np-z]{20,}")

    fun parse(text: String): List<MarkdownBlock> {
        val normalized = text.replace("\r\n", "\n").replace("\r", "\n").replace("\t", "    ")
        return parseBlocks(normalized.split("\n"))
    }

    fun pubkeys(text: String): List<String> =
        pubkeyPattern.findAll(text).mapNotNull { Nip19.pubkeyHex(it.value) }.distinct().toList()

    private fun parseBlocks(lines: List<String>, depth: Int = 0): List<MarkdownBlock> {
        if (depth >= MAX_DEPTH) return paragraphBlocks(lines.filter { it.trimWs().isNotEmpty() })
        val blocks = mutableListOf<MarkdownBlock>()
        val paragraph = mutableListOf<String>()
        var i = 0

        fun flush() {
            if (paragraph.isEmpty()) return
            blocks.addAll(paragraphBlocks(paragraph.toList()))
            paragraph.clear()
        }

        while (i < lines.size) {
            val line = lines[i]
            val trimmed = line.trimWs()

            if (trimmed.isEmpty()) {
                flush()
                i++
                continue
            }

            val fence = fenceMarker(trimmed)
            if (fence != null) {
                flush()
                val language = trimmed.drop(fence.length).trimWs()
                val indent = leadingSpaces(line)
                val code = mutableListOf<String>()
                i++
                while (i < lines.size) {
                    val candidate = lines[i].trimWs()
                    if (candidate.startsWith(fence) && candidate.all { it == fence[0] }) { i++; break }
                    code.add(dedent(lines[i], indent))
                    i++
                }
                blocks.add(MarkdownBlock.Code(language, code.joinToString("\n")))
                continue
            }

            val heading = atxHeading(trimmed)
            if (heading != null) {
                flush()
                blocks.add(MarkdownBlock.Heading(heading.first, heading.second))
                i++
                continue
            }

            if (paragraph.isNotEmpty() && trimmed.length >= 2 && trimmed.all { it == '=' }) {
                blocks.add(MarkdownBlock.Heading(1, paragraph.joinToString(" ") { it.trimWs() }))
                paragraph.clear()
                i++
                continue
            }

            if (paragraph.isNotEmpty() && trimmed.length >= 2 && trimmed.all { it == '-' }) {
                blocks.add(MarkdownBlock.Heading(2, paragraph.joinToString(" ") { it.trimWs() }))
                paragraph.clear()
                i++
                continue
            }

            if (isRule(trimmed)) {
                flush()
                blocks.add(MarkdownBlock.Rule)
                i++
                continue
            }

            if (trimmed.startsWith(">")) {
                flush()
                val inner = mutableListOf<String>()
                while (i < lines.size) {
                    val candidate = lines[i].trimWs()
                    if (candidate.startsWith(">")) {
                        var stripped = candidate.drop(1)
                        if (stripped.startsWith(" ")) stripped = stripped.drop(1)
                        inner.add(stripped)
                    } else if (candidate.isNotEmpty() && (inner.lastOrNull() ?: "").trimWs().isNotEmpty() && !startsBlock(lines[i])) {
                        inner.add(candidate)
                    } else {
                        break
                    }
                    i++
                }
                blocks.add(MarkdownBlock.Quote(parseBlocks(inner, depth + 1)))
                continue
            }

            val marker = listMarker(line)
            if (marker != null && (paragraph.isEmpty() || !marker.ordered || marker.number == 1)) {
                flush()
                val (list, next) = parseList(lines, i, marker, depth)
                blocks.add(list)
                i = next
                continue
            }

            if (paragraph.isEmpty() && i + 1 < lines.size && trimmed.contains("|") && isTableSeparator(lines[i + 1])) {
                val header = tableCells(trimmed)
                val rows = mutableListOf<List<String>>()
                i += 2
                while (i < lines.size) {
                    val rowLine = lines[i].trimWs()
                    if (rowLine.isEmpty() || !rowLine.contains("|")) break
                    var cells = tableCells(rowLine)
                    if (cells.size < header.size) cells = cells + List(header.size - cells.size) { "" }
                    rows.add(cells.take(header.size))
                    i++
                }
                blocks.add(MarkdownBlock.Table(header, rows))
                continue
            }

            if (paragraph.isEmpty() && leadingSpaces(line) >= 4) {
                val code = mutableListOf<String>()
                while (i < lines.size) {
                    val candidate = lines[i]
                    if (candidate.trimWs().isEmpty()) {
                        code.add("")
                    } else if (leadingSpaces(candidate) >= 4) {
                        code.add(dedent(candidate, 4))
                    } else {
                        break
                    }
                    i++
                }
                while (code.lastOrNull()?.isEmpty() == true) code.removeAt(code.lastIndex)
                blocks.add(MarkdownBlock.Code("", code.joinToString("\n")))
                continue
            }

            paragraph.add(line)
            i++
        }
        flush()
        return blocks
    }

    private data class ListMarker(val ordered: Boolean, val number: Int, val indent: Int, val contentOffset: Int, val content: String)

    private fun listMarker(line: String): ListMarker? {
        val indent = leadingSpaces(line)
        val rest = line.drop(indent)
        val first = rest.firstOrNull() ?: return null
        if (first in "-*+") {
            val after = rest.drop(1)
            if (after.isNotEmpty() && after[0] != ' ') return null
            val spaces = minOf(4, after.takeWhile { it == ' ' }.length)
            return ListMarker(false, 1, indent, indent + 1 + maxOf(1, spaces), after.dropWhile { it == ' ' })
        }
        val digits = rest.takeWhile { it.isDigit() }
        if (digits.isEmpty() || digits.length > 9) return null
        val after = rest.drop(digits.length)
        val delimiter = after.firstOrNull() ?: return null
        if (delimiter != '.' && delimiter != ')') return null
        val tail = after.drop(1)
        if (tail.isNotEmpty() && tail[0] != ' ') return null
        val spaces = minOf(4, tail.takeWhile { it == ' ' }.length)
        return ListMarker(true, digits.toIntOrNull() ?: 1, indent, indent + digits.length + 1 + maxOf(1, spaces), tail.dropWhile { it == ' ' })
    }

    private fun parseList(lines: List<String>, start: Int, first: ListMarker, depth: Int): Pair<MarkdownBlock, Int> {
        val items = mutableListOf<MarkdownListItem>()
        val current = mutableListOf<String>()
        var contentOffset = first.contentOffset
        var i = start
        var previousBlank = false
        var started = false

        fun finishItem() {
            if (!started) return
            val linesForItem = current.toMutableList()
            var checked: Boolean? = null
            val head = linesForItem.firstOrNull()
            if (head != null) {
                val lower = head.lowercase()
                if (lower.startsWith("[ ] ") || lower == "[ ]") { checked = false; linesForItem[0] = head.drop(3).trimWs() }
                else if (lower.startsWith("[x] ") || lower == "[x]") { checked = true; linesForItem[0] = head.drop(3).trimWs() }
            }
            items.add(MarkdownListItem(checked, parseBlocks(linesForItem, depth + 1)))
            current.clear()
        }

        while (i < lines.size) {
            val line = lines[i]
            val trimmed = line.trimWs()
            if (trimmed.isEmpty()) {
                var j = i + 1
                while (j < lines.size && lines[j].trimWs().isEmpty()) j++
                if (j >= lines.size) break
                val nextLine = lines[j]
                val nextMarker = listMarker(nextLine)
                val continues = leadingSpaces(nextLine) >= contentOffset || (nextMarker != null && nextMarker.ordered == first.ordered && nextMarker.indent < contentOffset)
                if (!continues) break
                current.add("")
                previousBlank = true
                i++
                continue
            }
            val marker = listMarker(line)
            if (marker != null && marker.indent < contentOffset && !isRule(trimmed)) {
                if (marker.ordered != first.ordered || marker.indent > first.indent + 3) break
                finishItem()
                started = true
                contentOffset = marker.contentOffset
                current.clear()
                current.add(marker.content)
                previousBlank = false
                i++
                continue
            }
            if (leadingSpaces(line) >= contentOffset) {
                current.add(dedent(line, contentOffset))
            } else if (!previousBlank && !startsBlock(line)) {
                current.add(trimmed)
            } else {
                break
            }
            previousBlank = false
            i++
        }
        finishItem()
        return MarkdownBlock.ListBlock(first.ordered, first.number, items) to i
    }

    private sealed interface Segment {
        data class Text(val value: String) : Segment
        data class Img(val url: String, val alt: String, val link: String?) : Segment
    }

    private fun paragraphBlocks(lines: List<String>): List<MarkdownBlock> {
        val blocks = mutableListOf<MarkdownBlock>()
        val text = StringBuilder()
        fun flushText() {
            val cleaned = text.toString().trim()
            if (cleaned.isNotEmpty()) blocks.add(MarkdownBlock.Paragraph(cleaned))
            text.clear()
        }
        lines.forEachIndexed { index, raw ->
            val trimmed = raw.trimWs()
            val entity = standaloneEntity(trimmed)
            if (entity != null) {
                flushText()
                blocks.add(MarkdownBlock.Nostr(entity))
                return@forEachIndexed
            }
            if (isImageURL(trimmed)) {
                flushText()
                blocks.add(MarkdownBlock.Image(trimmed, "", null))
                return@forEachIndexed
            }
            val segments = splitImages(trimmed)
            if (segments.size == 1 && segments[0] is Segment.Text) {
                val hardBreak = raw.endsWith("  ") || raw.endsWith("\\")
                var piece = trimmed
                if (piece.endsWith("\\")) piece = piece.dropLast(1)
                if (text.isNotEmpty() && !text.endsWith("\n")) text.append(' ')
                text.append(piece)
                if (hardBreak && index < lines.size - 1) text.append('\n')
                return@forEachIndexed
            }
            for (segment in segments) {
                when (segment) {
                    is Segment.Text -> {
                        if (text.isNotEmpty() && !text.endsWith("\n")) text.append(' ')
                        text.append(segment.value)
                    }
                    is Segment.Img -> {
                        flushText()
                        blocks.add(MarkdownBlock.Image(segment.url, segment.alt, segment.link))
                    }
                }
            }
        }
        flushText()
        return blocks
    }

    private val linkedImage = Regex("""\[!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)\]\(\s*([^)\s]+)\s*\)""")
    private val image = Regex("""!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)""")

    private fun splitImages(text: String): List<Segment> {
        if (!text.contains("![")) return listOf(Segment.Text(text))
        val matches = mutableListOf<Pair<IntRange, Segment>>()
        for (m in linkedImage.findAll(text)) {
            matches.add(m.range to Segment.Img(m.groupValues[2], m.groupValues[1], m.groupValues[3]))
        }
        for (m in image.findAll(text)) {
            if (matches.any { it.first.first <= m.range.last && m.range.first <= it.first.last }) continue
            matches.add(m.range to Segment.Img(m.groupValues[2], m.groupValues[1], null))
        }
        if (matches.isEmpty()) return listOf(Segment.Text(text))
        matches.sortBy { it.first.first }
        val segments = mutableListOf<Segment>()
        var cursor = 0
        for ((range, segment) in matches) {
            if (range.first > cursor) {
                val piece = text.substring(cursor, range.first).trimWs()
                if (piece.isNotEmpty()) segments.add(Segment.Text(piece))
            }
            segments.add(segment)
            cursor = range.last + 1
        }
        if (cursor < text.length) {
            val piece = text.substring(cursor).trimWs()
            if (piece.isNotEmpty()) segments.add(Segment.Text(piece))
        }
        return segments
    }

    private val entityPattern = Regex("^(?:nostr:)?((?:note1|nevent1|naddr1|npub1|nprofile1)[02-9ac-hj-np-z]{20,})$")

    private fun standaloneEntity(text: String): String? = entityPattern.find(text)?.groupValues?.get(1)

    fun isImageURL(text: String): Boolean {
        if (!text.startsWith("http") || text.contains(" ")) return false
        val path = runCatching { java.net.URI(text).path }.getOrNull() ?: return false
        val ext = path.substringAfterLast('.', "").lowercase()
        return ext in setOf("jpg", "jpeg", "png", "gif", "webp", "avif", "heic")
    }

    private fun fenceMarker(trimmed: String): String? {
        for (char in charArrayOf('`', '~')) {
            val run = trimmed.takeWhile { it == char }
            if (run.length >= 3) {
                if (char == '`' && trimmed.drop(run.length).contains('`')) return null
                return run
            }
        }
        return null
    }

    private fun atxHeading(trimmed: String): Pair<Int, String>? {
        val hashes = trimmed.takeWhile { it == '#' }.length
        if (hashes !in 1..6) return null
        val rest = trimmed.drop(hashes)
        if (rest.isNotEmpty() && rest[0] != ' ') return null
        var text = rest.trimWs()
        while (text.endsWith("#")) text = text.dropLast(1)
        return hashes to text.trimWs()
    }

    private fun isRule(trimmed: String): Boolean {
        val compact = trimmed.replace(" ", "")
        if (compact.length < 3) return false
        val first = compact[0]
        if (first !in "-*_") return false
        return compact.all { it == first }
    }

    private fun isTableSeparator(line: String): Boolean {
        val trimmed = line.trimWs()
        if (!trimmed.contains("-")) return false
        val cells = tableCells(trimmed)
        return cells.isNotEmpty() && cells.all { cell ->
            val c = cell.trimWs()
            c.isNotEmpty() && c.all { it in "-:" } && c.contains("-")
        }
    }

    private fun tableCells(line: String): List<String> {
        var row = line
        if (row.startsWith("|")) row = row.drop(1)
        if (row.endsWith("|")) row = row.dropLast(1)
        return row.split("|").map { it.trimWs() }
    }

    private fun startsBlock(line: String): Boolean {
        val trimmed = line.trimWs()
        return fenceMarker(trimmed) != null || atxHeading(trimmed) != null || isRule(trimmed) || trimmed.startsWith(">") || listMarker(line) != null
    }

    private fun leadingSpaces(line: String): Int = line.takeWhile { it == ' ' }.length

    private fun dedent(line: String, count: Int): String = line.drop(minOf(count, leadingSpaces(line)))
}
