package me.untreu.qiqstr.data.sync

import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.data.services.ReadOnlyGate

object ServiceRegistry {
    private var registered = false

    fun register() {
        if (registered) return
        registered = true
        SessionHooks.onTeardown {
            Router.reset()
            ReadOnlyGate.reset()
        }
        FeatureRegistry.all.forEach { it.register() }
    }
}

interface FeatureHooks {
    fun register()
}
