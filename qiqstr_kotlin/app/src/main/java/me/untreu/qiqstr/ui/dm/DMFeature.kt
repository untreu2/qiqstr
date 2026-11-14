package me.untreu.qiqstr.ui.dm

import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.data.accounts.AccountData
import me.untreu.qiqstr.data.services.MuteService
import me.untreu.qiqstr.data.sync.FeatureHooks
import me.untreu.qiqstr.data.sync.SessionHooks

object DMFeature : FeatureHooks {
    override fun register() {
        SessionHooks.onTeardown { DMService.reset() }
        SessionHooks.onBootstrap { App.scope.launch { DMService.start() } }
        MuteService.onChange { DMService.mutesChanged() }
        AccountData.onErase { MarmotEngine.close() }
    }
}
