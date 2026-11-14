package me.untreu.qiqstr.core

import android.content.Context
import android.content.SharedPreferences
import me.untreu.qiqstr.App

object Prefs {
    val store: SharedPreferences by lazy { App.context.getSharedPreferences("qiqstr", Context.MODE_PRIVATE) }

    fun string(key: String): String? = store.getString(key, null)
    fun set(key: String, value: String?) = store.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    fun bool(key: String, default: Boolean = false): Boolean = store.getBoolean(key, default)
    fun set(key: String, value: Boolean) = store.edit().putBoolean(key, value).apply()
    fun long(key: String, default: Long = 0): Long = store.getLong(key, default)
    fun set(key: String, value: Long) = store.edit().putLong(key, value).apply()
    fun double(key: String): Double = java.lang.Double.longBitsToDouble(store.getLong(key, 0))
    fun setDouble(key: String, value: Double) = store.edit().putLong(key, java.lang.Double.doubleToRawLongBits(value)).apply()
    fun stringList(key: String): List<String>? = string(key)?.let { Json.stringList(it) }
    fun setStringList(key: String, value: List<String>?) = set(key, value?.let { Json.string(it) })
    fun contains(key: String) = store.contains(key)
    fun remove(key: String) = store.edit().remove(key).apply()
    fun keys(): Set<String> = store.all.keys
    fun clear() = store.edit().clear().apply()
}
