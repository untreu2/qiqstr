package me.untreu.qiqstr.ui.compose

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat

@Composable
internal fun ComposeGoalEditor(model: ComposeViewModel) {
    var picking by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().padding(start = 52.dp).testTag("compose-goal-editor"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        OutlinedTextField(model.goalAmount, { model.goalAmount = it.filter(Char::isDigit) }, label = { Text(L("zapGoalAmountPlaceholder")) }, suffix = { Text(L("walletSats")) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true, modifier = Modifier.fillMaxWidth().testTag("compose-goal-amount"))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(L("zapGoalDeadline"), Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
            Switch(model.goalHasEnd, { model.goalHasEnd = it }, modifier = Modifier.testTag("compose-goal-end-toggle"))
        }
        if (model.goalHasEnd) TextButton(onClick = { picking = true }, modifier = Modifier.testTag("compose-goal-end-date")) { Text("${L("zapGoalEndsOn")}: ${TimeFormat.full(model.goalEndsAt)}") }
    }
    if (picking) {
        val state = rememberDatePickerState(initialSelectedDateMillis = model.goalEndsAt * 1000)
        DatePickerDialog(onDismissRequest = { picking = false }, confirmButton = {
            TextButton(onClick = { state.selectedDateMillis?.let { model.goalEndsAt = maxOf(TimeFormat.now + 3600, it / 1000) }; picking = false }) { Text(L("done")) }
        }, dismissButton = { TextButton(onClick = { picking = false }) { Text(L("cancel")) } }) { DatePicker(state) }
    }
}
