package me.untreu.qiqstr.ui.dm

import android.text.format.DateFormat as AndroidDateFormat
import android.util.Patterns
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AttachFile
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Videocam
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import java.text.DateFormat
import java.text.Normalizer
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppLanguage
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Profile

object DMFormat {
    val locale: Locale get() = AppLanguage.locale

    private fun calendar(timestamp: Long) = Calendar.getInstance().apply { timeInMillis = timestamp * 1000 }

    private fun startOfDay(calendar: Calendar): Calendar = (calendar.clone() as Calendar).apply {
        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
    }

    private fun daysBetween(timestamp: Long): Int {
        val from = startOfDay(calendar(timestamp)).timeInMillis
        val to = startOfDay(Calendar.getInstance()).timeInMillis
        return Math.round((to - from) / 86_400_000.0).toInt()
    }

    private fun pattern(skeleton: String, date: Date): String =
        SimpleDateFormat(AndroidDateFormat.getBestDateTimePattern(locale, skeleton), locale).format(date)

    fun listTime(timestamp: Long): String {
        val days = daysBetween(timestamp)
        if (days <= 0) return time(timestamp)
        if (days == 1) return L("yesterday")
        if (days < 7) return L("daysAgo", "days" to maxOf(days, 1))
        return pattern("dMy", Date(timestamp * 1000))
    }

    fun time(timestamp: Long): String = DateFormat.getTimeInstance(DateFormat.SHORT, locale).format(Date(timestamp * 1000))

    fun dayStart(timestamp: Long): Long = startOfDay(calendar(timestamp)).timeInMillis / 1000

    fun sameDay(a: Long, b: Long): Boolean {
        val x = calendar(a)
        val y = calendar(b)
        return x.get(Calendar.YEAR) == y.get(Calendar.YEAR) && x.get(Calendar.DAY_OF_YEAR) == y.get(Calendar.DAY_OF_YEAR)
    }

    fun daySeparator(timestamp: Long): String {
        val days = daysBetween(timestamp)
        if (days == 0) return L("today")
        if (days == 1) return L("yesterday")
        val sameYear = calendar(timestamp).get(Calendar.YEAR) == Calendar.getInstance().get(Calendar.YEAR)
        return pattern(if (sameYear) "EEEEdMMMM" else "dMMMMy", Date(timestamp * 1000))
    }

    fun infoDate(timestamp: Long): String = pattern("EEEdMMMyjmmss", Date(timestamp * 1000))

    fun preview(message: DMMessage): Pair<ImageVector?, String> {
        if (!message.isFile) return null to message.content.replace("\n", " ")
        val file = message.file
        if (file?.isImage == true) return Icons.Outlined.Image to L("dmPhoto")
        if (file?.isVideo == true) return Icons.Outlined.Videocam to L("dmVideo")
        return Icons.Outlined.AttachFile to L("dmAttachment")
    }
}

val DMMessage.spokenSender: String
    get() = if (isMine) L("dmYou") else ProfileCache.profile(peer)?.bestName ?: Profile.shortNpub(peer)

object DMText {
    private val imageExtensions = setOf("jpg", "jpeg", "png", "gif", "webp")
    private val nostrPattern = Regex("nostr:(npub1|nprofile1|note1|nevent1|naddr1)[02-9ac-hj-np-z]+", RegexOption.IGNORE_CASE)

    fun isImageURL(value: String): Boolean {
        val uri = runCatching { java.net.URI(value) }.getOrNull() ?: return false
        if (uri.scheme?.startsWith("http") != true) return false
        val path = uri.path ?: return false
        return path.substringAfterLast('/').substringAfterLast('.', "").lowercase() in imageExtensions
    }

    fun fold(text: String): String {
        val builder = StringBuilder(text.length)
        for (char in text) {
            val decomposed = Normalizer.normalize(char.toString(), Normalizer.Form.NFD)
            builder.append((decomposed.firstOrNull() ?: char).lowercaseChar())
        }
        return builder.toString()
    }

    fun contains(text: String, query: String): Boolean = fold(text).contains(fold(query))

    fun attributed(text: String, mine: Boolean, highlighting: String, highlight: Color, linkColor: Color): AnnotatedString {
        val spans = mutableListOf<Triple<IntRange, String, String?>>()
        for (match in nostrPattern.findAll(text)) {
            val entity = match.value
            val bech = entity.drop(6)
            val label = if (bech.startsWith("npub1") || bech.startsWith("nprofile1")) {
                val hex = Nip19.pubkeyHex(bech)
                "@" + (hex?.let { ProfileCache.profile(it)?.bestName } ?: (bech.take(12) + "…"))
            } else {
                bech.take(14) + "…"
            }
            spans.add(Triple(match.range, entity, label))
        }
        val matcher = Patterns.WEB_URL.matcher(text)
        while (matcher.find()) {
            val range = matcher.start() until matcher.end()
            val raw = matcher.group()
            val lower = raw.lowercase()
            val url = when {
                lower.startsWith("http://") || lower.startsWith("https://") -> raw
                lower.startsWith("www.") -> "http://$raw"
                else -> continue
            }
            if (spans.any { it.first.first <= range.last && range.first <= it.first.last }) continue
            spans.add(Triple(range, url, null))
        }
        spans.sortBy { it.first.first }
        val base = buildAnnotatedString {
            var cursor = 0
            for ((range, url, label) in spans) {
                if (range.first > cursor) append(text.substring(cursor, range.first))
                val style = SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline, fontWeight = if (label != null) FontWeight.SemiBold else null)
                pushLink(LinkAnnotation.Clickable(url, TextLinkStyles(style)) { Router.openUrl(url) })
                append(label ?: text.substring(range.first, range.last + 1))
                pop()
                cursor = range.last + 1
            }
            if (cursor < text.length) append(text.substring(cursor))
        }
        val needle = fold(highlighting.trim())
        if (needle.isEmpty()) return base
        val folded = fold(base.text)
        return AnnotatedString.Builder(base).apply {
            var start = folded.indexOf(needle)
            while (start >= 0) {
                addStyle(SpanStyle(background = highlight.copy(alpha = if (mine) 0.55f else 0.3f)), start, start + needle.length)
                start = folded.indexOf(needle, start + needle.length)
            }
        }.toAnnotatedString()
    }
}
