package me.untreu.qiqstr.ui.explore

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.DockedSearchBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExploreLargeScaffold(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    showBack: Boolean = true,
    actions: @Composable RowScope.() -> Unit = {},
    below: (@Composable () -> Unit)? = null,
    content: @Composable (PaddingValues) -> Unit,
) {
    val scroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    Scaffold(
        modifier = modifier.fillMaxSize().nestedScroll(scroll.nestedScrollConnection),
        containerColor = AppColors.background,
        contentWindowInsets = WindowInsets(0),
        topBar = {
            Column {
                LargeTopAppBar(
                    title = {
                        Column {
                            Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (!subtitle.isNullOrEmpty()) {
                                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    },
                    navigationIcon = {
                        if (showBack) IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) }
                    },
                    actions = actions,
                    scrollBehavior = scroll,
                    colors = TopAppBarDefaults.largeTopAppBarColors(containerColor = AppColors.background, scrolledContainerColor = AppColors.background),
                )
                below?.invoke()
            }
        },
        content = content,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RefreshBox(onRefresh: suspend () -> Unit, modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            refreshing = true
            scope.launch {
                try { onRefresh() } finally { refreshing = false }
            }
        },
        modifier = modifier.fillMaxSize(),
        content = content,
    )
}

@Composable
fun PaddedBox(padding: PaddingValues, content: @Composable BoxScope.() -> Unit) {
    Box(Modifier.fillMaxSize().padding(padding), content = content)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExploreSearchField(
    query: String,
    onQueryChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    onSearch: () -> Unit = {},
    onFocusChange: (Boolean) -> Unit = {},
) {
    var focused by remember { mutableStateOf(false) }
    val keyboard = LocalSoftwareKeyboardController.current
    DockedSearchBar(
        inputField = {
            SearchBarDefaults.InputField(
                query = query,
                onQueryChange = onQueryChange,
                onSearch = {
                    onSearch()
                    keyboard?.hide()
                },
                expanded = focused,
                onExpandedChange = {
                    focused = it
                    onFocusChange(it)
                },
                placeholder = { Text(placeholder, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                leadingIcon = { Icon(Icons.Outlined.Search, null) },
                trailingIcon = {
                    if (query.isNotEmpty()) IconButton(onClick = { onQueryChange("") }) { Icon(Icons.Outlined.Close, L("searchClearRecent")) }
                },
                modifier = Modifier.testTag("search-field"),
            )
        },
        expanded = false,
        onExpandedChange = {},
        colors = SearchBarDefaults.colors(containerColor = AppColors.inputFill),
        modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
    ) {}
}
