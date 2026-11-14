package me.untreu.qiqstr.ui.articles

import me.untreu.qiqstr.data.sync.FeatureHooks
import me.untreu.qiqstr.data.sync.SessionHooks

object ArticlesFeature : FeatureHooks {
    override fun register() {
        SessionHooks.onTeardown { ReadingProgressStore.persist() }
    }
}
