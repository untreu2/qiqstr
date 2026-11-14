package me.untreu.qiqstr.ui.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import java.text.DateFormat
import java.util.Calendar
import java.util.Date
import java.util.TimeZone
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.AppLanguage
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.TextAction

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ComposePollEditor(model: ComposeViewModel) {
    Column(Modifier.fillMaxWidth().padding(start = 52.dp).testTag("compose-poll-editor"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        model.pollOptions.forEachIndexed { index, option ->
            key(option.id) {
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(AppColors.inputFill).padding(start = 14.dp, end = 4.dp, top = 4.dp, bottom = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.weight(1f).padding(vertical = 8.dp)) {
                        val style = MaterialTheme.typography.bodyLarge
                        if (option.text.isEmpty()) Text(L("feedPollOption", "number" to index + 1), style = style, color = AppColors.textTertiary)
                        BasicTextField(
                            value = option.text,
                            onValueChange = { option.text = it },
                            singleLine = true,
                            textStyle = style.copy(color = AppColors.textPrimary),
                            cursorBrush = SolidColor(AppColors.textPrimary),
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                            modifier = Modifier.fillMaxWidth().testTag("compose-poll-option"),
                        )
                    }
                    if (model.pollOptions.size > ComposeViewModel.MIN_POLL_OPTIONS) {
                        ComposeIconRemove({ model.removePollOption(option) }, L("feedPollRemoveOption"), "compose-poll-remove-option")
                    }
                }
            }
        }
        if (model.pollOptions.size < ComposeViewModel.MAX_POLL_OPTIONS) {
            TextButton(onClick = { model.addPollOption() }, modifier = Modifier.testTag("compose-poll-add-option")) {
                Icon(Icons.Outlined.Add, null, tint = AppColors.link)
                Text(L("feedPollAddOption"), Modifier.padding(start = 6.dp), color = AppColors.link, fontWeight = FontWeight.SemiBold)
            }
        }
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().testTag("compose-poll-type")) {
            listOf(false, true).forEachIndexed { index, multiple ->
                SegmentedButton(
                    selected = model.pollMultiple == multiple,
                    onClick = { model.pollMultiple = multiple },
                    shape = SegmentedButtonDefaults.itemShape(index, 2),
                ) { Text(if (multiple) L("feedPollMultiple") else L("feedPollSingle")) }
            }
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(L("feedPollEndDate"), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            Switch(
                checked = model.pollHasEnd,
                onCheckedChange = { model.pollHasEnd = it },
                colors = SwitchDefaults.colors(checkedTrackColor = AppColors.switchActive),
                modifier = Modifier.testTag("compose-poll-end-toggle"),
            )
        }
        if (model.pollHasEnd) PollEndPicker(model)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PollEndPicker(model: ComposeViewModel) {
    var pickingDate by remember { mutableStateOf(false) }
    var pickingTime by remember { mutableStateOf(false) }
    var pickedDay by remember { mutableStateOf<Long?>(null) }
    val minimum = TimeFormat.now + 300
    val locale = AppLanguage.locale
    val formatted = remember(model.pollEndsAt, locale) {
        DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, locale).format(Date(model.pollEndsAt * 1000))
    }
    Row(Modifier.fillMaxWidth().testTag("compose-poll-end-date"), verticalAlignment = Alignment.CenterVertically) {
        Text(L("feedPollEnds"), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        TextAction(formatted, { pickingDate = true })
    }
    if (pickingDate) {
        val today = remember {
            Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
                val local = Calendar.getInstance()
                clear()
                set(local.get(Calendar.YEAR), local.get(Calendar.MONTH), local.get(Calendar.DAY_OF_MONTH))
            }.timeInMillis
        }
        val initial = remember(model.pollEndsAt) {
            val local = Calendar.getInstance().apply { timeInMillis = model.pollEndsAt * 1000 }
            Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
                clear()
                set(local.get(Calendar.YEAR), local.get(Calendar.MONTH), local.get(Calendar.DAY_OF_MONTH))
            }.timeInMillis
        }
        val state = rememberDatePickerState(
            initialSelectedDateMillis = initial,
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis >= today
            },
        )
        DatePickerDialog(
            onDismissRequest = { pickingDate = false },
            confirmButton = {
                TextAction(L("done"), {
                    pickedDay = state.selectedDateMillis
                    pickingDate = false
                    pickingTime = pickedDay != null
                })
            },
            dismissButton = { TextAction(L("cancel"), { pickingDate = false }) },
        ) { DatePicker(state) }
    }
    if (pickingTime) {
        val current = remember(model.pollEndsAt) { Calendar.getInstance().apply { timeInMillis = model.pollEndsAt * 1000 } }
        val state = rememberTimePickerState(current.get(Calendar.HOUR_OF_DAY), current.get(Calendar.MINUTE))
        AlertDialog(
            onDismissRequest = { pickingTime = false },
            text = { TimePicker(state) },
            confirmButton = {
                TextAction(L("done"), {
                    val day = pickedDay
                    if (day != null) {
                        val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply { timeInMillis = day }
                        val local = Calendar.getInstance().apply {
                            clear()
                            set(utc.get(Calendar.YEAR), utc.get(Calendar.MONTH), utc.get(Calendar.DAY_OF_MONTH), state.hour, state.minute)
                        }
                        model.pollEndsAt = maxOf(minimum, local.timeInMillis / 1000)
                    }
                    pickingTime = false
                })
            },
            dismissButton = { TextAction(L("cancel"), { pickingTime = false }) },
        )
    }
}
