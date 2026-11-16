package me.untreu.qiqstr.ui.note

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Article
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.PlayCircleOutline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.IconTile
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.RemoteImage
import me.untreu.qiqstr.data.services.NotePoll
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Article
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile

object NoteEmbeddedCache {
    val notes = HashMap<String, Note>()
    val articles = HashMap<String, Article>()
    val attempted = HashMap<String, Long>()
}

@Composable
fun NoteQuoteCard(noteId: String, modifier: Modifier = Modifier, depth: Int = 0, preloaded: Note? = null) {
    var note by remember(noteId) { mutableStateOf(preloaded ?: NoteEmbeddedCache.notes[noteId]) }
    var failed by remember(noteId) { mutableStateOf(false) }
    LaunchedEffect(noteId) {
        if (note != null) return@LaunchedEffect
        NoteRepository.note(noteId)?.let {
            NoteEmbeddedCache.notes[noteId] = it
            note = it
            return@LaunchedEffect
        }
        val last = NoteEmbeddedCache.attempted[noteId]
        if (last != null && System.currentTimeMillis() - last < 60_000) {
            delay(3000)
            val loaded = NoteEmbeddedCache.notes[noteId]
            if (loaded != null) note = loaded else failed = true
            return@LaunchedEffect
        }
        NoteEmbeddedCache.attempted[noteId] = System.currentTimeMillis()
        try {
            val loaded = NoteRepository.ensureNote(noteId)
            if (loaded != null) {
                NoteEmbeddedCache.notes[noteId] = loaded
                note = loaded
            } else {
                failed = true
            }
        } catch (cancel: kotlinx.coroutines.CancellationException) {
            NoteEmbeddedCache.attempted.remove(noteId)
            throw cancel
        }
    }
    val current = note
    when {
        current != null && isHidden(current) -> Placeholder(L("noteHiddenMuted"), modifier)
        current != null -> QuoteContent(current, depth, modifier)
        failed -> Placeholder(L("eventNotFound"), modifier)
        else -> Placeholder(null, modifier)
    }
}

private fun isHidden(note: Note): Boolean {
    if (NoteInteractionStore.isDeleted(note.id) || note.pubkey in Session.mutedPubkeys) return true
    val words = Session.mutedWords
    if (words.isEmpty()) return false
    val content = note.content.lowercase()
    return words.any { it.isNotEmpty() && content.contains(it) }
}

@Composable
private fun Placeholder(text: String?, modifier: Modifier) {
    Surface(shape = RoundedCornerShape(16.dp), color = AppColors.inputFill, modifier = modifier.fillMaxWidth().heightIn(min = 52.dp)) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (text != null) {
                Icon(Icons.Outlined.ErrorOutline, null, Modifier.size(18.dp), tint = AppColors.textSecondary)
                Text(text, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
            } else {
                CircularProgressIndicator(Modifier.size(18.dp), color = AppColors.textSecondary, strokeWidth = 2.dp)
            }
        }
    }
}

@Composable
private fun QuoteContent(note: Note, depth: Int, modifier: Modifier) {
    val parsed = remember(note.id) { NoteContentCache.content(note) }
    val name = ProfileCache.profiles[note.pubkey]?.bestName ?: note.authorName ?: Profile.shortNpub(note.pubkey)
    val shape = RoundedCornerShape(16.dp)
    Surface(
        onClick = { Router.push(Route.Thread(note.id)) },
        shape = shape,
        color = AppColors.inputFill.copy(alpha = 0.6f),
        border = BorderStroke(0.5.dp, AppColors.border),
        modifier = modifier.fillMaxWidth().testTag("note-quote-card"),
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ProfileAvatar(note.pubkey, size = 22.dp, fallbackUrl = note.authorImage)
                Text(name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                Text("· ${TimeFormat.relative(note.createdAt)}", style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, maxLines = 1)
            }
            NoteSensitiveCover(note.id, parsed.contentWarning, compact = true) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (!parsed.isEmptyText) {
                        val text = parsed.annotated(parsed.truncatedSegments ?: parsed.segments, AppColors.link, ProfileCache.profiles)
                        Text(text, inlineContent = emojiInlineContent(parsed, parsed.truncatedSegments ?: parsed.segments), style = MaterialTheme.typography.bodyMedium, color = AppColors.textPrimary, maxLines = 6, overflow = TextOverflow.Ellipsis)
                    }
                    NotePoll.from(note.id, note.tags)?.let { NotePollView(it, note.pubkey, interactive = false) }
                    ZapGoal.from(note)?.let { ZapGoalView(it, note) }
                    val image = parsed.images.firstOrNull()
                    if (image != null) {
                        NoteMediaImage(image, Modifier.fillMaxWidth().height(150.dp).clip(RoundedCornerShape(12.dp)))
                    } else if (parsed.videos.isNotEmpty()) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(Icons.Outlined.PlayCircleOutline, null, Modifier.size(16.dp), tint = AppColors.textSecondary)
                            Text(L("videoTapToPlay"), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
                        }
                    }
                }
            }
            if (depth == 0) parsed.quoteIds.firstOrNull()?.let { NoteQuoteCard(it, depth = depth + 1) }
        }
    }
}

@Composable
fun NoteArticleCard(naddr: String, modifier: Modifier = Modifier) {
    var article by remember(naddr) { mutableStateOf(NoteEmbeddedCache.articles[naddr]) }
    var failed by remember(naddr) { mutableStateOf(false) }
    LaunchedEffect(naddr) {
        if (article != null) return@LaunchedEffect
        val loaded = NoteRepository.article(naddr)
        if (loaded != null) {
            NoteEmbeddedCache.articles[naddr] = loaded
            article = loaded
        } else {
            failed = true
        }
    }
    val current = article
    Surface(
        onClick = { Router.push(Route.ArticleAddress(naddr)) },
        shape = RoundedCornerShape(16.dp),
        color = AppColors.inputFill,
        modifier = modifier.fillMaxWidth().testTag("note-article-card"),
    ) {
        Row(Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            val image = current?.image
            if (image != null) {
                RemoteImage(image, Modifier.size(72.dp).clip(RoundedCornerShape(12.dp)))
            } else {
                IconTile(Icons.Outlined.Article, size = 72.dp, tint = AppColors.textSecondary)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(L("article"), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = AppColors.textSecondary)
                val title = current?.let { if (it.title.isEmpty()) L("untitledArticle") else it.title } ?: if (failed) L("articleNotFound") else L("article")
                Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (current != null) {
                    Text(
                        ProfileCache.profiles[current.pubkey]?.bestName ?: current.authorName ?: Profile.shortNpub(current.pubkey),
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textSecondary,
                        maxLines = 1,
                    )
                } else if (!failed) {
                    CircularProgressIndicator(Modifier.size(12.dp), color = AppColors.textSecondary, strokeWidth = 1.5.dp)
                }
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = AppColors.textSecondary)
        }
    }
}
