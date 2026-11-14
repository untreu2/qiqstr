package me.untreu.qiqstr.ui.profile

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.DockedSearchBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ProfileSearchField(
    query: String,
    onQueryChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    tag: String = "search-field",
    trailing: (@Composable () -> Unit)? = null,
) {
    val focus = LocalFocusManager.current
    DockedSearchBar(
        inputField = {
            SearchBarDefaults.InputField(
                query = query,
                onQueryChange = onQueryChange,
                onSearch = { focus.clearFocus() },
                expanded = false,
                onExpandedChange = {},
                placeholder = { Text(placeholder) },
                leadingIcon = { Icon(Icons.Outlined.Search, null) },
                trailingIcon = {
                    when {
                        trailing != null -> trailing()
                        query.isNotEmpty() -> IconButton(onClick = { onQueryChange("") }) { Icon(Icons.Outlined.Close, L("profileClearSearch")) }
                    }
                },
                modifier = Modifier.testTag(tag),
            )
        },
        expanded = false,
        onExpandedChange = {},
        colors = SearchBarDefaults.colors(containerColor = AppColors.inputFill),
        modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
    ) {}
}
