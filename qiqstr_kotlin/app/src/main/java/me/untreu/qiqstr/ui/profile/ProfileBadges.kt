package me.untreu.qiqstr.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.MilitaryTech
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.SubcomposeAsyncImage
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.data.services.ProfileBadge
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Profile

private const val VISIBLE_LIMIT = 8

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ProfileBadgesRow(badges: List<ProfileBadge>, modifier: Modifier = Modifier) {
    var showSheet by remember { mutableStateOf(false) }
    val description = L("profileBadgesCount", "count" to badges.size)
    FlowRow(
        modifier.fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .clickable { showSheet = true }
            .semantics { contentDescription = description }
            .testTag("profile-badges"),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        badges.take(VISIBLE_LIMIT).forEach { BadgeImage(it.thumbURL, 28.dp) }
        if (badges.size > VISIBLE_LIMIT) {
            Text(
                "+${badges.size - VISIBLE_LIMIT}",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.textSecondary,
                modifier = Modifier.align(Alignment.CenterVertically),
            )
        }
    }
    if (showSheet) ProfileBadgesSheet(badges) { showSheet = false }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileBadgesSheet(badges: List<ProfileBadge>, onDismiss: () -> Unit) {
    LaunchedEffect(badges) {
        val missing = badges.map { it.issuer }.distinct().filter { ProfileCache.profile(it) == null }
        if (missing.isNotEmpty()) ProfileCache.load(missing)
    }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = AppColors.background, modifier = Modifier.testTag("profile-badges-sheet")) {
        Text(
            L("profileBadges"),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
        )
        LazyColumn(Modifier.fillMaxWidth()) {
            items(badges, key = { it.id }) { badge ->
                ProfileBadgeRow(badge, ProfileCache.profiles[badge.issuer]) {
                    onDismiss()
                    Router.push(Route.Profile(badge.issuer))
                }
            }
        }
    }
}

@Composable
private fun ProfileBadgeRow(badge: ProfileBadge, issuer: Profile?, onIssuerTap: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        BadgeImage(badge.imageURL, 56.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(badge.displayName, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            if (badge.description.isNotEmpty()) {
                Text(badge.description, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
            }
            Row(
                Modifier.clip(RoundedCornerShape(6.dp)).clickable(onClick = onIssuerTap).padding(vertical = 4.dp).testTag("profile-badge-issuer"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                ProfileAvatar(badge.issuer, size = 18.dp)
                Text(
                    L("profileBadgeIssuedBy", "name" to (issuer?.bestName ?: Profile.shortNpub(badge.issuer))),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun BadgeImage(url: String?, size: Dp) {
    val shape = RoundedCornerShape(size * 0.22f)
    val placeholder: @Composable () -> Unit = {
        Box(Modifier.size(size).background(AppColors.tile, shape), contentAlignment = Alignment.Center) {
            Icon(Icons.Outlined.MilitaryTech, null, Modifier.size(size * 0.45f), tint = AppColors.textSecondary)
        }
    }
    if (url.isNullOrBlank()) {
        placeholder()
        return
    }
    SubcomposeAsyncImage(
        model = url,
        contentDescription = null,
        contentScale = androidx.compose.ui.layout.ContentScale.Crop,
        modifier = Modifier.size(size).clip(shape),
        loading = { placeholder() },
        error = { placeholder() },
    )
}
