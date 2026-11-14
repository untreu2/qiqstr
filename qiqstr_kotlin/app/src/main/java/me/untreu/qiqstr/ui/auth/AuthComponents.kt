package me.untreu.qiqstr.ui.auth

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.PersistableBundle
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Error
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.AppFont
import me.untreu.qiqstr.core.AppLanguage
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.IconTile

@Composable
fun AuthHeader(title: String, subtitle: String? = null, titleSize: Int = 32, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            title,
            style = AppFont.brandSemibold(titleSize.sp).copy(letterSpacing = (-titleSize * 0.02).sp),
            color = AppColors.textPrimary,
            modifier = Modifier.semantics { heading() },
        )
        if (subtitle != null) {
            Text(subtitle, style = MaterialTheme.typography.bodyLarge, color = AppColors.textSecondary)
        }
    }
}

@Composable
fun AuthFeatureRow(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        IconTile(icon, size = 40.dp)
        Text(text, style = MaterialTheme.typography.bodyLarge, color = AppColors.textPrimary, modifier = Modifier.weight(1f))
    }
}

@Composable
fun AuthErrorText(message: String, modifier: Modifier = Modifier, tag: String = "auth-error") {
    Row(modifier.fillMaxWidth().testTag(tag), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(Icons.Filled.Error, null, tint = AppColors.error, modifier = Modifier.size(18.dp))
        Text(message, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = AppColors.error)
    }
}

@Composable
fun OnboardingStepIndicator(current: Int, total: Int = 4) {
    val label = L("authStepOf", "current" to current, "total" to total)
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.semantics { contentDescription = label }.testTag("onboarding-step-$current"),
    ) {
        for (index in 1..total) {
            val width by animateDpAsState(if (index == current) 22.dp else 8.dp, label = "step")
            Box(
                Modifier.width(width).height(8.dp).clip(CircleShape)
                    .background(if (index <= current) AppColors.textPrimary else AppColors.overlayLight),
            )
        }
    }
}

object SecureClipboard {
    private val manager: ClipboardManager get() = App.context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    fun copy(value: String, sensitive: Boolean = true) {
        val clip = ClipData.newPlainText("qiqstr", value)
        if (sensitive && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            clip.description.extras = PersistableBundle().apply {
                putBoolean(if (Build.VERSION.SDK_INT >= 33) ClipDescription.EXTRA_IS_SENSITIVE else "android.content.extra.IS_SENSITIVE", true)
            }
        }
        manager.setPrimaryClip(clip)
        if (!sensitive) return
        App.scope.launch {
            delay(120_000)
            val current = manager.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString()
            if (current == value) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) manager.clearPrimaryClip() else manager.setPrimaryClip(ClipData.newPlainText("", ""))
            }
        }
    }

    fun paste(): String? = manager.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(App.context)?.toString()?.trim()?.ifEmpty { null }
}

class Haptics(private val view: View) {
    fun success() = view.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.CONTEXT_CLICK)
    fun error() = view.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS)
    fun selection() = view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    fun impact() = view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
}

@Composable
fun rememberHaptics(): Haptics {
    val view = LocalView.current
    return remember(view) { Haptics(view) }
}

@Composable
fun rememberQrScanner(onScan: (String) -> Unit): () -> Unit {
    val haptics = rememberHaptics()
    val launcher = rememberLauncherForActivityResult(ScanContract()) { result ->
        val value = result.contents?.trim()
        if (!value.isNullOrEmpty()) {
            haptics.success()
            onScan(value)
        }
    }
    val prompt = L("scanQRCode")
    return {
        launcher.launch(
            ScanOptions()
                .setDesiredBarcodeFormats(ScanOptions.QR_CODE)
                .setPrompt(prompt)
                .setBeepEnabled(false)
                .setOrientationLocked(true),
        )
    }
}

val AppLanguage.localizedName: String
    get() = when (this) {
        AppLanguage.EN -> L("english")
        AppLanguage.TR -> L("turkish")
        AppLanguage.DE -> L("german")
    }

object SuggestedUsers {
    val pubkeys = listOf(
        "ded3db39158474a8d1dfeb3400e5f1c206f89d1c94d579c18eb2a79a9502043e",
        "fa90c095c6eca1fd3813beb3cfb054836cfa217d949d29a893ad20523123e2ac",
        "5ffb8e1b6b629c0e34a013f9298ebb0759b98a3d24029916321d5eb4255b6735",
        "3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24",
        "6e468422dfb74a5738702a8823b9b28168abab8655faacb6853cd0ee15deee93",
        "c4eabae1be3cf657bc1855ee05e69de9f059cb7a059227168b80b89761cbc4e0",
    )
}

@Composable
fun AuthBottomBar(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().background(AppColors.background).padding(horizontal = 24.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        content()
        Spacer(Modifier.height(0.dp))
    }
}
