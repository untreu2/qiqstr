package me.untreu.qiqstr.ui.thread

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FormatQuote
import androidx.compose.material3.Scaffold
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.testTag
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.BackTopBar
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.LoadingView
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.ui.note.NoteContentCache
import me.untreu.qiqstr.ui.note.NoteInteractionStore
import me.untreu.qiqstr.ui.note.NoteList
import me.untreu.qiqstr.ui.note.NoteRepository

class QuotesViewModel(val noteId: String) : ViewModel() {
    var quotes by mutableStateOf<List<Note>>(emptyList())
        private set
    var isLoading by mutableStateOf(true)
        private set

    suspend fun load() {
        reloadLocal()
        NoteRepository.fetchQuotesFromRelays(noteId)
        reloadLocal()
        isLoading = false
    }

    suspend fun reloadLocal() {
        val muted = Session.mutedPubkeys.toSet()
        val deleted = NoteInteractionStore.deletedIds
        val result = NoteRepository.quotes(noteId).filter { it.pubkey !in muted && it.id !in deleted }
        quotes = result
        if (result.isNotEmpty()) isLoading = false
        NoteInteractionStore.seed(result)
        NoteInteractionStore.requestCounts(result.map { it.id })
        NoteContentCache.warm(result)
        ProfileCache.load(result.map { it.pubkey }.distinct().filter { ProfileCache.profile(it) == null })
    }
}

@Composable
fun QuotesScreen(noteId: String) {
    val model: QuotesViewModel = viewModel(key = "quotes-$noteId") { QuotesViewModel(noteId) }
    val scope = rememberCoroutineScope()
    var isRefreshing by remember { mutableStateOf(false) }
    val scrollBehavior = TopAppBarDefaults.pinnedScrollBehavior()
    LaunchedEffect(Unit) { model.load() }
    LaunchedEffect(DataBus.feedVersion) { if (DataBus.feedVersion > 0) model.reloadLocal() }
    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = AppColors.background,
        topBar = { BackTopBar(L("quotes"), scrollBehavior = scrollBehavior) },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                scope.launch {
                    isRefreshing = true
                    try { model.load() } finally { isRefreshing = false }
                }
            },
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            NoteList(model.quotes, modifier = Modifier.testTag("quotes-list"))
            if (model.quotes.isEmpty()) {
                if (model.isLoading) {
                    LoadingView()
                } else {
                    EmptyStateView(Icons.Outlined.FormatQuote, L("noQuotesFound"), modifier = Modifier.align(Alignment.Center).testTag("quotes-empty"))
                }
            }
        }
    }
}
