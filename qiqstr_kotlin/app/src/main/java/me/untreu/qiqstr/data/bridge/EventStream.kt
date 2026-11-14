package me.untreu.qiqstr.data.bridge

import com.qiqstr.core.EventSink
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.CoreError

object EventStream {
    fun make(start: suspend (EventSink) -> Unit): Flow<String> = callbackFlow {
        val closed = AtomicBoolean(false)
        val sink = object : EventSink {
            override fun onItem(item: String): Boolean {
                if (closed.get()) return false
                val sent = trySendBlocking(item).isSuccess
                if (!sent) closed.set(true)
                return sent
            }

            override fun onError(message: String) {
                close(CoreError(message))
            }

            override fun onDone() {
                close()
            }

            override fun isClosed(): Boolean = closed.get()
        }
        val job = launch {
            try {
                start(sink)
                close()
            } catch (error: Throwable) {
                close(error)
            }
        }
        awaitClose {
            closed.set(true)
            job.cancel()
        }
    }.buffer(256)
}
