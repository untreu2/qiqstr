package me.untreu.qiqstr.core

import java.util.Locale
import me.untreu.qiqstr.App
import org.json.JSONObject

enum class AppLanguage(val code: String, val displayName: String) {
    EN("en", "English"),
    TR("tr", "Türkçe"),
    DE("de", "Deutsch");

    companion object {
        fun from(code: String?): AppLanguage? = entries.firstOrNull { it.code == code }

        val stored: String? get() = Prefs.string("app_language")

        val current: AppLanguage
            get() = from(stored) ?: from(Locale.getDefault().language) ?: EN

        val locale: Locale get() = stored?.let { Locale.forLanguageTag(it) } ?: Locale.getDefault()
    }
}

object Localizer {
    private val tables = listOf("Localizable", "Auth", "Feed", "Profile", "Explore", "DM", "Wallet", "Settings", "Reader")
    private val lock = Any()
    private var language: String? = null
    private var strings: Map<String, String> = emptyMap()
    private val english: Map<String, String> by lazy { load("en") }

    private fun load(lang: String): Map<String, String> {
        val result = HashMap<String, String>()
        for (table in tables) {
            val raw = runCatching {
                App.context.assets.open("i18n/$lang/$table.json").bufferedReader().use { it.readText() }
            }.getOrNull() ?: continue
            val json = JSONObject(raw)
            for (key in json.keys()) if (!result.containsKey(key)) result[key] = json.getString(key)
        }
        return result
    }

    fun apply(code: String?) = synchronized(lock) {
        val lang = (AppLanguage.from(code) ?: AppLanguage.from(Locale.getDefault().language) ?: AppLanguage.EN).code
        language = lang
        strings = if (lang == "en") english else load(lang)
    }

    fun string(key: String): String = synchronized(lock) {
        if (language == null) apply(AppLanguage.stored)
        strings[key] ?: english[key] ?: key
    }
}

fun L(key: String, args: Map<String, Any?> = emptyMap()): String {
    var s = IcuPlural.resolve(Localizer.string(key), args)
    for ((name, value) in args) s = s.replace("{$name}", value.toString())
    return s
}

fun L(key: String, vararg args: Pair<String, Any?>): String = L(key, args.toMap())

object IcuPlural {
    private val start = Regex("""\{(\w+), plural,""")

    fun resolve(template: String, args: Map<String, Any?>): String {
        var result = template
        while (true) {
            val match = start.find(result) ?: break
            val name = match.groupValues[1]
            val end = matchingBrace(result, match.range.first) ?: break
            val body = result.substring(match.range.last + 1, end)
            val count = args[name]?.toString()?.toLongOrNull() ?: 0
            val choices = parseChoices(body)
            val chosen = choices["=$count"] ?: (if (count == 1L) choices["one"] else null) ?: choices["other"] ?: ""
            result = result.substring(0, match.range.first) + chosen.replace("#", count.toString()) + result.substring(end + 1)
        }
        return result
    }

    private fun matchingBrace(s: String, from: Int): Int? {
        var depth = 0
        for (i in from until s.length) {
            if (s[i] == '{') depth++
            if (s[i] == '}') { depth--; if (depth == 0) return i }
        }
        return null
    }

    private fun parseChoices(body: String): Map<String, String> {
        val choices = HashMap<String, String>()
        var i = 0
        while (i < body.length) {
            while (i < body.length && body[i].isWhitespace()) i++
            val keyStart = i
            while (i < body.length && body[i] != '{') i++
            if (i >= body.length) break
            val close = matchingBrace(body, i) ?: break
            choices[body.substring(keyStart, i).trim()] = body.substring(i + 1, close)
            i = close + 1
        }
        return choices
    }
}
