package me.untreu.qiqstr

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import me.untreu.qiqstr.app.RootScreen
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.QiqstrTheme
import me.untreu.qiqstr.data.sync.Session

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (BuildConfig.DEBUG) intent?.getStringExtra("QIQ_LOGIN")?.let { Session.debugLogin = it }
        handle(intent)
        setContent { QiqstrTheme { RootScreen() } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        val data = intent?.data ?: return
        Router.open(data)
    }
}
