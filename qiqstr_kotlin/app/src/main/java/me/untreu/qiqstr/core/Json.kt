package me.untreu.qiqstr.core

import org.json.JSONArray
import org.json.JSONObject

object Json {
    fun obj(string: String?): JSONObject? {
        if (string.isNullOrEmpty()) return null
        return runCatching { JSONObject(string) }.getOrNull()
    }

    fun array(string: String?): List<JSONObject> {
        if (string.isNullOrEmpty()) return emptyList()
        val array = runCatching { JSONArray(string) }.getOrNull() ?: return emptyList()
        return (0 until array.length()).mapNotNull { array.optJSONObject(it) }
    }

    fun any(string: String?): Any? {
        if (string.isNullOrEmpty()) return null
        return runCatching { org.json.JSONTokener(string).nextValue() }.getOrNull()
    }

    fun stringList(string: String?): List<String> {
        val array = (any(string) as? JSONArray) ?: return emptyList()
        return (0 until array.length()).mapNotNull { array.opt(it) as? String }
    }

    fun string(value: Any?): String = when (value) {
        null -> "null"
        is JSONObject -> value.toString()
        is JSONArray -> value.toString()
        is Map<*, *> -> toJson(value).toString()
        is Collection<*> -> toJson(value).toString()
        else -> JSONObject.wrap(value)?.toString() ?: "{}"
    }

    fun toJson(value: Any?): Any? = when (value) {
        null -> JSONObject.NULL
        is Map<*, *> -> JSONObject().apply { value.forEach { (k, v) -> put(k.toString(), toJson(v)) } }
        is Collection<*> -> JSONArray().apply { value.forEach { put(toJson(it)) } }
        is Array<*> -> JSONArray().apply { value.forEach { put(toJson(it)) } }
        else -> value
    }
}

fun JSONObject.str(key: String): String? {
    val value = opt(key)
    return if (value is String && value.isNotEmpty()) value else null
}

fun JSONObject.text(key: String): String = (opt(key) as? String) ?: ""

fun JSONObject.long(key: String): Long = when (val value = opt(key)) {
    is Number -> value.toLong()
    is String -> value.toLongOrNull() ?: 0L
    else -> 0L
}

fun JSONObject.int(key: String): Int = long(key).coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()

fun JSONObject.bool(key: String): Boolean = when (val value = opt(key)) {
    is Boolean -> value
    is Number -> value.toInt() != 0
    else -> false
}

fun JSONObject.has(key: String, type: Class<*>): Boolean = type.isInstance(opt(key))

fun JSONObject.strings(key: String): List<String> {
    val array = optJSONArray(key) ?: return emptyList()
    return (0 until array.length()).mapNotNull { array.opt(it) as? String }
}

fun JSONObject.objects(key: String): List<JSONObject> {
    val array = optJSONArray(key) ?: return emptyList()
    return (0 until array.length()).mapNotNull { array.optJSONObject(it) }
}

fun JSONObject.tags(key: String = "tags"): List<List<String>> {
    val array = optJSONArray(key) ?: return emptyList()
    return (0 until array.length()).mapNotNull { index ->
        val tag = array.optJSONArray(index) ?: return@mapNotNull null
        (0 until tag.length()).map { tag.opt(it)?.toString() ?: "" }
    }
}

fun JSONObject.toMap(): Map<String, Any?> = keys().asSequence().associateWith { opt(it) }
