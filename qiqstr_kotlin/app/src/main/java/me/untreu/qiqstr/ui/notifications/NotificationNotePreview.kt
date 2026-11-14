package me.untreu.qiqstr.ui.notifications

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.qiqstr.core.dbGetHydratedNote
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile

object NotificationNoteStore {
    val notes = mutableStateMapOf<String, Note>()
    private var missing by mutableStateOf<Set<String>>(emptySet())
    private val inflight = HashSet<String>()

    fun note(id: String): Note? = notes[id]
    fun isMissing(id: String): Boolean = id in missing

    suspend fun load(id: String) {
        if (notes.containsKey(id) || !inflight.add(id)) return
        try {
            fetchLocal(id)?.let { store(it); return }
            withTimeoutOrNull(6_000) { SyncService.syncNote(id) }
            val note = fetchLocal(id)
            if (note != null) store(note) else missing = missing + id
        } finally {
            inflight.remove(id)
        }
    }

    fun reset() {
        notes.clear()
        missing = emptySet()
    }

    private fun store(note: Note) {
        notes[note.id] = note
        if (note.id in missing) missing = missing - note.id
        if (ProfileCache.profile(note.pubkey) == null) App.scope.launch { ProfileCache.load(listOf(note.pubkey)) }
    }

    private suspend fun fetchLocal(id: String): Note? {
        val obj = Json.obj(runCatching { dbGetHydratedNote(id, Session.pubkey) }.getOrNull()) ?: return null
        return Note.from(obj).takeIf { it.id.isNotEmpty() }
    }
}

object NotificationText {
    private val pattern = Regex("nostr:(npub1|nprofile1|note1|nevent1|naddr1)[0-9a-z]+")

    fun readable(content: String): String = pattern.replace(content) { match ->
        val bech = match.value.removePrefix("nostr:")
        if (bech.startsWith("npub1") || bech.startsWith("nprofile1")) {
            Nip19.pubkeyHex(bech)?.let { hex -> "@" + (ProfileCache.profiles[hex]?.bestName ?: Profile.shortNpub(hex)) } ?: ""
        } else {
            ""
        }
    }.trim()
}

@Composable
fun NotificationNotePreview(noteId: String) {
    if (NotificationNoteStore.isMissing(noteId)) return
    LaunchedEffect(noteId) { NotificationNoteStore.load(noteId) }
    val note = NotificationNoteStore.note(noteId)
    Box(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(AppColors.overlayLight.copy(alpha = AppColors.overlayLight.alpha * 0.6f))
            .padding(12.dp),
    ) {
        if (note != null) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    ProfileAvatar(note.pubkey, size = 18.dp, fallbackUrl = note.authorImage)
                    Text(
                        ProfileCache.profiles[note.pubkey]?.bestName ?: note.authorName ?: Profile.shortNpub(note.pubkey),
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    Text(TimeFormat.relative(note.createdAt), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
                }
                val text = NotificationText.readable(note.content)
                if (text.isNotEmpty()) {
                    Text(text, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 3, overflow = TextOverflow.Ellipsis)
                }
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.size(18.dp).clip(CircleShape).background(AppColors.overlayLight))
                Box(Modifier.width(140.dp).height(10.dp).clip(RoundedCornerShape(4.dp)).background(AppColors.overlayLight))
            }
        }
    }
}
