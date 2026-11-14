package me.untreu.qiqstr.ui.auth

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.AppLanguage
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Localizer
import me.untreu.qiqstr.core.ThemeState
import me.untreu.qiqstr.core.components.TextAction

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AuthLanguageSheet(onDismiss: () -> Unit) {
    val selected = AppLanguage.current
    val haptics = rememberHaptics()
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = AppColors.background) {
        Column(Modifier.padding(bottom = 16.dp)) {
            TopAppBar(
                title = { Text(L("language")) },
                navigationIcon = {
                    IconButton(onClick = onDismiss, modifier = Modifier.testTag("language-close")) { Icon(Icons.Filled.Close, L("close")) }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background),
            )
            AppLanguage.entries.forEach { option ->
                val isSelected = option == selected
                ListItem(
                    headlineContent = { Text(option.displayName, fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal) },
                    supportingContent = if (option.localizedName != option.displayName) ({ Text(option.localizedName) }) else null,
                    trailingContent = if (isSelected) ({ Icon(Icons.Filled.Check, null) }) else null,
                    colors = ListItemDefaults.colors(containerColor = AppColors.background),
                    modifier = Modifier.testTag("language-${option.code}").clickable {
                        haptics.selection()
                        Localizer.apply(option.code)
                        onDismiss()
                        App.scope.launch {
                            delay(250)
                            ThemeState.applyLanguage(option.code)
                        }
                    },
                )
            }
            Text(
                L("languageSubtitle"),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textSecondary,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }
    }
}

private sealed interface TermsBlock {
    data class Heading(val level: Int, val text: String) : TermsBlock
    data class Bullet(val text: String) : TermsBlock
    data class Paragraph(val text: String) : TermsBlock
    object Divider : TermsBlock
}

private fun parseTerms(markdown: String): List<TermsBlock> = markdown.split("\n").map { it.trim() }.filter { it.isNotEmpty() }.map { line ->
    when {
        line == "---" -> TermsBlock.Divider
        line.startsWith("#") -> {
            val level = line.takeWhile { it == '#' }.length
            TermsBlock.Heading(level, line.drop(level).trim())
        }
        line.startsWith("- ") -> TermsBlock.Bullet(line.drop(2))
        else -> TermsBlock.Paragraph(line)
    }
}

private val inlinePattern = Regex("""\*\*(.+?)\*\*|\[(.+?)]\((.+?)\)""")

@Composable
fun inlineMarkdown(text: String): AnnotatedString {
    val linkColor = AppColors.link
    return remember(text, linkColor) {
        buildAnnotatedString {
            var cursor = 0
            for (match in inlinePattern.findAll(text)) {
                append(text.substring(cursor, match.range.first))
                val bold = match.groups[1]?.value
                if (bold != null) {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(bold) }
                } else {
                    val label = match.groups[2]?.value ?: ""
                    val url = match.groups[3]?.value ?: ""
                    withLink(LinkAnnotation.Url(url, TextLinkStyles(SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline)))) { append(label) }
                }
                cursor = match.range.last + 1
            }
            append(text.substring(cursor))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AuthTermsSheet(onAccept: (() -> Unit)? = null, onDismiss: () -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val blocks = remember(AppLanguage.current) { parseTerms(AuthTermsText.localized) }
    val dismiss: () -> Unit = { scope.launch { state.hide() }.invokeOnCompletion { onDismiss() } }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, containerColor = AppColors.background, modifier = Modifier.testTag("terms-sheet")) {
        Column(Modifier.fillMaxSize()) {
            TopAppBar(
                title = { Text(L("authTermsTitle")) },
                navigationIcon = {
                    if (onAccept != null) TextAction(L("cancel"), dismiss)
                },
                actions = {
                    if (onAccept != null) {
                        Button(
                            onClick = onAccept,
                            colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
                            modifier = Modifier.padding(end = 8.dp).testTag("terms-agree"),
                        ) { Text(L("authTermsAgreeShort"), fontWeight = FontWeight.SemiBold) }
                    } else {
                        Row { TextAction(L("done"), dismiss) }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background),
            )
            SelectionContainer {
                LazyColumn(
                    contentPadding = PaddingValues(horizontal = 20.dp, vertical = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    itemsIndexed(blocks) { _, block -> TermsBlockView(block) }
                }
            }
        }
    }
}

@Composable
private fun TermsBlockView(block: TermsBlock) {
    val typography = MaterialTheme.typography
    when (block) {
        is TermsBlock.Heading -> Text(
            inlineMarkdown(block.text),
            style = when (block.level) {
                1 -> typography.headlineSmall
                2 -> typography.titleLarge
                3 -> typography.titleMedium
                else -> typography.titleSmall
            },
            fontWeight = FontWeight.SemiBold,
            color = AppColors.textPrimary,
            modifier = Modifier.padding(top = if (block.level <= 2) 10.dp else 6.dp),
        )
        is TermsBlock.Bullet -> Row(Modifier.padding(start = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("•", style = typography.bodyMedium, color = AppColors.textPrimary)
            Text(inlineMarkdown(block.text), style = typography.bodyMedium, color = AppColors.textPrimary)
        }
        is TermsBlock.Paragraph -> Text(inlineMarkdown(block.text), style = typography.bodyMedium, color = AppColors.textPrimary)
        TermsBlock.Divider -> HorizontalDivider(Modifier.padding(vertical = 8.dp), color = AppColors.divider)
    }
}
