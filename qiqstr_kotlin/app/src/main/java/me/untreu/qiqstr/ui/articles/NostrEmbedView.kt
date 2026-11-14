package me.untreu.qiqstr.ui.articles

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Article
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Article
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.note.NoteRow

private val embedShape = RoundedCornerShape(18.dp)

@Composable
fun NostrEmbedView(entity: String) {
    val pubkey = if (entity.startsWith("npub1") || entity.startsWith("nprofile1")) Nip19.pubkeyHex(entity) else null
    when {
        pubkey != null -> ProfileEmbed(pubkey)
        entity.startsWith("naddr1") -> ArticleEmbed(entity)
        else -> {
            val id = remember(entity) { Nip19.decode(entity) }
            if (id != null) NoteEmbed(id) else MarkdownText(entity)
        }
    }
}

@Composable
private fun ProfileEmbed(pubkey: String) {
    val profile = ProfileCache.profiles[pubkey]
    Row(
        Modifier
            .fillMaxWidth()
            .clip(embedShape)
            .background(AppColors.inputFill)
            .clickable { Router.push(Route.Profile(pubkey)) }
            .padding(12.dp)
            .testTag("markdown-profile-$pubkey"),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ProfileAvatar(pubkey, size = 44.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(profile?.bestName ?: Profile.shortNpub(pubkey), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary)
            profile?.nip05?.ifEmpty { null }?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null, tint = AppColors.textTertiary)
    }
}

@Composable
private fun ArticleEmbed(naddr: String) {
    var article by remember(naddr) { mutableStateOf<Article?>(null) }
    var failed by remember(naddr) { mutableStateOf(false) }
    LaunchedEffect(naddr) {
        val address = ArticleAddress.from(naddr)
        if (address == null) { failed = true; return@LaunchedEffect }
        val local = ArticleService.article(address)
        if (local != null) { article = local; return@LaunchedEffect }
        article = ArticleService.fetch(address)
        failed = article == null
    }
    val loaded = article
    Column(Modifier.testTag("markdown-article-embed")) {
        when {
            loaded != null -> CompactArticleCard(loaded, Modifier.clip(embedShape).clickable { Router.push(Route.Article(loaded.id)) })
            failed -> EmbedPlaceholder(Icons.AutoMirrored.Outlined.Article, L("articleNotFound"), Modifier.clickable { Router.push(Route.ArticleAddress(naddr)) })
            else -> EmbedPlaceholder(Icons.AutoMirrored.Outlined.Article, L("loading"), loading = true)
        }
    }
}

@Composable
private fun NoteEmbed(noteId: String) {
    var note by remember(noteId) { mutableStateOf<Note?>(null) }
    var failed by remember(noteId) { mutableStateOf(false) }
    LaunchedEffect(noteId) {
        note = ArticleService.note(noteId)
        failed = note == null
    }
    val loaded = note
    Column(Modifier.testTag("markdown-note-embed")) {
        when {
            loaded != null -> NoteRow(
                note = loaded,
                modifier = Modifier.clip(embedShape).background(AppColors.surface).border(1.dp, AppColors.border, embedShape),
            )
            failed -> EmbedPlaceholder(Icons.AutoMirrored.Outlined.Chat, L("noteNotFound"), Modifier.clickable { Router.push(Route.Thread(noteId)) })
            else -> EmbedPlaceholder(Icons.AutoMirrored.Outlined.Chat, L("loading"), loading = true)
        }
    }
}

@Composable
private fun EmbedPlaceholder(icon: ImageVector, title: String, modifier: Modifier = Modifier, loading: Boolean = false) {
    Row(
        Modifier.fillMaxWidth().clip(embedShape).background(AppColors.inputFill).then(modifier).padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (loading) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = AppColors.textSecondary)
        else Icon(icon, null, tint = AppColors.textSecondary)
        Text(title, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
        Spacer(Modifier.weight(1f))
    }
}
