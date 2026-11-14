package me.untreu.qiqstr.ui.profile

import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Profile

sealed interface BioToken {
    data class Text(val text: String) : BioToken
    data class ProfileRef(val pubkey: String) : BioToken
    data class NoteRef(val id: String) : BioToken
    data class ArticleRef(val naddr: String) : BioToken
    data class Hashtag(val tag: String) : BioToken
    data class Link(val url: String, val raw: String) : BioToken
}

object BioParser {
    private const val BECH = "[02-9ac-hj-np-z]"
    private val regex = Regex(
        "(?:nostr:)?((?:npub1|note1)$BECH{58}|(?:nprofile1|nevent1|naddr1)$BECH{20,})|(https?://[^\\s<>\"]+)|(?<![\\p{L}\\p{N}_&/])#([\\p{L}\\p{N}_]{1,64})",
        RegexOption.IGNORE_CASE,
    )

    fun tokens(text: String): List<BioToken> {
        val result = mutableListOf<BioToken>()
        var cursor = 0
        for (match in regex.findAll(text)) {
            val start = match.range.first
            var end = match.range.last + 1
            val entity = match.groups[1]
            val link = match.groups[2]
            val tag = match.groups[3]
            val token: BioToken? = when {
                entity != null -> entity(entity.value)
                link != null -> {
                    var raw = link.value
                    while (raw.isNotEmpty() && raw.last() in ".,;:!?)]}'\"") {
                        raw = raw.dropLast(1)
                        end -= 1
                    }
                    BioToken.Link(raw, raw)
                }
                tag != null -> BioToken.Hashtag(tag.value)
                else -> null
            }
            if (token == null) continue
            if (start > cursor) result.add(BioToken.Text(text.substring(cursor, start)))
            result.add(token)
            cursor = end
        }
        if (cursor < text.length) result.add(BioToken.Text(text.substring(cursor)))
        return result
    }

    private fun entity(raw: String): BioToken? {
        val lower = raw.lowercase()
        if (lower.startsWith("npub1") || lower.startsWith("nprofile1")) return Nip19.pubkeyHex(lower)?.let { BioToken.ProfileRef(it) }
        if (lower.startsWith("note1") || lower.startsWith("nevent1")) return Nip19.decode(lower)?.let { BioToken.NoteRef(it) }
        if (lower.startsWith("naddr1")) return BioToken.ArticleRef(lower)
        return null
    }

    fun prettyLink(raw: String): String {
        var s = raw
        for (prefix in listOf("https://", "http://")) if (s.startsWith(prefix)) s = s.removePrefix(prefix)
        if (s.startsWith("www.")) s = s.removePrefix("www.")
        if (s.endsWith("/")) s = s.dropLast(1)
        return if (s.length > 42) "${s.take(40)}…" else s
    }
}

@Composable
fun ProfileBioText(text: String, modifier: Modifier = Modifier, style: TextStyle = MaterialTheme.typography.bodyMedium) {
    val tokens = remember(text) { BioParser.tokens(text) }
    LaunchedEffect(text) {
        val pubkeys = tokens.filterIsInstance<BioToken.ProfileRef>().map { it.pubkey }
        if (pubkeys.isNotEmpty()) ProfileCache.load(pubkeys)
    }
    val linkColor = AppColors.link
    val annotated = buildAnnotatedString {
        fun linked(label: String, weight: FontWeight, underline: Boolean = false, onClick: () -> Unit) {
            val styles = TextLinkStyles(SpanStyle(color = linkColor, fontWeight = weight, textDecoration = if (underline) TextDecoration.Underline else null))
            withLink(LinkAnnotation.Clickable(label, styles) { onClick() }) { append(label) }
        }
        for (token in tokens) {
            when (token) {
                is BioToken.Text -> append(token.text)
                is BioToken.ProfileRef -> {
                    val name = ProfileCache.profiles[token.pubkey]?.bestName ?: Profile.shortNpub(token.pubkey)
                    linked("@$name", FontWeight.SemiBold) { Router.push(Route.Profile(token.pubkey)) }
                }
                is BioToken.NoteRef -> linked(Nip19.note(token.id)?.let { "${it.take(14)}…" } ?: token.id, FontWeight.Medium) {
                    Router.push(Route.Thread(token.id))
                }
                is BioToken.ArticleRef -> linked("${token.naddr.take(14)}…", FontWeight.Medium) { Router.push(Route.ArticleAddress(token.naddr)) }
                is BioToken.Hashtag -> linked("#${token.tag}", FontWeight.SemiBold) { Router.push(Route.Hashtag(token.tag)) }
                is BioToken.Link -> linked(BioParser.prettyLink(token.raw), FontWeight.Normal, underline = true) { Router.openUrl(token.url) }
            }
        }
    }
    SelectionContainer(modifier) {
        Text(annotated, style = style, color = AppColors.textPrimary)
    }
}
