package me.untreu.qiqstr.ui.note

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FormatQuote
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.Bookmark
import androidx.compose.material.icons.outlined.BookmarkRemove
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.Tag
import androidx.compose.material.icons.outlined.Translate
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material.icons.automirrored.outlined.VolumeOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.services.BookmarkService
import me.untreu.qiqstr.data.services.InteractionService
import me.untreu.qiqstr.data.services.MuteService
import me.untreu.qiqstr.data.services.PinnedNotesService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile

@Stable
class NoteActionHandler {
    var pendingDelete by mutableStateOf<Note?>(null)
    var pendingMute by mutableStateOf<Note?>(null)
    var reportTarget by mutableStateOf<Note?>(null)

    companion object {
        fun shareUrl(note: Note): String {
            val bech = Nip19.nevent(note.id, note.pubkey) ?: Nip19.note(note.id) ?: note.id
            return "https://njump.me/$bech"
        }

        fun share(context: Context, note: Note) {
            val intent = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, shareUrl(note))
            runCatching { context.startActivity(Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }

        fun copy(context: Context, text: String) {
            val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return
            clipboard.setPrimaryClip(ClipData.newPlainText("qiqstr", text))
            ToastCenter.show(L("copiedToClipboard"), ToastStyle.SUCCESS)
        }
    }

    fun copyText(context: Context, note: Note) = copy(context, note.content)

    fun copyId(context: Context, note: Note) = copy(context, Nip19.note(note.id) ?: note.id)

    fun verify(note: Note) {
        App.scope.launch {
            val (event, profile) = InteractionService.verify(note)
            when {
                !event -> ToastCenter.show(L("eventSignatureVerificationFailed"), ToastStyle.ERROR)
                profile -> ToastCenter.show(L("eventAndAuthorProfileSignaturesVerified"), ToastStyle.SUCCESS)
                else -> ToastCenter.show(L("eventSignatureVerified"), ToastStyle.SUCCESS)
            }
        }
    }

    fun toggleBookmark(note: Note) {
        val wasBookmarked = BookmarkService.isBookmarked(note.id)
        App.scope.launch {
            try {
                BookmarkService.toggle(note.id)
                ToastCenter.show(if (wasBookmarked) L("bookmarkRemoved") else L("bookmarkAdded"), ToastStyle.SUCCESS)
            } catch (error: Throwable) {
                ToastCenter.error(error)
            }
        }
    }

    fun togglePin(note: Note) {
        val wasPinned = PinnedNotesService.isPinned(note.id)
        App.scope.launch {
            try {
                PinnedNotesService.toggle(note.id)
                ToastCenter.show(if (wasPinned) L("noteUnpinned") else L("notePinned"), ToastStyle.SUCCESS)
                DataBus.listsChanged()
            } catch (error: Throwable) {
                ToastCenter.error(error)
            }
        }
    }

    fun confirmMute(note: Note) {
        val pubkey = note.pubkey
        App.scope.launch {
            Moderation.mute(pubkey)
            ToastCenter.show(L("feedUserMuted"), ToastStyle.SUCCESS)
        }
    }

    fun toggleThreadMute(note: Note) {
        val root = note.rootId ?: note.id
        val wasMuted = MuteService.isThreadMuted(root)
        App.scope.launch {
            if (wasMuted) MuteService.unmuteThread(root) else MuteService.muteThread(root)
            ToastCenter.show(if (wasMuted) L("feedConversationUnmuted") else L("feedConversationMuted"), ToastStyle.SUCCESS)
        }
    }

    fun confirmDelete(note: Note) {
        NoteInteractionStore.markDeleted(note.id, note.parentId)
        App.scope.launch {
            try {
                InteractionService.delete(note)
                ToastCenter.show(L("feedNoteDeleted"), ToastStyle.SUCCESS)
            } catch (error: Throwable) {
                NoteInteractionStore.unmarkDeleted(note.id, note.parentId)
                ToastCenter.error(error)
            }
        }
    }
}

@Composable
fun ColumnScope.NoteMenuItems(note: Note, actions: NoteActionHandler, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val isMine = note.pubkey == Session.pubkey
    LaunchedEffect(note.id) { NoteLanguage.detect(note) }
    val item: @Composable (String, ImageVector, Boolean, String, () -> Unit) -> Unit = { title, icon, destructive, tag, action ->
        val color = if (destructive) AppColors.error else AppColors.textPrimary
        DropdownMenuItem(
            text = { Text(title) },
            leadingIcon = { Icon(icon, null) },
            onClick = { onDismiss(); action() },
            colors = MenuDefaults.itemColors(textColor = color, leadingIconColor = color),
            modifier = Modifier.testTag(tag),
        )
    }
    if (NoteLanguage.needsTranslation(note)) item(L("feedTranslate"), Icons.Outlined.Translate, false, "note-menu-translate") { NoteLanguage.translate(context, note) }
    item(L("feedCopyText"), Icons.Outlined.ContentCopy, false, "note-menu-copy-text") { actions.copyText(context, note) }
    item(L("feedCopyNoteId"), Icons.Outlined.Tag, false, "note-menu-copy-id") { actions.copyId(context, note) }
    item(L("share"), Icons.Outlined.Share, false, "note-menu-share") { NoteActionHandler.share(context, note) }
    HorizontalDivider()
    val bookmarked = BookmarkService.isBookmarked(note.id)
    item(
        if (bookmarked) L("feedRemoveBookmark") else L("addBookmark"),
        if (bookmarked) Icons.Outlined.BookmarkRemove else Icons.Outlined.Bookmark,
        false,
        "note-menu-bookmark",
    ) { actions.toggleBookmark(note) }
    if (isMine) {
        val pinned = PinnedNotesService.isPinned(note.id)
        item(if (pinned) L("unpinNote") else L("pinNote"), Icons.Outlined.PushPin, false, "note-menu-pin") { actions.togglePin(note) }
    }
    item(L("statistics"), Icons.Outlined.BarChart, false, "note-menu-statistics") { Router.push(Route.NoteStatistics(note.id)) }
    item(L("quotes"), Icons.Outlined.FormatQuote, false, "note-menu-quotes") { Router.push(Route.Quotes(note.id)) }
    item(L("verifySignature"), Icons.Outlined.VerifiedUser, false, "note-menu-verify") { actions.verify(note) }
    HorizontalDivider()
    val threadMuted = MuteService.isThreadMuted(note.rootId ?: note.id)
    item(
        if (threadMuted) L("feedUnmuteConversation") else L("feedMuteConversation"),
        if (threadMuted) Icons.Outlined.Notifications else Icons.Outlined.NotificationsOff,
        false,
        "note-menu-mute-conversation",
    ) { actions.toggleThreadMute(note) }
    if (isMine) {
        item(L("delete"), Icons.Outlined.Delete, true, "note-menu-delete") { actions.pendingDelete = note }
    } else {
        item(L("feedMuteAuthor"), Icons.AutoMirrored.Outlined.VolumeOff, false, "note-menu-mute") { actions.pendingMute = note }
        item(L("report"), Icons.Outlined.Flag, true, "note-menu-report") { actions.reportTarget = note }
    }
}

@Composable
fun NoteActionDialogs(actions: NoteActionHandler) {
    actions.pendingDelete?.let { note ->
        AlertDialog(
            onDismissRequest = { actions.pendingDelete = null },
            title = { Text(L("deleteThisPost")) },
            confirmButton = {
                TextButton(onClick = { actions.pendingDelete = null; actions.confirmDelete(note) }, modifier = Modifier.testTag("note-delete-confirm")) {
                    Text(L("delete"), color = AppColors.error, fontWeight = FontWeight.SemiBold)
                }
            },
            dismissButton = { TextAction(L("cancel"), { actions.pendingDelete = null }) },
        )
    }
    actions.pendingMute?.let { note ->
        val name = ProfileCache.profiles[note.pubkey]?.bestName ?: note.authorName ?: Profile.shortNpub(note.pubkey)
        AlertDialog(
            onDismissRequest = { actions.pendingMute = null },
            title = { Text(L("muteUser", "user" to name)) },
            text = { Text(L("muteUserDescription")) },
            confirmButton = {
                TextButton(onClick = { actions.pendingMute = null; actions.confirmMute(note) }, modifier = Modifier.testTag("note-mute-confirm")) {
                    Text(L("mute"), color = AppColors.error, fontWeight = FontWeight.SemiBold)
                }
            },
            dismissButton = { TextAction(L("cancel"), { actions.pendingMute = null }) },
        )
    }
    actions.reportTarget?.let { note ->
        ReportSheet(ReportTarget.from(note), onDismiss = { actions.reportTarget = null })
    }
}
