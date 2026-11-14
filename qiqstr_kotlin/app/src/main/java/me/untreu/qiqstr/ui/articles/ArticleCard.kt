package me.untreu.qiqstr.ui.articles

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Article
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.OpenInBrowser
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.VolumeOff
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
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
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.IconTile
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.RemoteImage
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Article
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.note.Moderation

private val cardShape = RoundedCornerShape(20.dp)

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ArticleCard(article: Article, modifier: Modifier = Modifier) {
    var menu by remember { mutableStateOf(false) }
    val authorName = ProfileCache.profiles[article.pubkey]?.bestName ?: article.authorName?.ifEmpty { null } ?: Profile.shortNpub(article.pubkey)
    Box(modifier) {
        Column(
            Modifier
                .fillMaxWidth()
                .clip(cardShape)
                .background(AppColors.inputFill)
                .combinedClickable(onClick = { Router.push(Route.Article(article.id)) }, onLongClick = { menu = true })
                .testTag("article-card-${article.id}"),
        ) {
            val image = article.image?.ifEmpty { null }
            if (image != null) {
                RemoteImage(image, Modifier.fillMaxWidth().aspectRatio(16f / 9f))
            }
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    article.displayTitle,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = AppColors.textPrimary,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                )
                article.summary?.ifEmpty { null }?.let {
                    Text(it, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
                Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(
                        Modifier.clip(RoundedCornerShape(8.dp)).clickable { Router.push(Route.Profile(article.pubkey)) }.testTag("article-card-author-${article.id}"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        ProfileAvatar(article.pubkey, size = 20.dp, fallbackUrl = article.authorImage)
                        Text(authorName, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    }
                    Text("·", style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
                    Text(TimeFormat.relative(article.publishedAt), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, maxLines = 1)
                    Spacer(Modifier.weight(1f))
                    Text(L("exploreMinRead", "count" to article.readingMinutes), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, maxLines = 1)
                }
            }
        }
        ArticleMenu(article, menu) { menu = false }
    }
}

@Composable
fun ArticleCardSkeleton(modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().clip(cardShape).background(AppColors.inputFill)) {
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).background(AppColors.tile))
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.fillMaxWidth(0.8f).height(18.dp).clip(RoundedCornerShape(6.dp)).background(AppColors.tile))
            Box(Modifier.fillMaxWidth().height(14.dp).clip(RoundedCornerShape(6.dp)).background(AppColors.tile))
            Box(Modifier.fillMaxWidth(0.6f).height(14.dp).clip(RoundedCornerShape(6.dp)).background(AppColors.tile))
            Box(Modifier.padding(top = 6.dp).width(120.dp).height(12.dp).clip(RoundedCornerShape(6.dp)).background(AppColors.tile))
        }
    }
}

@Composable
fun ArticleMenu(article: Article, expanded: Boolean, onDismiss: () -> Unit) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        MenuItem(L("read"), Icons.AutoMirrored.Outlined.MenuBook) { onDismiss(); Router.push(Route.Article(article.id)) }
        MenuItem(L("exploreViewAuthor"), Icons.Outlined.AccountCircle) { onDismiss(); Router.push(Route.Profile(article.pubkey)) }
        article.naddr?.let { naddr ->
            MenuItem(L("share"), Icons.Outlined.Share) { onDismiss(); ArticleActions.share("nostr:$naddr") }
            MenuItem(L("exploreCopyArticleLink"), Icons.Outlined.Link) { onDismiss(); ArticleActions.copy("nostr:$naddr") }
        }
        article.shareURL?.let { url ->
            MenuItem(L("exploreOpenInBrowser"), Icons.Outlined.OpenInBrowser) { onDismiss(); Router.openUrl(url) }
        }
        if (article.pubkey != Session.pubkey) {
            HorizontalDivider()
            MenuItem(L("feedMuteAuthor"), Icons.Outlined.VolumeOff, destructive = true) {
                onDismiss()
                ArticleActions.mute(article.pubkey)
            }
        }
    }
}

@Composable
internal fun MenuItem(title: String, icon: ImageVector, destructive: Boolean = false, tag: String? = null, onClick: () -> Unit) {
    val color = if (destructive) AppColors.error else AppColors.textPrimary
    DropdownMenuItem(
        text = { Text(title, color = color) },
        leadingIcon = { Icon(icon, null, tint = color) },
        onClick = onClick,
        modifier = if (tag != null) Modifier.testTag(tag) else Modifier,
    )
}

@Composable
fun CompactArticleCard(article: Article, modifier: Modifier = Modifier) {
    LaunchedEffect(article.pubkey) { ProfileCache.load(listOf(article.pubkey)) }
    val shape = RoundedCornerShape(18.dp)
    Row(
        modifier.fillMaxWidth().clip(shape).background(AppColors.inputFill).padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val image = article.image?.ifEmpty { null }
        if (image != null) {
            RemoteImage(image, Modifier.size(72.dp).clip(RoundedCornerShape(12.dp)))
        } else {
            IconTile(Icons.Outlined.Article, size = 72.dp, tint = AppColors.textSecondary)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(L("article"), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = AppColors.textSecondary)
            Text(article.displayTitle, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(
                ProfileCache.profiles[article.pubkey]?.bestName ?: article.authorName?.ifEmpty { null } ?: Profile.shortNpub(article.pubkey),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

internal object ArticleActions {
    fun copy(text: String, toast: Boolean = true) {
        val clipboard = App.context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
        clipboard.setPrimaryClip(ClipData.newPlainText("qiqstr", text))
        if (toast) ToastCenter.show(L("copiedToClipboard"), ToastStyle.SUCCESS)
    }

    fun share(text: String) {
        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
        runCatching { App.context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }

    fun mute(pubkey: String, toast: Boolean = true, then: () -> Unit = {}) {
        App.scope.launch {
            Moderation.mute(pubkey)
            if (toast) ToastCenter.show(L("feedUserMuted"), ToastStyle.SUCCESS)
            then()
        }
    }
}
