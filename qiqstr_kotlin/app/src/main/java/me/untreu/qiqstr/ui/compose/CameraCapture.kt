package me.untreu.qiqstr.ui.compose

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.MediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File
import java.util.UUID
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle

enum class CameraCaptureMode(val fileExtension: String) { PHOTO("jpg"), VIDEO("mp4") }

object CameraCapture {
    const val MAX_VIDEO_SECONDS = 180

    val isAvailable: Boolean get() = App.context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)

    val hasPermission: Boolean
        get() = ContextCompat.checkSelfPermission(App.context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    fun file(mode: CameraCaptureMode): File {
        val directory = File(App.context.cacheDir, "captures").apply { mkdirs() }
        return File(directory, "capture-${UUID.randomUUID()}.${mode.fileExtension}")
    }

    fun uri(file: File): Uri = FileProvider.getUriForFile(App.context, "${App.context.packageName}.fileprovider", file)
}

private class CaptureLimitedVideo : ActivityResultContracts.CaptureVideo() {
    override fun createIntent(context: Context, input: Uri): Intent =
        super.createIntent(context, input)
            .putExtra(MediaStore.EXTRA_DURATION_LIMIT, CameraCapture.MAX_VIDEO_SECONDS)
            .putExtra(MediaStore.EXTRA_VIDEO_QUALITY, 1)
}

@Composable
internal fun rememberCameraCapture(onCapture: (CameraCaptureMode, File) -> Unit): (CameraCaptureMode) -> Unit {
    var pendingPath by rememberSaveable { mutableStateOf<String?>(null) }
    var pendingMode by rememberSaveable { mutableStateOf<String?>(null) }
    var requested by remember { mutableStateOf<CameraCaptureMode?>(null) }
    val finish: (Boolean) -> Unit = {
        val file = pendingPath?.let(::File)
        val mode = CameraCaptureMode.entries.firstOrNull { it.name == pendingMode }
        pendingPath = null
        pendingMode = null
        if (file != null && mode != null) {
            if (file.length() > 0) onCapture(mode, file) else file.delete()
        }
    }
    val photo = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture(), finish)
    val video = rememberLauncherForActivityResult(remember { CaptureLimitedVideo() }, finish)
    val launch: (CameraCaptureMode) -> Unit = { mode ->
        val file = CameraCapture.file(mode)
        pendingPath = file.absolutePath
        pendingMode = mode.name
        try {
            (if (mode == CameraCaptureMode.PHOTO) photo else video).launch(CameraCapture.uri(file))
        } catch (_: Throwable) {
            pendingPath = null
            pendingMode = null
            ToastCenter.show(L("walletCameraUnavailable"), ToastStyle.ERROR)
        }
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        val mode = requested
        requested = null
        if (mode != null) {
            if (granted) launch(mode) else ToastCenter.show(L("walletCameraAccessTitle"), ToastStyle.ERROR)
        }
    }
    return { mode ->
        if (CameraCapture.hasPermission) {
            launch(mode)
        } else {
            requested = mode
            permission.launch(Manifest.permission.CAMERA)
        }
    }
}
