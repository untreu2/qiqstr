package me.untreu.qiqstr.ui.profile

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle

internal object ProfileSharing {
    fun copy(text: String, toast: String = L("copiedToClipboard")) {
        val clipboard = App.context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
        clipboard.setPrimaryClip(ClipData.newPlainText("qiqstr", text))
        ToastCenter.show(toast, ToastStyle.SUCCESS)
    }

    fun share(context: Context, text: String, subject: String? = null) {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
            if (subject != null) putExtra(Intent.EXTRA_SUBJECT, subject)
        }
        runCatching { context.startActivity(Intent.createChooser(send, L("share"))) }
    }
}
