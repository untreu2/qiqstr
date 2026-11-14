package me.untreu.qiqstr.ui.profile

import android.content.pm.PackageManager
import android.graphics.Bitmap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.PrimaryButton
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.SecondaryButton
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache

object QRCodeRenderer {
    fun image(text: String, size: Int = 720): ImageBitmap? = runCatching {
        val hints = mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.MARGIN to 0)
        val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size, hints)
        val pixels = IntArray(matrix.width * matrix.height) { index ->
            if (matrix.get(index % matrix.width, index / matrix.width)) android.graphics.Color.BLACK else android.graphics.Color.WHITE
        }
        Bitmap.createBitmap(pixels, matrix.width, matrix.height, Bitmap.Config.ARGB_8888).asImageBitmap()
    }.getOrNull()
}

@Composable
fun ShareProfileSheet(pubkey: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val npub = remember(pubkey) { Nip19.npub(pubkey) ?: pubkey }
    val link = "nostr:$npub"
    val profile = ProfileCache.profiles[pubkey]
    var qr by remember { mutableStateOf<ImageBitmap?>(null) }
    LaunchedEffect(pubkey) {
        qr = withContext(Dispatchers.Default) { QRCodeRenderer.image(link) }
        if (ProfileCache.profile(pubkey) == null) ProfileCache.load(listOf(pubkey))
    }
    val scanner = rememberLauncherForActivityResult(ScanContract()) { result ->
        val value = result.contents ?: return@rememberLauncherForActivityResult
        val hex = Nip19.pubkeyHex(Nip19.stripScheme(value.trim()))
        if (hex == null) {
            ToastCenter.show(L("profileInvalidQRCode"), ToastStyle.ERROR)
            return@rememberLauncherForActivityResult
        }
        onDismiss()
        App.scope.launch {
            delay(350)
            Router.push(Route.Profile(hex))
        }
    }

    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(L("shareProfile"), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            IconButton(onClick = onDismiss, modifier = Modifier.testTag("share-profile-close")) { Icon(Icons.Outlined.Close, L("closeDialog")) }
        }
        Surface(shape = RoundedCornerShape(32.dp), color = AppColors.tile, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    ProfileAvatar(pubkey, size = 52.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(profile?.bestName ?: L("anonymous"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        profile?.nip05?.ifEmpty { null }?.let {
                            Text(Nip05Verifier.display(it), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
                val qrLabel = L("shareProfile")
                Box(
                    Modifier.widthIn(max = 320.dp).fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(24.dp)).background(Color.White),
                    contentAlignment = Alignment.Center,
                ) {
                    val bitmap = qr
                    if (bitmap != null) {
                        Image(
                            bitmap,
                            contentDescription = null,
                            contentScale = ContentScale.Fit,
                            filterQuality = FilterQuality.None,
                            modifier = Modifier.fillMaxWidth().padding(18.dp).semantics { contentDescription = qrLabel }.testTag("share-profile-qr"),
                        )
                    } else {
                        CircularProgressIndicator(color = Color.Black)
                    }
                }
                Text(L("shareThisToReceiveMessages"), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, textAlign = TextAlign.Center)
            }
        }
        val copyLabel = L("copy")
        Surface(
            onClick = { ProfileSharing.copy(npub, L("copiedNpub")) },
            shape = RoundedCornerShape(22.dp),
            color = AppColors.tile,
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = copyLabel }.testTag("share-profile-copy"),
        ) {
            Row(Modifier.padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(L("publicKeyNpub"), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = AppColors.textSecondary)
                    Text(npub, style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace), maxLines = 3)
                }
                Icon(Icons.Outlined.ContentCopy, null)
            }
        }
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            PrimaryButton(
                L("share"),
                { ProfileSharing.share(context, link, profile?.bestName ?: L("profile")) },
                icon = Icons.Outlined.Share,
                modifier = Modifier.fillMaxWidth().testTag("share-profile-sharelink"),
            )
            SecondaryButton(
                L("scanQRCode"),
                {
                    if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)) {
                        ToastCenter.show(L("profileScannerUnavailable"), ToastStyle.ERROR)
                    } else {
                        scanner.launch(
                            ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE).setPrompt(L("scanQRCode")).setBeepEnabled(false).setOrientationLocked(true),
                        )
                    }
                },
                icon = Icons.Outlined.QrCodeScanner,
                modifier = Modifier.fillMaxWidth().testTag("share-profile-scan"),
            )
        }
    }
}
