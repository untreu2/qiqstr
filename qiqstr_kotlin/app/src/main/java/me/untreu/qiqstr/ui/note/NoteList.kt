package me.untreu.qiqstr.ui.note

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.domain.Note

@Composable
fun NoteList(
    notes: List<Note>,
    modifier: Modifier = Modifier,
    state: LazyListState = rememberLazyListState(),
    isLoadingMore: Boolean = false,
    showsThreadContext: Boolean = true,
    contentPadding: PaddingValues = PaddingValues(0.dp),
    onAppearNote: (Note) -> Unit = {},
    header: LazyListScope.() -> Unit = {},
) {
    LazyColumn(modifier.fillMaxSize(), state = state, contentPadding = contentPadding) {
        header()
        noteItems(notes, showsThreadContext, onAppearNote)
        if (isLoadingMore) {
            item(key = "loading-more") {
                Box(Modifier.fillMaxWidth().padding(vertical = 18.dp).testTag("feed-loading-more"), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = AppColors.textSecondary)
                }
            }
        }
    }
}

fun LazyListScope.noteItems(notes: List<Note>, showsThreadContext: Boolean = true, onAppearNote: (Note) -> Unit = {}) {
    itemsIndexed(notes, key = { _, note -> note.listId }, contentType = { _, _ -> "note" }) { index, note ->
        LaunchedEffect(note.listId) { onAppearNote(note) }
        if (index > 0) HorizontalDivider(color = AppColors.divider, thickness = 0.5.dp)
        NoteRow(note, showsThreadContext = showsThreadContext, swipeActions = true)
    }
}
