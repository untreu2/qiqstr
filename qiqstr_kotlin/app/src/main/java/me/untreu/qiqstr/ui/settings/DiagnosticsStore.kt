package me.untreu.qiqstr.ui.settings

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File
import me.untreu.qiqstr.App
import me.untreu.qiqstr.BuildConfig
import me.untreu.qiqstr.core.Prefs
import org.json.JSONObject

data class DiagnosticReport(
    val file: File,
    val receivedAt: Long,
    val crashes: Int,
    val hangs: Int,
    val other: Int,
) {
    val id: String get() = file.name
}

object DiagnosticsStore {
    private const val LIMIT = 30
    private const val TRACE_LIMIT = 256 * 1024
    private const val PROCESSED_KEY = "diagnostics_exit_processed_until"

    var reports by mutableStateOf<List<DiagnosticReport>>(emptyList())
        private set
    private var isActive = false

    val directory: File get() = File(App.context.filesDir, "Diagnostics")

    fun activate() {
        if (isActive) return
        isActive = true
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            runCatching { recordCrash(thread, error) }
            previous?.uncaughtException(thread, error)
        }
        runCatching { importExitReasons() }
        reload()
    }

    fun reload() {
        reports = directory.listFiles().orEmpty().mapNotNull(::report).sortedByDescending { it.receivedAt }
    }

    fun delete(report: DiagnosticReport) {
        report.file.delete()
        reload()
    }

    fun deleteAll() {
        reports.forEach { it.file.delete() }
        reload()
    }

    fun contents(report: DiagnosticReport): String = runCatching { report.file.readText() }.getOrDefault("")

    private fun recordCrash(thread: Thread, error: Throwable) {
        val json = base("crash", System.currentTimeMillis())
            .put("thread", thread.name)
            .put("exception", error.javaClass.name)
            .put("message", error.message ?: "")
            .put("stackTrace", error.stackTraceToString().take(TRACE_LIMIT))
        write(json, System.currentTimeMillis(), 1, 0, 0)
        prune()
    }

    private fun importExitReasons() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val manager = App.context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val processedUntil = Prefs.long(PROCESSED_KEY)
        val exits = manager.getHistoricalProcessExitReasons(App.context.packageName, 0, 0)
            .filter { it.timestamp > processedUntil }
        var newest = processedUntil
        val existing = directory.listFiles().orEmpty().mapNotNull(::report).filter { it.crashes > 0 }.map { it.receivedAt }
        for (exit in exits) {
            newest = maxOf(newest, exit.timestamp)
            val counts = when (exit.reason) {
                ApplicationExitInfo.REASON_CRASH -> {
                    if (existing.any { kotlin.math.abs(it - exit.timestamp) < 15_000 }) continue
                    Triple(1, 0, 0)
                }
                ApplicationExitInfo.REASON_CRASH_NATIVE -> Triple(1, 0, 0)
                ApplicationExitInfo.REASON_ANR -> Triple(0, 1, 0)
                ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE,
                ApplicationExitInfo.REASON_INITIALIZATION_FAILURE,
                ApplicationExitInfo.REASON_LOW_MEMORY -> Triple(0, 0, 1)
                else -> continue
            }
            val json = base(reasonName(exit.reason), exit.timestamp)
                .put("description", exit.description ?: "")
                .put("importance", exit.importance)
                .put("pss", exit.pss)
                .put("rss", exit.rss)
                .put("status", exit.status)
            if (exit.reason == ApplicationExitInfo.REASON_ANR) {
                runCatching { exit.traceInputStream?.bufferedReader()?.use { it.readText().take(TRACE_LIMIT) } }.getOrNull()?.let { json.put("trace", it) }
            }
            write(json, exit.timestamp, counts.first, counts.second, counts.third)
        }
        Prefs.set(PROCESSED_KEY, newest)
        prune()
    }

    private fun reasonName(reason: Int) = when (reason) {
        ApplicationExitInfo.REASON_CRASH -> "crash"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "native_crash"
        ApplicationExitInfo.REASON_ANR -> "anr"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "excessive_resource_usage"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "initialization_failure"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "low_memory"
        else -> "other"
    }

    private fun base(type: String, timestamp: Long) = JSONObject()
        .put("type", type)
        .put("timestamp", timestamp)
        .put("appVersion", "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
        .put("device", "${Build.MANUFACTURER} ${Build.MODEL}")
        .put("android", "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")

    private fun write(json: JSONObject, timestamp: Long, crashes: Int, hangs: Int, other: Int) {
        directory.mkdirs()
        val file = File(directory, "diagnostics-${timestamp / 1000}-$crashes-$hangs-$other.json")
        if (file.exists()) return
        file.writeText(json.toString(2))
    }

    private fun prune() {
        directory.listFiles().orEmpty().mapNotNull(::report).sortedByDescending { it.receivedAt }.drop(LIMIT).forEach { it.file.delete() }
    }

    private fun report(file: File): DiagnosticReport? {
        if (file.extension != "json") return null
        val parts = file.nameWithoutExtension.split("-")
        if (parts.size != 5 || parts[0] != "diagnostics") return null
        val stamp = parts[1].toLongOrNull() ?: return null
        return DiagnosticReport(file, stamp * 1000, parts[2].toIntOrNull() ?: return null, parts[3].toIntOrNull() ?: return null, parts[4].toIntOrNull() ?: return null)
    }
}
