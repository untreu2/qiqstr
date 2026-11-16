package me.untreu.qiqstr.core.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.data.services.*

@Composable
fun CustomEmojiImage(url: String, size: Dp = 28.dp) {
    RemoteImage(url, Modifier.size(size), contentScale = ContentScale.Fit)
}

@Composable
fun EmojiChoiceView(choice: EmojiChoice, size: Dp = 28.dp) {
    when (choice) {
        is EmojiChoice.Unicode -> Text(choice.emoji, style = MaterialTheme.typography.headlineSmall)
        is EmojiChoice.Custom -> CustomEmojiImage(choice.emoji.url, size)
    }
}

@Composable
fun EmojiPickerSheet(customOnly: Boolean = false, onDismiss: () -> Unit, onPick: (EmojiChoice) -> Unit) {
    var query by remember { mutableStateOf("") }
    val gridState = rememberLazyGridState()
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { if (!EmojiPackService.isLoaded) EmojiPackService.load() }
    val searching = query.isNotBlank()
    val sections = if (searching) {
        val custom = EmojiPackService.allEmojis.filter { it.shortcode.contains(query.trim(), ignoreCase = true) }.map { EmojiChoice.Custom(it) }
        val standard = if (customOnly) emptyList() else EmojiCatalog.search(query).map { EmojiChoice.Unicode(it.emoji) }
        listOf(Triple("search", L("emojiTitle"), custom + standard))
    } else buildList {
        val recent = RecentEmojiStore.items.filter { !customOnly || it is EmojiChoice.Custom }
        if (recent.isNotEmpty()) add(Triple("recent", L("emojiRecent"), recent))
        EmojiPackService.packs.forEach { add(Triple(it.coordinate, it.title, it.emojis.map(EmojiChoice::Custom))) }
        if (!customOnly) EmojiCatalog.groups.forEach { add(Triple(it.id, it.title, it.items.map { e -> EmojiChoice.Unicode(e.emoji) })) }
    }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = AppColors.background) {
        Column(Modifier.fillMaxWidth().heightIn(max = 650.dp).testTag("emoji-picker")) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(L("emojiTitle"), style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                TextButton(onClick = onDismiss, modifier = Modifier.testTag("emoji-cancel")) { Text(L("cancel")) }
            }
            OutlinedTextField(query, { query = it }, placeholder = { Text(L("emojiSearch")) }, singleLine = true, modifier = Modifier.fillMaxWidth().padding(12.dp).testTag("emoji-search"))
            LazyVerticalGrid(GridCells.Adaptive(42.dp), state = gridState, modifier = Modifier.weight(1f).padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (sections.all { it.third.isEmpty() }) item(span = { GridItemSpan(maxLineSpan) }) {
                    Column(Modifier.padding(24.dp)) {
                        Text(L(if (searching) "emojiNoResults" else "emojiNoPacks"))
                        if (!searching) Text(L("emojiNoPacksMessage"), color = AppColors.textSecondary)
                    }
                }
                sections.forEach { (id, title, choices) ->
                    if (choices.isNotEmpty()) {
                        item(key = "heading-$id", span = { GridItemSpan(maxLineSpan) }) { Text(title, style = MaterialTheme.typography.labelLarge, color = AppColors.textSecondary, modifier = Modifier.padding(top = 12.dp, bottom = 4.dp)) }
                        items(choices) { choice ->
                            Box(Modifier.size(42.dp).clickable { RecentEmojiStore.record(choice); onPick(choice); onDismiss() }.semantics { contentDescription = choice.content }.testTag("emoji-item"), contentAlignment = Alignment.Center) { EmojiChoiceView(choice) }
                        }
                    }
                }
            }
            if (!customOnly && !searching) Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).testTag("emoji-categories"), horizontalArrangement = Arrangement.SpaceEvenly) {
                val categories = listOf("recent" to "🕘") + (if (EmojiPackService.packs.isEmpty()) emptyList() else listOf(EmojiPackService.packs.first().coordinate to "⭐")) + EmojiCatalog.groups.map { it.id to it.symbol }
                categories.forEach { (id, symbol) ->
                    TextButton(onClick = {
                        var index = 0
                        for (section in sections) {
                            if (section.first == id) break
                            if (section.third.isNotEmpty()) index += 1 + section.third.size
                        }
                        if (sections.any { it.first == id }) scope.launch { gridState.animateScrollToItem(index) }
                    }, modifier = Modifier.semantics { contentDescription = when (id) { "recent" -> L("emojiRecent"); else -> EmojiCatalog.groups.firstOrNull { it.id == id }?.title ?: L("emojiCustom") } }) { Text(symbol) }
                }
            }
        }
    }
}
