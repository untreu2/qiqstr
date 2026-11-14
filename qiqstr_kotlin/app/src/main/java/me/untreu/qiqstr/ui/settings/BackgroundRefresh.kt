package me.untreu.qiqstr.ui.settings

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import me.untreu.qiqstr.App
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SessionPhase

object BackgroundRefresh {
    const val IDENTIFIER = "me.untreu.qiqstr.refresh"
    private const val INTERVAL_MINUTES = 15L
    private var launchTask: Deferred<Unit>? = null

    fun schedule() {
        if (!LocalNotificationService.isEnabled) return
        val request = PeriodicWorkRequestBuilder<RefreshWorker>(INTERVAL_MINUTES, TimeUnit.MINUTES)
            .setInitialDelay(INTERVAL_MINUTES, TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        runCatching { WorkManager.getInstance(App.context).enqueueUniquePeriodicWork(IDENTIFIER, ExistingPeriodicWorkPolicy.KEEP, request) }
    }

    fun cancel() {
        runCatching { WorkManager.getInstance(App.context).cancelUniqueWork(IDENTIFIER) }
    }

    suspend fun launchSession() {
        launchTask?.let { return it.await() }
        if (Session.phase != SessionPhase.Launching) return
        val task = App.scope.async { Session.launch() }
        launchTask = task
        task.await()
    }

    suspend fun run() {
        withTimeoutOrNull(25_000) { refresh() }
    }

    private suspend fun refresh() {
        if (!LocalNotificationService.isEnabled) return
        launchSession()
        LocalNotificationService.activate()
        LocalNotificationService.refreshStatus()
        if (!LocalNotificationService.isAuthorized || Session.phase != SessionPhase.Ready) return
        val me = Session.pubkey ?: return
        LocalNotificationService.checkForNewActivity(me)
    }
}

class RefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        withContext(Dispatchers.Main) { BackgroundRefresh.run() }
        return Result.success()
    }
}
