package me.untreu.qiqstr.ui.wallet

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.FlashlightOff
import androidx.compose.material.icons.outlined.FlashlightOn
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material.icons.outlined.QrCode2
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.EncodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import com.journeyapps.barcodescanner.BarcodeView
import com.journeyapps.barcodescanner.DefaultDecoderFactory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.core.L

object QRCodes {
    fun bitmap(content: String): Bitmap? {
        if (content.isEmpty()) return null
        return runCatching {
            val matrix = QRCodeWriter().encode(
                content,
                BarcodeFormat.QR_CODE,
                0,
                0,
                mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.MARGIN to 0),
            )
            val pixels = IntArray(matrix.width * matrix.height) { index ->
                if (matrix.get(index % matrix.width, index / matrix.width)) android.graphics.Color.BLACK else android.graphics.Color.WHITE
            }
            Bitmap.createBitmap(pixels, matrix.width, matrix.height, Bitmap.Config.ARGB_8888)
        }.getOrNull()
    }

    fun detect(context: Context, uri: Uri): String? = runCatching {
        val source = context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) } ?: return null
        val scale = minOf(1f, 1600f / maxOf(source.width, source.height))
        val bitmap = if (scale < 1f) Bitmap.createScaledBitmap(source, (source.width * scale).toInt(), (source.height * scale).toInt(), true) else source
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        val reader = MultiFormatReader().apply {
            setHints(mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE), DecodeHintType.TRY_HARDER to true))
        }
        reader.decodeWithState(BinaryBitmap(HybridBinarizer(RGBLuminanceSource(bitmap.width, bitmap.height, pixels)))).text
    }.getOrNull()
}

@Composable
fun QRCodeView(content: String, size: Dp = 260.dp, modifier: Modifier = Modifier) {
    val bitmap = remember(content) { QRCodes.bitmap(content)?.asImageBitmap() }
    Box(
        modifier
            .clip(RoundedCornerShape(28.dp))
            .background(Color.White)
            .padding(18.dp)
            .size(size)
            .testTag("qr-code"),
        contentAlignment = Alignment.Center,
    ) {
        if (bitmap != null) {
            Image(bitmap, null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit, filterQuality = FilterQuality.None)
        } else {
            Icon(Icons.Outlined.QrCode2, null, Modifier.size(size * 0.4f), tint = Color.Black.copy(alpha = 0.2f))
        }
    }
}

private enum class CameraPermission { UNDETERMINED, AUTHORIZED, DENIED, UNAVAILABLE }

@Composable
fun QRScannerDialog(onScan: (String) -> Unit, onDismiss: () -> Unit, title: String = L("scanQRCode")) {
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    var permission by remember { mutableStateOf(CameraPermission.UNDETERMINED) }
    var torchOn by remember { mutableStateOf(false) }
    var scanned by remember { mutableStateOf(false) }
    var photoError by remember { mutableStateOf(false) }
    val hasTorch = remember { context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_FLASH) }

    fun deliver(code: String) {
        if (scanned) return
        scanned = true
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        onScan(code.trim())
        onDismiss()
    }

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        permission = if (granted) CameraPermission.AUTHORIZED else CameraPermission.DENIED
    }
    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val code = withContext(Dispatchers.Default) { QRCodes.detect(context, uri) }
            if (code != null) deliver(code) else photoError = true
        }
    }

    LaunchedEffect(Unit) {
        permission = when {
            !context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) -> CameraPermission.UNAVAILABLE
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED -> CameraPermission.AUTHORIZED
            else -> {
                permissionLauncher.launch(Manifest.permission.CAMERA)
                CameraPermission.UNDETERMINED
            }
        }
    }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black).testTag("qr-scanner")) {
            when (permission) {
                CameraPermission.UNDETERMINED -> CircularProgressIndicator(Modifier.align(Alignment.Center), color = Color.White)
                CameraPermission.AUTHORIZED -> {
                    CameraScanner(torchOn, Modifier.fillMaxSize()) { deliver(it) }
                    Box(
                        Modifier.align(Alignment.Center).size(250.dp).border(BorderStroke(3.dp, Color.White.copy(alpha = 0.85f)), RoundedCornerShape(32.dp)),
                    )
                }
                CameraPermission.DENIED -> PermissionMessage(L("walletCameraAccessTitle"), L("walletCameraAccessMessage"), showSettings = true, Modifier.align(Alignment.Center))
                CameraPermission.UNAVAILABLE -> PermissionMessage(L("walletCameraUnavailable"), L("walletCameraUnavailableMessage"), showSettings = false, Modifier.align(Alignment.Center))
            }
            Column(Modifier.fillMaxSize().safeDrawingPadding().padding(20.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    ScannerIconButton(Icons.Outlined.Close, L("closeDialog"), Modifier.testTag("qr-close")) { onDismiss() }
                    Text(title, Modifier.weight(1f), color = Color.White, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
                    if (permission == CameraPermission.AUTHORIZED && hasTorch) {
                        ScannerIconButton(if (torchOn) Icons.Outlined.FlashlightOn else Icons.Outlined.FlashlightOff, L("walletFlashlight"), Modifier.testTag("qr-torch")) { torchOn = !torchOn }
                    } else {
                        Spacer(Modifier.size(48.dp))
                    }
                }
                Spacer(Modifier.weight(1f))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ScannerFooterButton(L("walletChoosePhoto"), Icons.Outlined.Image, Modifier.weight(1f).testTag("qr-photo")) {
                        photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    }
                    ScannerFooterButton(L("walletPaste"), Icons.Outlined.ContentPaste, Modifier.weight(1f).testTag("qr-paste")) {
                        WalletClipboard.text()?.trim()?.takeIf { it.isNotEmpty() }?.let { deliver(it) }
                    }
                }
            }
        }
    }

    if (photoError) {
        AlertDialog(
            onDismissRequest = { photoError = false },
            title = { Text(L("walletNoQRCodeFound")) },
            confirmButton = { androidx.compose.material3.TextButton(onClick = { photoError = false }) { Text(L("ok")) } },
        )
    }
}

@Composable
private fun ScannerIconButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    FilledTonalIconButton(
        onClick = onClick,
        modifier = modifier.size(48.dp),
        colors = IconButtonDefaults.filledTonalIconButtonColors(containerColor = Color.White.copy(alpha = 0.16f), contentColor = Color.White),
    ) {
        Icon(icon, label)
    }
}

@Composable
private fun ScannerFooterButton(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, modifier: Modifier = Modifier, onClick: () -> Unit) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier.heightIn(min = 50.dp),
        shape = CircleShape,
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.3f)),
        colors = ButtonDefaults.outlinedButtonColors(containerColor = Color.White.copy(alpha = 0.12f), contentColor = Color.White),
    ) {
        Icon(icon, null, Modifier.size(18.dp))
        Spacer(Modifier.size(8.dp))
        Text(title, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

@Composable
private fun PermissionMessage(title: String, message: String, showSettings: Boolean, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    Column(modifier.padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Icon(Icons.Outlined.PhotoCamera, null, Modifier.size(44.dp), tint = Color.White)
        Text(title, color = Color.White, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Text(message, color = Color.White.copy(alpha = 0.7f), style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
        if (showSettings) {
            Button(
                onClick = {
                    runCatching {
                        context.startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)),
                        )
                    }
                },
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color.Black),
                modifier = Modifier.padding(top = 6.dp).testTag("qr-open-settings"),
            ) {
                Text(L("walletOpenSettings"), fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun CameraScanner(torchOn: Boolean, modifier: Modifier = Modifier, onCode: (String) -> Unit) {
    val lifecycleOwner = LocalLifecycleOwner.current
    val context = LocalContext.current
    val latest by rememberUpdatedState(onCode)
    val view = remember {
        BarcodeView(context).apply {
            decoderFactory = DefaultDecoderFactory(listOf(BarcodeFormat.QR_CODE))
        }
    }
    DisposableEffect(lifecycleOwner) {
        view.decodeContinuous { result -> result.text?.let { latest(it) } }
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> view.resume()
                Lifecycle.Event.ON_PAUSE -> view.pause()
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        if (lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) view.resume()
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            view.pause()
        }
    }
    LaunchedEffect(torchOn) { runCatching { view.setTorch(torchOn) } }
    AndroidView(factory = { view }, modifier = modifier)
}
