package me.untreu.qiqstr.data.services

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.data.sync.Session

class ReadOnlyError : Exception() {
    override val message: String get() = L("readOnlyMessage")
}

class ListError : Exception() {
    override val message: String get() = L("listNewCancelled")
}

object ReadOnlyGate {
    var isAlertPresented by mutableStateOf(false)
    var isAddingKey by mutableStateOf(false)

    fun present() {
        if (isAddingKey) return
        isAlertPresented = true
    }

    fun addKey() {
        isAlertPresented = false
        isAddingKey = true
    }

    fun reset() {
        isAlertPresented = false
        isAddingKey = false
    }

    fun check(): Boolean {
        if (!Session.isReadOnly) return true
        present()
        return false
    }

    fun intercepts(message: String): Boolean {
        if (!Session.isReadOnly) return false
        val markers = listOf(L("readOnlyMessage"), L("authenticationRequired"), L("dmNotSignedIn"), L("privateKeyNotFound"), L("walletNoAccount"), "Not signed in", "Not authenticated")
        if (markers.none { message.contains(it) }) return false
        present()
        return true
    }
}

object ListConfirmation {
    var pendingKind by mutableStateOf<Int?>(null)
        private set
    private var answer: CompletableDeferred<Boolean>? = null

    suspend fun startNewList(kind: Int): Boolean {
        answer?.let { return it.await() }
        val deferred = CompletableDeferred<Boolean>()
        answer = deferred
        pendingKind = kind
        return try { deferred.await() } finally { answer = null; pendingKind = null }
    }

    fun respond(start: Boolean) { answer?.complete(start) }

    fun name(kind: Int): String = when (kind) {
        10001 -> L("listNamePins")
        30001 -> L("listNameBookmarks")
        10015 -> L("listNameTopics")
        10002 -> L("listNameRelays")
        else -> L("listNameGeneric")
    }
}

enum class ToastStyle { INFO, SUCCESS, ERROR }

data class Toast(val message: String, val style: ToastStyle, val id: Long = System.nanoTime())

object ToastCenter {
    var current by mutableStateOf<Toast?>(null)
        private set

    fun show(message: String, style: ToastStyle = ToastStyle.INFO) {
        if (style == ToastStyle.ERROR && ReadOnlyGate.intercepts(message)) return
        val toast = Toast(message, style)
        current = toast
        App.scope.launch {
            delay(if (style == ToastStyle.ERROR) 4000 else 2600)
            if (current?.id == toast.id) current = null
        }
    }

    fun error(error: Throwable) {
        if (error is ReadOnlyError) { ReadOnlyGate.present(); return }
        if (error is ListError || error is kotlinx.coroutines.CancellationException) return
        show(coreErrorMessage(error), ToastStyle.ERROR)
    }

    fun dismiss() { current = null }
}
