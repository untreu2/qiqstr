package me.untreu.qiqstr.ui.compose

import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.data.services.MediaServerStore
import me.untreu.qiqstr.data.sync.FeatureHooks
import me.untreu.qiqstr.data.sync.SessionHooks

object ComposeFeature : FeatureHooks {
    override fun register() {
        SessionHooks.onTeardown {
            ScheduledPostService.reset()
            MediaServerStore.reset()
        }
        SessionHooks.onBootstrap {
            ScheduledPostService.start()
            App.scope.launch { MediaServerStore.load() }
        }
    }
}
