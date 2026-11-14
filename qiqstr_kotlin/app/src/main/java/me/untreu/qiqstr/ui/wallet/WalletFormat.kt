package me.untreu.qiqstr.ui.wallet

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.text.format.DateUtils
import java.text.DateFormat
import java.util.Calendar
import java.util.Date
import kotlin.math.abs
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.AppLanguage
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle

object WalletFormat {
    fun sats(value: Long): String = Sats.format(abs(value))

    fun signed(value: Long, incoming: Boolean): String = "${if (incoming) "+" else "-"}${sats(value)}"

    fun timestamp(ts: Long): String {
        if (ts <= 0) return ""
        val millis = ts * 1000
        if (DateUtils.isToday(millis)) return time(ts)
        if (DateUtils.isToday(millis + DateUtils.DAY_IN_MILLIS)) return L("yesterday")
        val days = daysBetween(startOfDay(millis), startOfDay(System.currentTimeMillis()))
        if (days < 7) return L("daysAgo", "days" to days)
        return DateFormat.getDateInstance(DateFormat.MEDIUM, AppLanguage.locale).format(Date(millis))
    }

    fun time(ts: Long): String = DateFormat.getTimeInstance(DateFormat.SHORT, AppLanguage.locale).format(Date(ts * 1000))

    fun truncated(text: String, head: Int = 12, tail: Int = 8): String {
        if (text.length <= head + tail + 3) return text
        return "${text.take(head)}…${text.takeLast(tail)}"
    }

    fun startOfDay(millis: Long): Long = Calendar.getInstance().apply {
        timeInMillis = millis
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    private fun daysBetween(from: Long, to: Long): Long = Math.round((to - from) / DateUtils.DAY_IN_MILLIS.toDouble())

    fun countdown(seconds: Long): String {
        val s = seconds.coerceAtLeast(0)
        val h = s / 3600
        val m = (s % 3600) / 60
        val sec = s % 60
        return if (h > 0) String.format("%d:%02d:%02d", h, m, sec) else String.format("%d:%02d", m, sec)
    }
}

internal object WalletClipboard {
    private val manager: ClipboardManager get() = App.context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    fun text(): String? = runCatching { manager.primaryClip?.getItemAt(0)?.coerceToText(App.context)?.toString() }.getOrNull()

    val hasContent: Boolean
        get() = runCatching {
            val description = manager.primaryClipDescription ?: return false
            manager.hasPrimaryClip() && (description.hasMimeType("text/*") || description.hasMimeType(android.content.ClipDescription.MIMETYPE_TEXT_URILIST))
        }.getOrDefault(false)

    fun copy(text: String, toast: String = L("copiedToClipboard")) {
        manager.setPrimaryClip(ClipData.newPlainText("qiqstr", text))
        ToastCenter.show(toast, ToastStyle.SUCCESS)
    }

    fun share(context: Context, text: String) {
        val intent = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
        runCatching { context.startActivity(Intent.createChooser(intent, L("share"))) }
    }
}
