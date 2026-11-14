package me.untreu.qiqstr.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.components.AvatarView
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.data.sync.ProfileCache

@Composable
fun FollowedByRow(score: FollowScore, mutuals: List<String>, modifier: Modifier = Modifier) {
    var showSheet by remember { mutableStateOf(false) }
    val total = maxOf(score.count, mutuals.size)
    Row(
        modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp))
            .clickable(enabled = mutuals.isNotEmpty()) { showSheet = true }
            .padding(vertical = 2.dp)
            .testTag("profile-followed-by"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row {
            if (mutuals.isNotEmpty()) {
                val shown = mutuals.take(3)
                shown.forEachIndexed { index, pubkey ->
                    Box(
                        Modifier.offset(x = (-7 * index).dp).zIndex((shown.size - index).toFloat())
                            .background(AppColors.background, CircleShape).padding(1.5.dp),
                    ) { ProfileAvatar(pubkey, size = 24.dp) }
                }
            } else {
                val urls = score.avatarUrls.take(3)
                urls.forEachIndexed { index, url ->
                    Box(
                        Modifier.offset(x = (-7 * index).dp).zIndex((urls.size - index).toFloat())
                            .background(AppColors.background, CircleShape).padding(1.5.dp),
                    ) { AvatarView(url, size = 24.dp) }
                }
            }
        }
        Text(
            summary(total, mutuals),
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textSecondary,
            maxLines = 2,
            modifier = Modifier.weight(1f),
        )
        if (mutuals.isNotEmpty()) {
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null, tint = AppColors.textTertiary)
        }
    }
    if (showSheet) MutualFollowsSheet(mutuals) { showSheet = false }
}

private fun summary(total: Int, mutuals: List<String>): String {
    val names = mutuals.take(2).mapNotNull { ProfileCache.profiles[it]?.bestName?.ifEmpty { null } }
    if (names.size != minOf(2, mutuals.size) || names.isEmpty()) {
        return if (total == 1) L("profileFollowedByOne") else L("profileFollowedByMany", "count" to Sats.compact(total.toLong()))
    }
    val others = total - names.size
    val lead = if (names.size == 1) L("profileFollowedByOneName", "first" to names[0])
    else L("profileFollowedByTwoNames", "first" to names[0], "second" to names[1])
    if (others <= 0) return lead
    val list = if (names.size == 1) names[0] else L("profileNameList", "first" to names[0], "second" to names[1])
    return if (others == 1) L("profileFollowedByNamesAndOne", "names" to list)
    else L("profileFollowedByNamesAndOthers", "names" to list, "count" to Sats.compact(others.toLong()))
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MutualFollowsSheet(pubkeys: List<String>, onDismiss: () -> Unit) {
    LaunchedEffect(pubkeys) {
        val missing = pubkeys.filter { ProfileCache.profile(it) == null }
        if (missing.isNotEmpty()) ProfileCache.load(missing)
    }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = AppColors.background, modifier = Modifier.testTag("mutual-follows-sheet")) {
        Text(
            L("profileMutualFollowsTitle"),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
        )
        LazyColumn(Modifier.fillMaxWidth()) {
            items(pubkeys, key = { it }) { pubkey ->
                UserRow(pubkey) {
                    onDismiss()
                    Router.push(Route.Profile(pubkey))
                }
            }
        }
    }
}
