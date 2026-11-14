package me.untreu.qiqstr.ui.wallet

import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.data.accounts.AccountData
import me.untreu.qiqstr.data.sync.FeatureHooks
import me.untreu.qiqstr.data.sync.SessionHooks

object WalletFeature : FeatureHooks {
    override fun register() {
        AccountData.registerCredential { pubkey -> WalletService.credentialKey(pubkey) }
        Router.externalHandlers.add { uri -> WalletService.handleIncoming(uri) }
        SessionHooks.onTeardown {
            WalletService.reset()
            ZapperDirectory.reset()
        }
        SessionHooks.onBootstrap { pubkey ->
            ZapperDirectory.prepare()
            App.scope.launch { WalletService.load() }
            App.scope.launch { ZapperDirectory.verify(pubkey) }
        }
    }
}
