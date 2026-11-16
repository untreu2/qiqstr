package me.untreu.qiqstr.core

import java.util.Locale
import me.untreu.qiqstr.App
import org.json.JSONObject

enum class AppLanguage(val code: String, val displayName: String) {
    EN("en", "English"),
    TR("tr", "Türkçe"),
    DE("de", "Deutsch"),
    ES("es", "Español"),
    PT_BR("pt-BR", "Português (Brasil)"),
    FR("fr", "Français"),
    IT("it", "Italiano"),
    NL("nl", "Nederlands"),
    PL("pl", "Polski");

    companion object {
        fun from(code: String?): AppLanguage? = entries.firstOrNull { it.code == code }

        /** The app language for a tag such as "pt-PT", "es_MX" or "fr", matching on the language part. */
        fun matching(code: String?): AppLanguage? {
            if (code == null) return null
            from(code)?.let { return it }
            val base = code.takeWhile { it != '-' && it != '_' }.lowercase()
            return if (base == "pt") PT_BR else from(base)
        }

        val stored: String? get() = Prefs.string("app_language")

        val current: AppLanguage
            get() = from(stored) ?: matching(Locale.getDefault().toLanguageTag()) ?: EN

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
        val lang = (AppLanguage.from(code) ?: AppLanguage.matching(Locale.getDefault().toLanguageTag()) ?: AppLanguage.EN).code
        language = lang
        strings = if (lang == "en") english else load(lang)
    }

    /** The language the UI is showing, such as "pl" or "pt-BR". */
    val languageCode: String get() = synchronized(lock) { language ?: AppLanguage.current.code }

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
            val chosen = choices["=$count"] ?: choices[category(count, Localizer.languageCode)] ?: choices["other"] ?: ""
            result = result.substring(0, match.range.first) + chosen.replace("#", count.toString()) + result.substring(end + 1)
        }
        return result
    }

    /** The CLDR plural category of a whole number in the app's languages. */
    fun category(n: Long, language: String): String = when (language) {
        "pl" -> when {
            n == 1L -> "one"
            n % 10 in 2..4 && n % 100 !in 12..14 -> "few"
            else -> "many"
        }
        "fr", "pt-BR" -> if (n == 0L || n == 1L) "one" else "other"
        else -> if (n == 1L) "one" else "other"
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
