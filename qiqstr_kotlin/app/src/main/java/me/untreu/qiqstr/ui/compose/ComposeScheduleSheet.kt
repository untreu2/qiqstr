package me.untreu.qiqstr.ui.compose

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.EventBusy
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.util.Calendar
import java.util.TimeZone
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.TextAction

@Composable
internal fun ComposeScheduleSheet(scheduledAt: Long?, onChange: (Long?) -> Unit, onDismiss: () -> Unit) {
    var date by remember { mutableLongStateOf(scheduledAt ?: (TimeFormat.now + 3600)) }
    var picking by remember { mutableStateOf(false) }
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, containerColor = AppColors.background) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(bottom = 12.dp).testTag("compose-schedule-sheet")) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onDismiss, modifier = Modifier.testTag("compose-schedule-cancel")) { Icon(Icons.Outlined.Close, L("cancel")) }
                Text(L("feedSchedule"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f).padding(start = 4.dp))
                Button(
                    onClick = {
                        onChange(maxOf(date, TimeFormat.now + 60))
                        onDismiss()
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
                    modifier = Modifier.padding(end = 8.dp).testTag("compose-schedule-done"),
                ) {
                    Icon(Icons.Outlined.Check, null, Modifier.size(18.dp))
                    Text(L("done"), Modifier.padding(start = 6.dp), fontWeight = FontWeight.SemiBold)
                }
            }
            Row(
                Modifier.fillMaxWidth().clickable { picking = true }.padding(horizontal = 16.dp, vertical = 16.dp).testTag("compose-schedule-date"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(Icons.Outlined.Schedule, null, tint = AppColors.textSecondary)
                Text(L("feedScheduleDate"), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                Text(TimeFormat.full(date), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, color = AppColors.link)
            }
            Text(L("feedScheduleFooter"), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
            if (scheduledAt != null) {
                HorizontalDivider(Modifier.padding(top = 12.dp), color = AppColors.divider)
                Row(
                    Modifier.fillMaxWidth()
                        .clickable {
                            onChange(null)
                            onDismiss()
                        }
                        .padding(horizontal = 16.dp, vertical = 16.dp)
                        .testTag("compose-schedule-remove"),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(Icons.Outlined.EventBusy, null, tint = AppColors.error)
                    Text(L("feedScheduleRemove"), style = MaterialTheme.typography.bodyLarge, color = AppColors.error)
                }
            }
        }
    }
    if (picking) {
        ComposeDateTimePicker(date, onPick = { date = maxOf(it, TimeFormat.now + 120) }) { picking = false }
    }
}

@Composable
internal fun ComposeDateTimePicker(initial: Long, onPick: (Long) -> Unit, onDismiss: () -> Unit) {
    var pickedDay by remember { mutableStateOf<Long?>(null) }
    val day = pickedDay
    if (day == null) {
        val today = remember {
            Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
                val local = Calendar.getInstance()
                clear()
                set(local.get(Calendar.YEAR), local.get(Calendar.MONTH), local.get(Calendar.DAY_OF_MONTH))
            }.timeInMillis
        }
        val selected = remember(initial) {
            val local = Calendar.getInstance().apply { timeInMillis = initial * 1000 }
            Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
                clear()
                set(local.get(Calendar.YEAR), local.get(Calendar.MONTH), local.get(Calendar.DAY_OF_MONTH))
            }.timeInMillis
        }
        val state = rememberDatePickerState(
            initialSelectedDateMillis = selected,
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis >= today
            },
        )
        DatePickerDialog(
            onDismissRequest = onDismiss,
            confirmButton = { TextAction(L("done"), { state.selectedDateMillis?.let { pickedDay = it } ?: onDismiss() }) },
            dismissButton = { TextAction(L("cancel"), onDismiss) },
        ) { DatePicker(state) }
    } else {
        val current = remember(initial) { Calendar.getInstance().apply { timeInMillis = initial * 1000 } }
        val state = rememberTimePickerState(current.get(Calendar.HOUR_OF_DAY), current.get(Calendar.MINUTE))
        AlertDialog(
            onDismissRequest = onDismiss,
            text = { TimePicker(state) },
            confirmButton = {
                TextAction(L("done"), {
                    val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply { timeInMillis = day }
                    val local = Calendar.getInstance().apply {
                        clear()
                        set(utc.get(Calendar.YEAR), utc.get(Calendar.MONTH), utc.get(Calendar.DAY_OF_MONTH), state.hour, state.minute)
                    }
                    onPick(local.timeInMillis / 1000)
                    onDismiss()
                })
            },
            dismissButton = { TextAction(L("cancel"), onDismiss) },
        )
    }
}
