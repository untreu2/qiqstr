package me.untreu.qiqstr.ui.compose

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.ui.note.NoteMediaPlaceholder

class GifPickerModel(private val scope: CoroutineScope) {
    var query by mutableStateOf("")
        private set
    var items by mutableStateOf<List<GifItem>>(emptyList())
        private set
    var isLoading by mutableStateOf(true)
        private set
    private var job: Job? = null

    fun updateQuery(value: String) {
        if (value == query) return
        query = value
        load()
    }

    fun load() {
        job?.cancel()
        val term = query
        isLoading = true
        job = scope.launch {
            if (term.isNotEmpty()) delay(350)
            val result = GifService.search(term)
            if (query != term) return@launch
            items = result
            isLoading = false
        }
    }
}

@Composable
internal fun GifPickerSheet(onDismiss: () -> Unit, onPick: (GifItem) -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, containerColor = AppColors.background) {
        GifPickerContent(onDismiss, onPick)
    }
}

@Composable
private fun GifPickerContent(onDismiss: () -> Unit, onPick: (GifItem) -> Unit) {
    val scope = rememberCoroutineScope()
    val model = remember { GifPickerModel(scope) }
    val context = LocalContext.current
    LaunchedEffect(model) { model.load() }
    Column(Modifier.fillMaxWidth().fillMaxHeight().imePadding().testTag("gif-picker")) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onDismiss, modifier = Modifier.testTag("gif-cancel")) { Icon(Icons.Outlined.Close, L("cancel")) }
            Text(L("feedGifTitle"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 4.dp))
        }
        TextField(
            value = model.query,
            onValueChange = model::updateQuery,
            placeholder = { Text(L("feedGifSearch")) },
            leadingIcon = { Icon(Icons.Outlined.Search, null) },
            trailingIcon = {
                if (model.query.isNotEmpty()) IconButton(onClick = { model.updateQuery("") }) { Icon(Icons.Outlined.Close, L("profileClearSearch")) }
            },
            singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Search),
            shape = RoundedCornerShape(14.dp),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = AppColors.inputFill,
                unfocusedContainerColor = AppColors.inputFill,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
            ),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp).testTag("gif-search"),
        )
        Box(Modifier.fillMaxWidth().weight(1f)) {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(150.dp),
                contentPadding = PaddingValues(start = 12.dp, end = 12.dp, bottom = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                items(model.items, key = { it.id }) { gif ->
                    val label = gif.title.ifEmpty { L("feedGif") }
                    Box(
                        Modifier.aspectRatio(1.3f).clip(RoundedCornerShape(12.dp))
                            .clickable {
                                onPick(gif)
                                onDismiss()
                            }
                            .semantics { contentDescription = label }
                            .testTag("gif-item"),
                    ) {
                        NoteMediaPlaceholder(gif.blurhash, Modifier.fillMaxSize())
                        AsyncImage(
                            model = ImageRequest.Builder(context).data(gif.preview).crossfade(true).build(),
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize(),
                        )
                    }
                }
            }
            if (model.items.isEmpty()) {
                if (model.isLoading) {
                    CircularProgressIndicator(Modifier.align(Alignment.Center), color = AppColors.textPrimary)
                } else {
                    EmptyStateView(Icons.Outlined.PhotoLibrary, L("feedGifEmpty"), L("feedGifEmptyMessage"), modifier = Modifier.align(Alignment.Center))
                }
            }
        }
    }
}
