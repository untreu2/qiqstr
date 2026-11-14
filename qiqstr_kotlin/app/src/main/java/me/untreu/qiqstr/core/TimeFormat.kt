package me.untreu.qiqstr.core

import android.icu.text.MeasureFormat
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import java.text.DateFormat
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date

object TimeFormat {
    val now: Long get() = System.currentTimeMillis() / 1000

    fun relative(timestamp: Long): String {
        val diff = (now - timestamp).coerceIn(0, 86400L * 365 * 10_000)
        val locale = AppLanguage.locale
        if (diff >= 86400 * 7) {
            val date = Date(timestamp * 1000)
            val sameYear = Calendar.getInstance().apply { time = date }.get(Calendar.YEAR) == Calendar.getInstance().get(Calendar.YEAR)
            val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, if (sameYear) "MMMd" else "yMMMd")
            return SimpleDateFormat(pattern, locale).format(date)
        }
        val (value, unit) = when {
            diff < 60 -> diff to MeasureUnit.SECOND
            diff < 3600 -> diff / 60 to MeasureUnit.MINUTE
            diff < 86400 -> diff / 3600 to MeasureUnit.HOUR
            else -> diff / 86400 to MeasureUnit.DAY
        }
        val width = if (locale.language == "en") MeasureFormat.FormatWidth.NARROW else MeasureFormat.FormatWidth.SHORT
        return MeasureFormat.getInstance(locale, width).format(Measure(value, unit))
    }

    fun full(timestamp: Long): String =
        DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, AppLanguage.locale).format(Date(timestamp * 1000))
}

object Sats {
    fun format(sats: Long): String = NumberFormat.getIntegerInstance(AppLanguage.locale).format(sats)

    fun compact(n: Long): String = when {
        n >= 1_000_000 -> String.format(java.util.Locale.US, "%.1fM", n / 1_000_000.0).replace(".0", "")
        n >= 1_000 -> String.format(java.util.Locale.US, "%.1fK", n / 1_000.0).replace(".0", "")
        else -> n.toString()
    }
}
