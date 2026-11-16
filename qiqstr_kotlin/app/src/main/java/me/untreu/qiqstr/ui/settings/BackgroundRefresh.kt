package me.untreu.qiqstr.ui.settings

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SessionPhase
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.ui.compose.ScheduledPostService

object BackgroundRefresh {
    const val IDENTIFIER = "me.untreu.qiqstr.refresh"
    const val SCHEDULED_POSTS_IDENTIFIER = "me.untreu.qiqstr.scheduled-posts"
    const val MAX_SCHEDULED_POST_ATTEMPTS = 5
    private const val INTERVAL_MINUTES = 15L
    private var launchTask: Deferred<Unit>? = null
    private var scheduledPostAt: Long? = null

    private val connected: Constraints get() = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

    private val hasDuePost: Boolean get() = ScheduledPostService.nextDue?.let { it <= TimeFormat.now } == true

    fun schedule() {
        scheduleNextPost()
        if (!LocalNotificationService.isEnabled) return
        val request = PeriodicWorkRequestBuilder<RefreshWorker>(INTERVAL_MINUTES, TimeUnit.MINUTES)
            .setInitialDelay(INTERVAL_MINUTES, TimeUnit.MINUTES)
            .setConstraints(connected)
            .build()
        runCatching { WorkManager.getInstance(App.context).enqueueUniquePeriodicWork(IDENTIFIER, ExistingPeriodicWorkPolicy.KEEP, request) }
    }

    private fun scheduleNextPost() {
        val next = ScheduledPostService.nextDue
        if (next == scheduledPostAt) return
        scheduledPostAt = next
        runCatching {
            val manager = WorkManager.getInstance(App.context)
            if (next == null) {
                manager.cancelUniqueWork(SCHEDULED_POSTS_IDENTIFIER)
                return
            }
            val wait = next - TimeFormat.now
            val request = OneTimeWorkRequestBuilder<ScheduledPostWorker>()
                .setInitialDelay(maxOf(0, wait), TimeUnit.SECONDS)
                .setConstraints(connected)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.MINUTES)
                .build()
            manager.enqueueUniqueWork(SCHEDULED_POSTS_IDENTIFIER, if (wait > 0) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP, request)
        }
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

    suspend fun runScheduledPosts(): Boolean {
        withTimeoutOrNull(25_000) {
            launchSession()
            publishScheduledPosts()
        }
        return !hasDuePost
    }

    private suspend fun publishScheduledPosts() {
        if (Session.phase != SessionPhase.Ready || !hasDuePost) return
        for (attempt in 0 until 10) {
            if (SyncService.hasConnectedRelays()) break
            delay(1000)
        }
        ScheduledPostService.publishDue()
        schedule()
    }

    private suspend fun refresh() {
        launchSession()
        publishScheduledPosts()
        if (!LocalNotificationService.isEnabled) return
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

class ScheduledPostWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val finished = withContext(Dispatchers.Main) { BackgroundRefresh.runScheduledPosts() }
        return when {
            finished -> Result.success()
            runAttemptCount + 1 < BackgroundRefresh.MAX_SCHEDULED_POST_ATTEMPTS -> Result.retry()
            else -> Result.failure()
        }
    }
}
