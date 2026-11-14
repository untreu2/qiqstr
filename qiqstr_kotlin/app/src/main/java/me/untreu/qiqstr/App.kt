package me.untreu.qiqstr

import android.app.Application
import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        instance = this
        me.untreu.qiqstr.data.sync.ServiceRegistry.register()
    }

    companion object {
        lateinit var instance: App
            private set
        val context: Context get() = instance.applicationContext
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    }
}
