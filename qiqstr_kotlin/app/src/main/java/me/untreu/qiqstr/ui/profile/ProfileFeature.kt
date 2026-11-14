package me.untreu.qiqstr.ui.profile

import me.untreu.qiqstr.data.services.BadgeService
import me.untreu.qiqstr.data.services.FollowService
import me.untreu.qiqstr.data.services.FollowSetService
import me.untreu.qiqstr.data.services.MuteService
import me.untreu.qiqstr.data.sync.FeatureHooks
import me.untreu.qiqstr.data.sync.SessionHooks

object ProfileFeature : FeatureHooks {
    override fun register() {
        SessionHooks.onTeardown {
            FollowService.reset()
            MuteService.reset()
            FollowSetService.reset()
            BadgeService.reset()
        }
        SessionHooks.onBootstrap {
            FollowService.load()
            MuteService.load()
            FollowSetService.load()
        }
    }
}
