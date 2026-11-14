package me.untreu.qiqstr.ui.profile

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.HowToReg
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.outlined.HowToReg
import androidx.compose.material.icons.outlined.PersonAddAlt
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.services.FollowError
import me.untreu.qiqstr.data.services.FollowService
import me.untreu.qiqstr.data.services.ReadOnlyGate
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session

@Composable
fun FollowButton(
    pubkey: String,
    modifier: Modifier = Modifier,
    displayName: String? = null,
    compact: Boolean = false,
    circular: Boolean = false,
) {
    if (pubkey == Session.pubkey) return
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var isWorking by remember { mutableStateOf(false) }
    var optimistic by remember { mutableStateOf<Boolean?>(null) }
    var confirmUnfollow by remember { mutableStateOf(false) }
    var confirmNewList by remember { mutableStateOf(false) }
    val isFollowing = optimistic ?: FollowService.isFollowing(pubkey)
    val name = displayName?.ifEmpty { null } ?: ProfileCache.profiles[pubkey]?.bestName ?: L("anonymous")

    fun toggle(follow: Boolean, creatingList: Boolean = false) {
        if (isWorking) return
        if (!ReadOnlyGate.check()) return
        isWorking = true
        optimistic = follow
        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        scope.launch {
            try {
                if (follow) FollowService.follow(pubkey, creatingList) else FollowService.unfollow(pubkey)
            } catch (error: FollowError) {
                confirmNewList = follow
            } catch (error: Throwable) {
                ToastCenter.error(error)
            } finally {
                isWorking = false
                optimistic = null
            }
        }
    }

    val onClick = { if (isFollowing) confirmUnfollow = true else toggle(true) }
    val tag = Modifier.testTag(if (isFollowing) "unfollow-button" else "follow-button")
    if (circular) {
        val content: @Composable () -> Unit = {
            if (isWorking) {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = if (isFollowing) AppColors.textPrimary else AppColors.background)
            } else {
                AnimatedContent(isFollowing, label = "follow-icon") { following ->
                    Icon(if (following) Icons.Filled.HowToReg else Icons.Filled.PersonAdd, if (following) L("unfollow") else L("follow"))
                }
            }
        }
        if (isFollowing) {
            FilledTonalIconButton(onClick = onClick, enabled = !isWorking, modifier = modifier.size(40.dp).then(tag)) { content() }
        } else {
            FilledIconButton(
                onClick = onClick,
                enabled = !isWorking,
                modifier = modifier.size(40.dp).then(tag),
                colors = IconButtonDefaults.filledIconButtonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
            ) { content() }
        }
    } else {
        val padding = if (compact) PaddingValues(horizontal = 12.dp, vertical = 4.dp) else ButtonDefaults.ContentPadding
        val style = if (compact) MaterialTheme.typography.labelMedium else MaterialTheme.typography.labelLarge
        val label: @Composable () -> Unit = {
            if (isWorking) {
                CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp, color = if (isFollowing) AppColors.textPrimary else AppColors.background)
            } else {
                Icon(if (isFollowing) Icons.Outlined.HowToReg else Icons.Outlined.PersonAddAlt, null, Modifier.size(if (compact) 16.dp else 18.dp))
            }
            Spacer(Modifier.width(6.dp))
            Text(if (isFollowing) L("following") else L("follow"), style = style, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
        if (isFollowing) {
            FilledTonalButton(onClick = onClick, enabled = !isWorking, contentPadding = padding, modifier = modifier.then(tag)) { label() }
        } else {
            Button(
                onClick = onClick,
                enabled = !isWorking,
                contentPadding = padding,
                colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
                modifier = modifier.then(tag),
            ) { label() }
        }
    }

    if (confirmUnfollow) {
        AlertDialog(
            onDismissRequest = { confirmUnfollow = false },
            title = { Text(L("unfollowUser", "user" to name)) },
            confirmButton = {
                Box(Modifier.testTag("confirm-unfollow")) {
                    TextAction(L("unfollow"), { confirmUnfollow = false; toggle(false) }, color = AppColors.error)
                }
            },
            dismissButton = { TextAction(L("cancel"), { confirmUnfollow = false }) },
        )
    }
    NewFollowListConfirmation(confirmNewList, onDismiss = { confirmNewList = false }) {
        confirmNewList = false
        toggle(follow = true, creatingList = true)
    }
}

@Composable
fun NewFollowListConfirmation(visible: Boolean, onDismiss: () -> Unit, create: () -> Unit) {
    if (!visible) return
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(L("followListMissingTitle")) },
        text = { Text(L("followListMissingMessage")) },
        confirmButton = { Box(Modifier.testTag("follow-list-create-new")) { TextAction(L("followListCreateNew"), create) } },
        dismissButton = { TextAction(L("cancel"), onDismiss) },
    )
}
