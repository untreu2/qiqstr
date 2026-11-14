package me.untreu.qiqstr.ui.explore

import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.data.services.ExploreSafety
import me.untreu.qiqstr.data.services.ExploreSeenStore
import me.untreu.qiqstr.data.services.ExploreService
import me.untreu.qiqstr.data.services.LiveService
import me.untreu.qiqstr.data.services.WebOfTrustService
import me.untreu.qiqstr.data.sync.FeatureHooks
import me.untreu.qiqstr.data.sync.SessionHooks
import me.untreu.qiqstr.ui.notifications.NotificationNoteStore

object ExploreFeature : FeatureHooks {
    override fun register() {
        SessionHooks.onTeardown {
            WebOfTrustService.reset()
            LiveService.reset()
            ExploreSeenStore.reset()
            ExploreService.reset()
            ExploreSafety.reset()
            NotificationNoteStore.reset()
        }
        SessionHooks.onBootstrap { pubkey ->
            ExploreService.refreshPinnedIfNeeded()
            App.scope.launch { WebOfTrustService.load(pubkey) }
        }
    }
}
