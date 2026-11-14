package me.untreu.qiqstr.ui.auth

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.IconTile
import me.untreu.qiqstr.core.components.PillButton
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.RemoteImage
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Profile

@Composable
fun FollowPackHeader(pack: FollowPack, isSelected: Boolean, isDisabled: Boolean, onToggle: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            FollowPackArtwork(pack.image.ifEmpty { null }, isBuiltIn = pack.kind == 0)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(pack.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (pack.summary.isNotEmpty()) {
                    Text(pack.summary, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 3, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            FollowPackAvatarStack(pack.members.take(5))
            Text(
                L("memberCount", "count" to pack.members.size),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textSecondary,
                maxLines = 1,
                modifier = Modifier.weight(1f),
            )
            PillButton(
                title = if (isSelected) L("authPackSelected") else L("authFollowAll"),
                onClick = onToggle,
                filled = !isSelected,
                enabled = !isDisabled,
                icon = if (isSelected) Icons.Filled.Check else null,
                modifier = Modifier.testTag("pack-follow-all"),
            )
        }
    }
}

@Composable
fun FollowPackArtwork(url: String?, isBuiltIn: Boolean = false, size: Dp = 56.dp) {
    val shape = RoundedCornerShape(14.dp)
    if (url != null) {
        RemoteImage(url, Modifier.size(size).clip(shape))
    } else {
        IconTile(if (isBuiltIn) Icons.Outlined.AutoAwesome else Icons.Outlined.Groups, size = size)
    }
}

@Composable
fun FollowPackAvatarStack(pubkeys: List<String>, size: Dp = 28.dp) {
    Row(horizontalArrangement = Arrangement.spacedBy(-size * 0.3f)) {
        pubkeys.forEach { pubkey ->
            ProfileAvatar(pubkey, size = size, modifier = Modifier.border(2.dp, AppColors.background, CircleShape))
        }
    }
}

@Composable
fun FollowPackSkeleton() {
    val transition = rememberInfiniteTransition(label = "skeleton")
    val alpha by transition.animateFloat(0.45f, 1f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "alpha")
    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp).alpha(alpha), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.size(56.dp).clip(RoundedCornerShape(14.dp)).background(AppColors.tile))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.fillMaxWidth(0.6f).height(16.dp).clip(RoundedCornerShape(4.dp)).background(AppColors.tile))
                Box(Modifier.fillMaxWidth(0.9f).height(12.dp).clip(RoundedCornerShape(4.dp)).background(AppColors.tile))
                Box(Modifier.fillMaxWidth(0.7f).height(12.dp).clip(RoundedCornerShape(4.dp)).background(AppColors.tile))
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy((-8).dp)) {
                repeat(5) { Box(Modifier.size(28.dp).clip(CircleShape).background(AppColors.tile)) }
            }
            Box(Modifier.width(70.dp).height(12.dp).clip(RoundedCornerShape(4.dp)).background(AppColors.tile))
            Spacer(Modifier.weight(1f))
            Box(Modifier.width(84.dp).height(30.dp).clip(CircleShape).background(AppColors.tile))
        }
    }
}

@Composable
fun FollowPackMemberRow(pubkey: String, isSelected: Boolean, alreadyFollowing: Boolean, enabled: Boolean = true, onClick: () -> Unit) {
    val profile = ProfileCache.profiles[pubkey]
    Row(
        Modifier.fillMaxWidth().clickableRow(enabled = enabled && !alreadyFollowing, onClick = onClick).padding(vertical = 8.dp)
            .testTag("suggested-user-${pubkey.take(8)}"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        ProfileAvatar(pubkey, size = 40.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(profile?.bestName ?: Profile.shortNpub(pubkey), fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val detail = profile?.about?.ifEmpty { null } ?: profile?.nip05?.ifEmpty { null }
            if (detail != null) Text(detail, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (alreadyFollowing) {
            Text(L("following"), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = AppColors.textSecondary)
        } else {
            Icon(
                if (isSelected) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                null,
                Modifier.size(26.dp),
                tint = if (isSelected) AppColors.textPrimary else AppColors.textTertiary,
            )
        }
    }
}
