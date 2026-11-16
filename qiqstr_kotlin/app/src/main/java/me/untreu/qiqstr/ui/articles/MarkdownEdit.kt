package me.untreu.qiqstr.ui.articles

import java.text.Normalizer
import java.util.Locale
import java.util.UUID

enum class MarkdownStyle(val key: String, val symbol: String) {
    BOLD("articleFormatBold", "B"), ITALIC("articleFormatItalic", "I"), HEADING("articleFormatHeading", "H"),
    QUOTE("articleFormatQuote", "❞"), BULLET("articleFormatBullets", "•"), NUMBERED("articleFormatNumbers", "1."),
    LINK("articleFormatLink", "↗"), CODE("articleFormatCode", "<>"),
}

data class MarkdownEdit(val text: String, val caret: Int) {
    companion object {
        fun apply(style: MarkdownStyle, text: String, start: Int, end: Int = start): MarkdownEdit {
            val low = minOf(start, end).coerceIn(0, text.length)
            val high = maxOf(start, end).coerceIn(low, text.length)
            val selected = text.substring(low, high)
            val marker = when (style) { MarkdownStyle.BOLD -> "**"; MarkdownStyle.ITALIC -> "*"; MarkdownStyle.CODE -> "`"; else -> null }
            if (marker != null) return MarkdownEdit(text.replaceRange(low, high, "$marker$selected$marker"), low + marker.length + if (selected.isEmpty()) 0 else selected.length + marker.length)
            if (style == MarkdownStyle.LINK) {
                val url = selected.startsWith("http://") || selected.startsWith("https://")
                val snippet = if (url) "[]($selected)" else "[$selected](https://)"
                return MarkdownEdit(text.replaceRange(low, high, snippet), low + if (url || selected.isEmpty()) 1 else snippet.length - 1)
            }
            val prefix = when (style) { MarkdownStyle.HEADING -> "## "; MarkdownStyle.QUOTE -> "> "; MarkdownStyle.BULLET -> "- "; else -> "1. " }
            val lineStart = text.substring(0, low).lastIndexOf('\n') + 1
            return if (text.startsWith(prefix, lineStart)) MarkdownEdit(text.removeRange(lineStart, lineStart + prefix.length), maxOf(lineStart, low - prefix.length))
            else MarkdownEdit(text.replaceRange(lineStart, lineStart, prefix), low + prefix.length)
        }

        fun image(url: String, text: String, start: Int, end: Int = start): MarkdownEdit {
            val low = minOf(start, end).coerceIn(0, text.length)
            val high = maxOf(start, end).coerceIn(low, text.length)
            val before = text.substring(0, low)
            val lead = when { before.isEmpty() || before.endsWith("\n\n") -> ""; before.endsWith("\n") -> "\n"; else -> "\n\n" }
            val snippet = "$lead![]($url)\n\n"
            return MarkdownEdit(text.replaceRange(low, high, snippet), low + snippet.length)
        }
    }
}

object ArticleIdentifier {
    fun make(title: String, suffix: String = UUID.randomUUID().toString().replace("-", "").take(6)): String {
        val folded = Normalizer.normalize(title, Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "").lowercase(Locale.ROOT)
        val slug = buildString {
            for (char in folded) {
                if (char in 'a'..'z' || char in '0'..'9') append(char)
                else if (isNotEmpty() && last() != '-') append('-')
                if (length >= 48) break
            }
        }.trimEnd('-')
        return if (slug.isEmpty()) suffix else "$slug-$suffix"
    }
    fun hashtags(text: String): List<String> = text.split(Regex("[,\\s]+")).map { it.trim('#').lowercase(Locale.ROOT) }.filter { it.isNotEmpty() }.distinct()
}
