package me.untreu.qiqstr.data.sync

import me.untreu.qiqstr.data.services.EmojiPackService
import me.untreu.qiqstr.App
import kotlinx.coroutines.launch
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
            EmojiPackService.reset()
        }
        FeatureRegistry.all.forEach { it.register() }
        SessionHooks.onBootstrap { App.scope.launch { EmojiPackService.load() } }
    }
}

interface FeatureHooks {
    fun register()
}
