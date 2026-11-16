package me.untreu.qiqstr.core

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App

enum class VideoAutoplay(val raw: String) {
    NEVER("never"), WIFI("wifi"), ALWAYS("always");

    val title: String
        get() = when (this) {
            NEVER -> L("settingsAutoplayNever")
            WIFI -> L("settingsAutoplayWifi")
            ALWAYS -> L("settingsAutoplayAlways")
        }

    companion object {
        fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: NEVER
    }
}

object MediaPolicy {
    const val AUTOPLAY_KEY = "video_autoplay"
    const val DATA_SAVER_KEY = "data_saver"

    var isExpensive by mutableStateOf(false)
        private set
    var allowed by mutableStateOf<Set<String>>(emptySet())
        private set
    var autoplay by mutableStateOf(VideoAutoplay.from(Prefs.string(AUTOPLAY_KEY)))
        private set
    var dataSaver by mutableStateOf(Prefs.bool(DATA_SAVER_KEY))
        private set

    init {
        val manager = App.context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        if (manager != null) {
            isExpensive = runCatching { manager.isActiveNetworkMetered }.getOrDefault(false)
            runCatching {
                manager.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                    override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                        update(!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED))
                    }

                    override fun onLost(network: Network) = update(false)
                })
            }
        }
    }

    private fun update(expensive: Boolean) {
        App.scope.launch { if (isExpensive != expensive) isExpensive = expensive }
    }

    fun updateAutoplay(value: VideoAutoplay) {
        autoplay = value
        Prefs.set(AUTOPLAY_KEY, value.raw)
    }

    fun updateDataSaver(value: Boolean) {
        dataSaver = value
        Prefs.set(DATA_SAVER_KEY, value)
    }

    val autoplaysVideo: Boolean
        get() {
            if (defersMedia) return false
            return when (autoplay) {
                VideoAutoplay.NEVER -> false
                VideoAutoplay.WIFI -> !isExpensive
                VideoAutoplay.ALWAYS -> true
            }
        }

    val defersMedia: Boolean get() = dataSaver && isExpensive

    fun loads(url: String): Boolean = !defersMedia || url in allowed

    fun allow(url: String) {
        if (url !in allowed) allowed = allowed + url
    }
}
