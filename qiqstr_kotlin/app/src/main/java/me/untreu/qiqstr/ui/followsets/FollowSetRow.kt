package me.untreu.qiqstr.ui.followsets

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.IconTile
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.data.services.FollowSet
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Profile

@Composable
fun FollowSetRow(set: FollowSet, modifier: Modifier = Modifier, showsOwner: Boolean = false, isFavorite: Boolean = false) {
    LaunchedEffect(set.id) { ProfileCache.load(set.pubkeys.take(3) + if (showsOwner) listOf(set.pubkey) else emptyList()) }
    val count = FollowSet.memberCountText(set.pubkeys.size)
    val subtitle = if (!showsOwner) {
        if (set.description.isEmpty()) count else "$count · ${set.description}"
    } else {
        val owner = ProfileCache.profiles[set.pubkey]?.bestName ?: Profile.shortNpub(set.pubkey)
        "$count · ${L("exploreByAuthor", "name" to owner)}"
    }
    Row(
        modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        FollowSetAvatarStack(set.pubkeys.take(3))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(set.displayTitle, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                if (isFavorite) Icon(Icons.Filled.PushPin, L("exploreInFeed"), Modifier.size(14.dp), tint = AppColors.textSecondary)
            }
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
fun FollowSetAvatarStack(pubkeys: List<String>, size: Dp = 30.dp) {
    Box(Modifier.size(46.dp), contentAlignment = Alignment.Center) {
        if (pubkeys.isEmpty()) {
            IconTile(Icons.Outlined.Group, size = 46.dp, tint = AppColors.textSecondary)
        } else {
            pubkeys.forEachIndexed { index, pubkey ->
                ProfileAvatar(
                    pubkey,
                    size = size,
                    modifier = Modifier
                        .offset(x = (index * 8 - (pubkeys.size - 1) * 4).dp, y = if (index % 2 == 0) (-4).dp else 4.dp)
                        .zIndex(-index.toFloat())
                        .border(2.dp, AppColors.background, CircleShape),
                )
            }
        }
    }
}
