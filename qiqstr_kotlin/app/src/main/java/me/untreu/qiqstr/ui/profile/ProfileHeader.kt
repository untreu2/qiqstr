package me.untreu.qiqstr.ui.profile

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.outlined.AlternateEmail
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.app.AppSheet
import me.untreu.qiqstr.app.FollowListMode
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.components.AvatarView
import me.untreu.qiqstr.core.components.RemoteImage
import me.untreu.qiqstr.data.services.MuteService
import me.untreu.qiqstr.domain.Profile

private val AVATAR_SIZE = 80.dp

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ProfileHeader(model: ProfileViewModel, onViewImage: (String) -> Unit, onIdentityBottom: (Float) -> Unit) {
    val profile = model.profile
    Column(Modifier.fillMaxWidth()) {
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
            val height = (maxWidth * 0.3f).coerceIn(110.dp, 160.dp) + top
            ProfileBanner(profile.banner.ifEmpty { null }, Modifier.fillMaxWidth().height(height)) {
                profile.banner.ifEmpty { null }?.let(onViewImage)
            }
        }
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            FlowRow(
                Modifier.fillMaxWidth().padding(top = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                ProfileAvatarButton(profile.picture.ifEmpty { null }, onViewImage)
                ProfileActionButtons(model, Modifier.align(Alignment.Bottom))
            }
            Identity(model, Modifier.onGloballyPositioned { onIdentityBottom(it.boundsInWindow().bottom) })
            if (profile.about.isNotEmpty()) {
                ProfileBioText(profile.about, Modifier.fillMaxWidth().testTag("profile-about"))
            }
            if (model.badges.isNotEmpty()) ProfileBadgesRow(model.badges, Modifier.padding(top = 2.dp))
            Details(model)
            Counts(model)
            val score = model.followScore
            if (score != null && !model.isMe) FollowedByRow(score, model.mutualFollowers)
        }
    }
}

@Composable
private fun ProfileBanner(url: String?, modifier: Modifier, onTap: () -> Unit) {
    Box(modifier.clickable(onClick = onTap).testTag("profile-banner")) {
        Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(AppColors.tile, AppColors.overlayLight))).background(AppColors.tile))
        if (url != null) RemoteImage(url, Modifier.fillMaxSize())
        Box(Modifier.fillMaxWidth().height(110.dp).background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.35f), Color.Transparent))))
    }
}

@Composable
private fun ProfileAvatarButton(picture: String?, onViewImage: (String) -> Unit) {
    val description = L("profileImage")
    Box(
        Modifier
            .layout { measurable, constraints ->
                val placeable = measurable.measure(constraints)
                val lift = (AVATAR_SIZE / 2).roundToPx()
                layout(placeable.width, (placeable.height - lift).coerceAtLeast(0)) { placeable.place(0, -lift) }
            }
            .clip(CircleShape)
            .background(AppColors.background, CircleShape)
            .clickable { picture?.let(onViewImage) }
            .padding(4.dp)
            .semantics { contentDescription = description }
            .testTag("profile-avatar"),
    ) {
        AvatarView(picture, AVATAR_SIZE)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Identity(model: ProfileViewModel, modifier: Modifier) {
    val showsFollowsYou = model.followsMe && !model.isMe
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                model.displayName,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.testTag("profile-name").align(Alignment.CenterVertically),
            )
            if (MuteService.isMuted(model.pubkey)) {
                Surface(shape = CircleShape, color = AppColors.tile, contentColor = AppColors.textSecondary, modifier = Modifier.align(Alignment.CenterVertically)) {
                    Text(
                        L("mutedButton"),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    )
                }
            }
        }
        val handle = model.handle
        if (handle != null || showsFollowsYou) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                val style = MaterialTheme.typography.bodyMedium
                if (handle != null) Text(handle, style = style, color = AppColors.textSecondary)
                if (handle != null && showsFollowsYou) Text("·", style = style, color = AppColors.textSecondary)
                if (showsFollowsYou) {
                    Text(L("profileFollowsYou"), style = style, color = AppColors.textSecondary, maxLines = 1, modifier = Modifier.testTag("profile-follows-you"))
                }
            }
        }
        val haptics = LocalHapticFeedback.current
        val copyLabel = L("profileCopyNpub")
        Row(
            Modifier.clip(RoundedCornerShape(6.dp))
                .clickable {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    ProfileSharing.copy(model.npub, L("copiedNpub"))
                }
                .semantics { contentDescription = copyLabel }
                .testTag("profile-copy-npub"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(Profile.shortNpub(model.pubkey), style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace), color = AppColors.textSecondary)
            Icon(Icons.Outlined.ContentCopy, null, Modifier.size(14.dp), tint = AppColors.textSecondary)
        }
    }
}

@Composable
private fun Details(model: ProfileViewModel) {
    val profile = model.profile
    val website = model.websiteURL
    if (profile.nip05.isEmpty() && profile.lud16.isEmpty() && website == null && profile.location.isEmpty()) return
    val context = LocalContext.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (profile.nip05.isNotEmpty()) {
            DetailRow(Icons.Outlined.AlternateEmail, Nip05Verifier.display(profile.nip05), Modifier.testTag("profile-nip05"))
        }
        if (website != null) {
            DetailRow(
                Icons.Outlined.Link,
                BioParser.prettyLink(profile.website),
                Modifier.testTag("profile-website"),
                emphasized = true,
                onClick = { Router.openUrl(website) },
                menu = listOf(
                    MenuAction(L("copy"), Icons.Outlined.ContentCopy) { ProfileSharing.copy(website) },
                    MenuAction(L("share"), Icons.Outlined.Share) { ProfileSharing.share(context, website) },
                ),
            )
        }
        if (profile.lud16.isNotEmpty()) {
            DetailRow(
                Icons.Filled.Bolt,
                profile.lud16,
                Modifier.testTag("profile-lud16"),
                tint = AppColors.zap,
                onClick = { if (!model.isMe) Router.present(AppSheet.ZapProfile(model.pubkey)) else ProfileSharing.copy(profile.lud16) },
                menu = listOf(MenuAction(L("copy"), Icons.Outlined.ContentCopy) { ProfileSharing.copy(profile.lud16) }),
            )
        }
        if (profile.location.isNotEmpty()) {
            DetailRow(Icons.Outlined.LocationOn, profile.location, Modifier.testTag("profile-location"))
        }
    }
}

private class MenuAction(val title: String, val icon: ImageVector, val action: () -> Unit)

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DetailRow(
    icon: ImageVector,
    text: String,
    modifier: Modifier = Modifier,
    emphasized: Boolean = false,
    tint: Color = AppColors.textSecondary,
    onClick: (() -> Unit)? = null,
    menu: List<MenuAction> = emptyList(),
) {
    var expanded by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    Box(modifier) {
        Row(
            Modifier.clip(RoundedCornerShape(6.dp)).then(
                if (onClick != null || menu.isNotEmpty()) {
                    Modifier.combinedClickable(
                        onClick = { onClick?.invoke() },
                        onLongClick = if (menu.isEmpty()) null else ({ haptics.performHapticFeedback(HapticFeedbackType.LongPress); expanded = true }),
                    )
                } else Modifier,
            ),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(icon, null, Modifier.width(18.dp).size(16.dp), tint = tint)
            Text(
                text,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = if (emphasized) FontWeight.Medium else FontWeight.Normal,
                color = if (emphasized) AppColors.textPrimary else AppColors.textSecondary,
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            menu.forEach { item ->
                DropdownMenuItem(
                    text = { Text(item.title) },
                    leadingIcon = { Icon(item.icon, null) },
                    onClick = { expanded = false; item.action() },
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Counts(model: ProfileViewModel) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        CountButton(model.followingCount, L("followingCount"), Modifier.testTag("profile-following-count")) {
            Router.push(Route.FollowList(model.pubkey, FollowListMode.FOLLOWING))
        }
        CountButton(model.followerCount, L(if (model.followerCount == 1) "followerSingular" else "followers"), Modifier.testTag("profile-followers-count")) {
            Router.push(Route.FollowList(model.pubkey, FollowListMode.FOLLOWERS))
        }
    }
}

@Composable
private fun CountButton(value: Int?, label: String, modifier: Modifier, onClick: () -> Unit) {
    Row(
        modifier.clip(RoundedCornerShape(6.dp)).clickable(onClick = onClick).padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        AnimatedContent(value, label = "count") { shown ->
            if (shown != null) {
                Text(Sats.compact(shown.toLong()), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary)
            } else {
                Spacer(Modifier.size(width = 28.dp, height = 14.dp).background(AppColors.tile, RoundedCornerShape(4.dp)))
            }
        }
        Text(label, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
    }
}
