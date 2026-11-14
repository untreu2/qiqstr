package me.untreu.qiqstr.ui.articles

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.Highlight
import androidx.compose.material.icons.outlined.VolumeOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.QiqTextField
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.note.ReportSheet
import me.untreu.qiqstr.ui.note.ReportTarget

data class HighlightDraft(val passage: String, val id: Long = System.nanoTime())

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HighlightComposerSheet(draft: HighlightDraft, onDismiss: () -> Unit, onPublish: suspend (text: String, comment: String) -> Boolean) {
    var passage by remember(draft.id) { mutableStateOf(TextFieldValue(draft.passage)) }
    var comment by remember(draft.id) { mutableStateOf("") }
    var confirming by remember { mutableStateOf(false) }
    var publishing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val selection = passage.selection
    val picked = if (selection.collapsed) "" else passage.text.substring(selection.min, selection.max).trim()
    val quote = picked.ifEmpty { draft.passage.trim() }

    Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
        CenterAlignedTopAppBar(
            title = { Text(L("highlightNew")) },
            navigationIcon = { TextAction(L("cancel"), { if (!publishing) onDismiss() }) },
            actions = {
                if (publishing) {
                    CircularProgressIndicator(Modifier.padding(end = 16.dp).size(22.dp), strokeWidth = 2.dp, color = AppColors.textPrimary)
                } else {
                    Button(
                        onClick = { confirming = true },
                        enabled = quote.isNotEmpty(),
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
                        modifier = Modifier.padding(end = 8.dp).testTag("highlight-publish"),
                    ) {
                        Icon(Icons.Outlined.Highlight, null, Modifier.size(18.dp))
                        Text(L("highlightAction"), Modifier.padding(start = 6.dp), fontWeight = FontWeight.SemiBold)
                    }
                }
            },
            colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = AppColors.background),
        )
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SectionLabel(L("highlightPassage"))
            BasicTextField(
                value = passage,
                onValueChange = { passage = it.copy(text = draft.passage) },
                readOnly = true,
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = AppColors.textPrimary),
                cursorBrush = SolidColor(AppColors.textPrimary),
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 120.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(AppColors.inputFill)
                    .padding(12.dp)
                    .testTag("highlight-passage"),
            )
            Footnote(L("highlightSelectHint"))
            SectionLabel(L("highlightPreview"))
            Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.width(3.dp).fillMaxHeight().clip(RoundedCornerShape(2.dp)).background(AppColors.link.copy(alpha = 0.55f)))
                Text(quote, style = MaterialTheme.typography.bodyLarge, color = AppColors.textPrimary, modifier = Modifier.testTag("highlight-preview"))
            }
            SectionLabel(L("highlightComment"))
            QiqTextField(
                value = comment,
                onValueChange = { comment = it },
                placeholder = L("highlightCommentPlaceholder"),
                singleLine = false,
                modifier = Modifier.fillMaxWidth().testTag("highlight-comment"),
            )
            Footnote(L("highlightPublicNotice"))
        }
    }

    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text(L("highlightConfirmTitle")) },
            text = { Text(L("highlightConfirmMessage")) },
            confirmButton = {
                TextAction(L("highlightConfirmAction"), {
                    confirming = false
                    publishing = true
                    val text = quote
                    val note = comment
                    scope.launch {
                        val ok = onPublish(text, note)
                        publishing = false
                        if (ok) onDismiss()
                    }
                })
            },
            dismissButton = { TextAction(L("cancel"), { confirming = false }) },
        )
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(text, style = MaterialTheme.typography.labelLarge, color = AppColors.textSecondary, modifier = Modifier.padding(top = 12.dp))
}

@Composable
private fun Footnote(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HighlightsSheet(highlights: List<ArticleHighlight>, isLoading: Boolean, onDismiss: () -> Unit, onSelect: (ArticleHighlight) -> Unit) {
    LaunchedEffect(highlights) { ProfileCache.load(highlights.map { it.pubkey }.distinct()) }
    Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
        CenterAlignedTopAppBar(
            title = { Text(L("highlightsTitle")) },
            actions = { TextAction(L("done"), onDismiss) },
            colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = AppColors.background),
        )
        val visible = highlights.filter { it.pubkey !in Session.mutedPubkeys }
        when {
            visible.isEmpty() && isLoading -> Box(Modifier.fillMaxWidth().height(240.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = AppColors.textPrimary)
            }
            visible.isEmpty() -> EmptyStateView(icon = Icons.Outlined.Highlight, title = L("highlightsEmpty"), message = L("highlightsEmptyHint"))
            else -> LazyColumn(Modifier.fillMaxWidth()) {
                items(visible, key = { it.id }) { highlight ->
                    HighlightRow(highlight, onDismiss, onSelect)
                    HorizontalDivider(Modifier.padding(start = 16.dp), color = AppColors.divider)
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun HighlightRow(highlight: ArticleHighlight, onDismiss: () -> Unit, onSelect: (ArticleHighlight) -> Unit) {
    var menu by remember { mutableStateOf(false) }
    var reportTarget by remember { mutableStateOf<ReportTarget?>(null) }
    reportTarget?.let { target -> ReportSheet(target, onDismiss = { reportTarget = null }) }
    Box {
        Column(
            Modifier
                .fillMaxWidth()
                .combinedClickable(onClick = { onDismiss(); onSelect(highlight) }, onLongClick = { menu = true })
                .padding(horizontal = 16.dp, vertical = 12.dp)
                .testTag("highlight-row-${highlight.id}"),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ProfileAvatar(highlight.pubkey, size = 24.dp)
                Text(
                    ProfileCache.profiles[highlight.pubkey]?.bestName ?: Profile.shortNpub(highlight.pubkey),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Text(TimeFormat.relative(highlight.createdAt), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
            }
            Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.width(3.dp).fillMaxHeight().clip(RoundedCornerShape(2.dp)).background(AppColors.link.copy(alpha = 0.55f)))
                Text(highlight.content, style = MaterialTheme.typography.bodyLarge, maxLines = 8, overflow = TextOverflow.Ellipsis)
            }
            highlight.comment?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary) }
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            MenuItem(L("copy"), Icons.Outlined.ContentCopy) { menu = false; ArticleActions.copy(highlight.content, toast = false) }
            MenuItem(L("exploreViewAuthor"), Icons.Outlined.AccountCircle) {
                menu = false
                onDismiss()
                Router.push(Route.Profile(highlight.pubkey))
            }
            if (highlight.pubkey != Session.pubkey) {
                HorizontalDivider()
                MenuItem(L("feedMuteAuthor"), Icons.Outlined.VolumeOff, destructive = true) {
                    menu = false
                    ArticleActions.mute(highlight.pubkey, toast = false)
                }
                MenuItem(L("report"), Icons.Outlined.Flag, destructive = true) {
                    menu = false
                    reportTarget = ReportTarget(highlight.pubkey, highlight.id)
                }
            }
        }
    }
}
