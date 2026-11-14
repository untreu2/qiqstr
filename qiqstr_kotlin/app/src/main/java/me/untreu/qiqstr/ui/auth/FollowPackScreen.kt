package me.untreu.qiqstr.ui.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.BackTopBar
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.LoadingView
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.SectionHeader
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.services.FollowService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.profile.UserRow

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FollowPackScreen(packId: String) {
    val pack = FollowPackService.packs.firstOrNull { it.id == packId }
    val me = Session.pubkey
    val scope = rememberCoroutineScope()
    var confirmFollowAll by remember { mutableStateOf(false) }
    var isFollowing by remember { mutableStateOf(false) }
    val remaining = pack?.members?.filter { it != me && !FollowService.isFollowing(it) }.orEmpty()
    val scrollBehavior = TopAppBarDefaults.pinnedScrollBehavior()
    LaunchedEffect(Unit) { FollowPackService.prefetch() }
    LaunchedEffect(pack?.id) { pack?.let { ProfileCache.load(it.members.take(60)) } }

    fun followAll() {
        isFollowing = true
        scope.launch {
            try {
                FollowService.followMany(remaining)
                ToastCenter.show(L("explorePackFollowed"), ToastStyle.SUCCESS)
            } catch (error: Throwable) {
                ToastCenter.error(error)
            } finally {
                isFollowing = false
            }
        }
    }

    Scaffold(
        containerColor = AppColors.background,
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection).testTag("follow-pack-view"),
        topBar = { BackTopBar(pack?.title ?: L("exploreFollowPacks"), scrollBehavior = scrollBehavior) },
    ) { padding ->
        when {
            pack != null -> LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                item("header") {
                    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            FollowPackArtwork(pack.image.ifEmpty { null }, isBuiltIn = pack.kind == 0)
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(pack.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                                if (pack.author.isNotEmpty()) PackAuthor(pack.author)
                            }
                        }
                        if (pack.summary.isNotEmpty()) {
                            Text(pack.summary, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
                        }
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            FollowPackAvatarStack(pack.members.take(5))
                            Text(
                                L("memberCount", "count" to pack.members.size),
                                style = MaterialTheme.typography.bodySmall,
                                color = AppColors.textSecondary,
                                modifier = Modifier.weight(1f),
                            )
                            Button(
                                onClick = { confirmFollowAll = true },
                                enabled = remaining.isNotEmpty() && !isFollowing,
                                colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
                                modifier = Modifier.testTag("pack-follow-all"),
                            ) {
                                if (isFollowing) {
                                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = AppColors.background)
                                } else {
                                    Text(if (remaining.isEmpty()) L("following") else L("authFollowAll"), fontWeight = FontWeight.SemiBold)
                                }
                            }
                        }
                    }
                }
                item("members-header") { SectionHeader(L("exploreMembersOther", "count" to pack.members.size)) }
                items(pack.members.filter { it != me }, key = { it }) { pubkey -> UserRow(pubkey) }
            }
            FollowPackService.isLoading -> LoadingView(Modifier.padding(padding))
            else -> Column(Modifier.fillMaxSize().padding(padding), verticalArrangement = Arrangement.Center) {
                EmptyStateView(icon = Icons.Outlined.Groups, title = L("exploreListNotFound"))
            }
        }
    }

    if (confirmFollowAll) {
        AlertDialog(
            onDismissRequest = { confirmFollowAll = false },
            title = { Text(L("explorePackFollowAllConfirm", "count" to remaining.size)) },
            confirmButton = { TextAction(L("authFollowAll"), { confirmFollowAll = false; followAll() }) },
            dismissButton = { TextAction(L("cancel"), { confirmFollowAll = false }) },
        )
    }
}

@Composable
private fun PackAuthor(pubkey: String) {
    LaunchedEffect(pubkey) { ProfileCache.load(listOf(pubkey)) }
    Row(
        Modifier.clickableRow { Router.push(Route.Profile(pubkey)) },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        ProfileAvatar(pubkey, size = 18.dp)
        Text(
            L("exploreByAuthor", "name" to (ProfileCache.profiles[pubkey]?.bestName ?: Profile.shortNpub(pubkey))),
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
