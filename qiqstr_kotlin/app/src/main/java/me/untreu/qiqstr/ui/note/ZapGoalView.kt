package me.untreu.qiqstr.ui.note

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.app.AppSheet
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.*
import me.untreu.qiqstr.data.services.ReadOnlyGate
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.ui.wallet.ZapService
import java.text.DateFormat
import java.util.Date
import kotlin.math.roundToInt

data class ZapGoal(val noteId: String, val targetSats: Long, val closesAt: Long?, val summary: String?) {
    val isClosed: Boolean get() = closesAt?.let { it <= TimeFormat.now } ?: false
    companion object {
        const val kind = 9041
        fun from(note: Note): ZapGoal? {
            if (note.kind != kind) return null
            val msats = note.tags.firstOrNull { it.size > 1 && it[0] == "amount" }?.get(1)?.toLongOrNull()?.takeIf { it >= 1000 } ?: return null
            return ZapGoal(note.id, msats / 1000, note.tags.firstOrNull { it.size > 1 && it[0] == "closed_at" }?.get(1)?.toLongOrNull(), note.tags.firstOrNull { it.size > 1 && it[0] == "summary" }?.get(1)?.ifEmpty { null })
        }
    }
}

@Composable
fun ZapGoalView(goal: ZapGoal, note: Note, interactive: Boolean = true) {
    val raised = NoteInteractionStore.model(note).counts.zapAmount.toLong() + ZapService.optimisticSats(note.id)
    val fraction = (raised.toDouble() / goal.targetSats.coerceAtLeast(1)).coerceIn(0.0, 1.0).toFloat()
    LaunchedEffect(note.id) { NoteInteractionStore.requestCounts(listOf(note.id)) }
    Column(Modifier.fillMaxWidth().background(AppColors.inputFill, RoundedCornerShape(16.dp)).padding(12.dp).testTag("zap-goal"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(L("zapGoalTitle"), Modifier.weight(1f), style = MaterialTheme.typography.titleSmall)
            if (goal.isClosed) Text(L("zapGoalEnded"), style = MaterialTheme.typography.bodySmall)
            else goal.closesAt?.let { Text(L("zapGoalEnds", "date" to DateFormat.getDateInstance(DateFormat.MEDIUM, AppLanguage.locale).format(Date(it * 1000))), style = MaterialTheme.typography.bodySmall) }
        }
        LinearProgressIndicator(progress = { fraction }, color = AppColors.zap, modifier = Modifier.fillMaxWidth())
        Row {
            Text(L("zapGoalProgress", "raised" to Sats.format(raised), "target" to Sats.format(goal.targetSats)), Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
            Text("${(fraction * 100).roundToInt()}%", style = MaterialTheme.typography.labelMedium)
        }
        if (interactive && !goal.isClosed && note.pubkey != Session.pubkey) OutlinedButton(onClick = { if (ReadOnlyGate.check()) Router.present(AppSheet.Zap(note)) }, modifier = Modifier.fillMaxWidth().testTag("zap-goal-contribute")) { Text(L("zapGoalContribute")) }
    }
}
