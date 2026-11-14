package me.untreu.qiqstr.ui.note

import android.text.format.DateUtils
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckBox
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.CheckBoxOutlineBlank
import androidx.compose.material.icons.filled.RadioButtonChecked
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.data.services.NotePoll
import me.untreu.qiqstr.data.services.PollService
import me.untreu.qiqstr.data.services.PollTally
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.Session
import kotlin.math.roundToInt

@Composable
fun NotePollView(poll: NotePoll, author: String, modifier: Modifier = Modifier, interactive: Boolean = true) {
    if (poll.id in PollService.invalid) return
    LaunchedEffect(poll.id) { PollService.load(poll) }
    var selection by remember(poll.id) { mutableStateOf<Set<String>>(emptySet()) }
    var confirming by remember { mutableStateOf(false) }
    var voting by remember { mutableStateOf(false) }
    var revealed by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    val tally = PollService.tally(poll.id) ?: PollTally()
    val ended = poll.isEnded()
    val canVote = interactive && !ended && Session.privateKey != null && tally.mine.isEmpty()
    val showsResults = !canVote || revealed

    val submit = {
        val ids = poll.options.map { it.id }.filter { it in selection }
        if (ids.isNotEmpty() && !voting) {
            voting = true
            scope.launch {
                try {
                    PollService.vote(poll, ids)
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    revealed = false
                } catch (error: Throwable) {
                    ToastCenter.show("${L("feedPollVoteFailed")}: ${coreErrorMessage(error)}", ToastStyle.ERROR)
                }
                selection = emptySet()
                voting = false
            }
        }
    }

    Column(modifier.fillMaxWidth().testTag("note-poll"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        poll.options.forEach { option ->
            if (showsResults) ResultRow(option, tally) else OptionButton(poll, option, option.id in selection, voting) {
                if (poll.multiple) {
                    selection = if (option.id in selection) selection - option.id else selection + option.id
                } else {
                    selection = setOf(option.id)
                    confirming = true
                }
            }
        }
        if (canVote && !revealed && poll.multiple && selection.isNotEmpty()) {
            Button(
                onClick = { confirming = true },
                enabled = !voting,
                colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
                modifier = Modifier.fillMaxWidth().testTag("poll-vote"),
            ) {
                if (voting) CircularProgressIndicator(Modifier.size(18.dp), color = AppColors.background, strokeWidth = 2.dp)
                else Text(L("feedPollVote"), fontWeight = FontWeight.SemiBold)
            }
        }
        Footer(poll, tally, ended, canVote, revealed) { revealed = !revealed }
    }

    if (confirming) {
        val title = if (poll.multiple) {
            L("feedPollVoteConfirmMultiple", "count" to selection.size)
        } else {
            L("feedPollVoteConfirm", "option" to (poll.options.firstOrNull { it.id in selection }?.label ?: ""))
        }
        AlertDialog(
            onDismissRequest = {
                confirming = false
                if (!poll.multiple) selection = emptySet()
            },
            title = { Text(title) },
            confirmButton = {
                TextButton(onClick = { confirming = false; submit() }, modifier = Modifier.testTag("poll-confirm-vote")) {
                    Text(L("feedPollVote"), fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary)
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    confirming = false
                    if (!poll.multiple) selection = emptySet()
                }) { Text(L("cancel"), color = AppColors.textPrimary) }
            },
        )
    }
}

@Composable
private fun OptionButton(poll: NotePoll, option: NotePoll.Option, selected: Boolean, disabled: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    Surface(
        onClick = onClick,
        enabled = !disabled,
        shape = shape,
        color = AppColors.inputFill,
        border = BorderStroke(if (selected) 1.dp else 0.5.dp, if (selected) AppColors.link else AppColors.border),
        modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp).testTag("poll-option"),
    ) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            val icon = if (poll.multiple) {
                if (selected) Icons.Filled.CheckBox else Icons.Filled.CheckBoxOutlineBlank
            } else {
                if (selected) Icons.Filled.RadioButtonChecked else Icons.Filled.RadioButtonUnchecked
            }
            Icon(icon, null, Modifier.size(20.dp), tint = if (selected) AppColors.link else AppColors.textSecondary)
            Text(option.label, style = MaterialTheme.typography.bodyMedium, color = AppColors.textPrimary, modifier = Modifier.weight(1f))
        }
    }
}

@Composable
private fun ResultRow(option: NotePoll.Option, tally: PollTally) {
    val share = tally.share(option.id).toFloat()
    val animated by animateFloatAsState(share, label = "poll-share")
    val mine = option.id in tally.mine
    val count = tally.counts[option.id] ?: 0
    val leading = count > 0 && count == tally.counts.values.maxOrNull()
    var width by remember { mutableStateOf(0) }
    val density = LocalDensity.current
    val shape = RoundedCornerShape(12.dp)
    Box(
        Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(shape).background(AppColors.inputFill.copy(alpha = 0.5f))
            .onSizeChanged { width = it.width }
            .testTag("poll-result"),
    ) {
        val barWidth = with(density) { maxOf(if (share > 0) 12.dp.toPx() else 0f, width * animated).toDp() }
        Box(Modifier.matchParentSize()) {
            Box(Modifier.width(barWidth).fillMaxHeight().clip(shape).background(if (mine) AppColors.link.copy(alpha = 0.22f) else AppColors.tile))
        }
        Row(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                option.label,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = if (leading) FontWeight.SemiBold else FontWeight.Normal,
                color = AppColors.textPrimary,
            )
            if (mine) Icon(Icons.Filled.CheckCircle, L("feedPollYourVote"), Modifier.size(16.dp), tint = AppColors.link)
            Spacer(Modifier.weight(1f))
            Text("${(share * 100).roundToInt()}%", style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
        }
    }
}

@Composable
private fun Footer(poll: NotePoll, tally: PollTally, ended: Boolean, canVote: Boolean, revealed: Boolean, onToggle: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(top = 2.dp), verticalAlignment = Alignment.CenterVertically) {
        val parts = mutableListOf(L("feedPollVotes", "count" to tally.voters))
        status(poll, ended)?.let { parts.add(it) }
        if (poll.multiple && canVote) parts.add(L("feedPollMultiple"))
        Text(
            parts.joinToString(" · "),
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textSecondary,
            maxLines = 1,
            modifier = Modifier.weight(1f),
        )
        if (canVote) {
            TextButton(onClick = onToggle, modifier = Modifier.testTag("poll-toggle-results")) {
                Text(if (revealed) L("feedPollHideResults") else L("feedPollShowResults"), style = MaterialTheme.typography.bodySmall, color = AppColors.link)
            }
        }
    }
}

private fun status(poll: NotePoll, ended: Boolean): String? {
    if (ended) return L("feedPollEnded")
    val endsAt = poll.endsAt ?: return null
    val relative = DateUtils.getRelativeTimeSpanString(endsAt * 1000, TimeFormat.now * 1000, DateUtils.MINUTE_IN_MILLIS).toString()
    return L("feedPollEndsIn", "time" to relative)
}
