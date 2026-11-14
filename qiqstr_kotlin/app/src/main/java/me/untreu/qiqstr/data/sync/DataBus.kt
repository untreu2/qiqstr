package me.untreu.qiqstr.data.sync

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

object DataBus {
    var feedVersion by mutableIntStateOf(0)
        private set
    var profileVersion by mutableIntStateOf(0)
        private set
    var notificationVersion by mutableIntStateOf(0)
        private set
    var interactionVersion by mutableIntStateOf(0)
        private set
    var dmVersion by mutableIntStateOf(0)
        private set
    var listsVersion by mutableIntStateOf(0)
        private set
    var lastFeedIds by mutableStateOf<List<String>>(emptyList())
        private set

    fun feedChanged(ids: List<String> = emptyList()) { lastFeedIds = ids; feedVersion++ }
    fun profileChanged() { profileVersion++ }
    fun notificationsChanged() { notificationVersion++ }
    fun interactionsChanged() { interactionVersion++ }
    fun dmChanged() { dmVersion++ }
    fun listsChanged() { listsVersion++ }
    fun everythingChanged() {
        feedChanged(); profileChanged(); notificationsChanged(); interactionsChanged(); dmChanged(); listsChanged()
    }
}
