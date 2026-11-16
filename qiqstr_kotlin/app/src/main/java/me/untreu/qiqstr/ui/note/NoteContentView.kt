package me.untreu.qiqstr.ui.note

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import me.untreu.qiqstr.core.components.CustomEmojiImage
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.MediaPolicy
import me.untreu.qiqstr.data.services.NotePoll
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Note

@Composable
fun NoteContentView(
    note: Note,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.bodyLarge,
    selectable: Boolean = false,
    expandedByDefault: Boolean = false,
) {
    val content = remember(note.id) { NoteContentCache.content(note) }
    var expanded by rememberSaveable(note.id) { mutableStateOf(false) }
    val isTruncated = content.truncatedSegments != null && !expanded && !expandedByDefault
    val poll = remember(note.id) { NotePoll.from(note.id, note.tags) }
    LaunchedEffect(content.mentionPubkeys) {
        val missing = content.mentionPubkeys.filter { ProfileCache.profile(it) == null }
        if (missing.isNotEmpty()) ProfileCache.load(missing)
    }
    NoteSensitiveCover(note.id, content.contentWarning, modifier) {
        Column(Modifier.fillMaxWidth().animateContentSize(tween(250)), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (!content.isEmptyText) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    val segments = if (isTruncated) content.truncatedSegments ?: content.segments else content.segments
                    val text = content.annotated(segments, AppColors.link, ProfileCache.profiles)
                    val inline = emojiInlineContent(content, segments)
                    val textStyle = style.copy(color = AppColors.textPrimary, lineHeight = 1.35.em)
                    if (selectable) {
                        SelectionContainer { Text(text, style = textStyle, inlineContent = inline, modifier = Modifier.fillMaxWidth()) }
                    } else {
                        Text(text, style = textStyle, inlineContent = inline, modifier = Modifier.fillMaxWidth())
                    }
                    if (isTruncated) {
                        Text(
                            L("feedShowMore"),
                            style = style,
                            fontWeight = FontWeight.SemiBold,
                            color = AppColors.link,
                            modifier = Modifier.clickable { expanded = true }.testTag("note-show-more"),
                        )
                    }
                }
            }
            if (poll != null) NotePollView(poll, note.pubkey)
            ZapGoal.from(note)?.let { ZapGoalView(it, note) }
            if (content.media.isNotEmpty()) NoteMediaGrid(content.media)
            content.audio.forEach { NoteAudioView(it) }
            content.previewLink?.let { if (!MediaPolicy.defersMedia) NoteLinkPreview(it) }
            content.quoteIds.forEach { NoteQuoteCard(it) }
            content.articleIds.forEach { NoteArticleCard(it) }
        }
    }
}

fun emojiInlineContent(content: NoteContent, segments: List<NoteContentSegment>): Map<String, InlineTextContent> = content.inlineEmojis(segments).mapValues { (url, _) ->
    InlineTextContent(Placeholder(1.2.em, 1.2.em, PlaceholderVerticalAlign.TextCenter)) { CustomEmojiImage(url, 22.dp) }
}
