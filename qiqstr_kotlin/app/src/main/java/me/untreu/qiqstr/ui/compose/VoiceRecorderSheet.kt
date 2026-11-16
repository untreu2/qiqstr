package me.untreu.qiqstr.ui.compose

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.MicOff
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.drop
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.PrimaryButton
import me.untreu.qiqstr.core.components.SecondaryButton
import me.untreu.qiqstr.data.services.AudioPlayback
import me.untreu.qiqstr.data.services.VoiceRecorder
import me.untreu.qiqstr.data.services.VoiceRecording
import me.untreu.qiqstr.ui.auth.rememberHaptics
import me.untreu.qiqstr.ui.note.AudioPlayerView
import me.untreu.qiqstr.ui.note.WaveformBars

@Composable
internal fun VoiceRecorderSheet(onDismiss: () -> Unit, onFinish: (VoiceRecording) -> Unit) {
    val recorder = remember { VoiceRecorder() }
    val attached = remember { booleanArrayOf(false) }
    val haptics = rememberHaptics()
    val context = LocalContext.current
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = { it != SheetValue.Hidden || !recorder.isRecording })
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) recorder.start() else recorder.deny()
    }
    val close = {
        AudioPlayback.stop()
        recorder.cancel()
        onDismiss()
    }
    LaunchedEffect(recorder) {
        if (VoiceRecorder.hasPermission) recorder.start() else permission.launch(Manifest.permission.RECORD_AUDIO)
    }
    LaunchedEffect(recorder) { snapshotFlow { recorder.isRecording }.drop(1).collect { haptics.impact() } }
    DisposableEffect(recorder) {
        onDispose {
            AudioPlayback.stop()
            if (!attached[0]) recorder.cancel()
        }
    }
    ModalBottomSheet(onDismissRequest = close, sheetState = state, containerColor = AppColors.background) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding().padding(bottom = 20.dp).testTag("voice-recorder"),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = close, modifier = Modifier.testTag("voice-cancel")) { Icon(Icons.Outlined.Close, L("cancel")) }
                Text(L("voiceTitle"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 4.dp))
            }
            Box(Modifier.fillMaxWidth().heightIn(min = 160.dp), contentAlignment = Alignment.Center) {
                when (val current = recorder.state) {
                    VoiceRecorder.State.Denied -> EmptyStateView(Icons.Outlined.MicOff, L("voiceMicDenied"), L("voiceMicDeniedMessage"), actionTitle = L("openSettings")) {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                        runCatching { context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                    }
                    VoiceRecorder.State.Failed -> EmptyStateView(Icons.Outlined.WarningAmber, L("voiceRecordFailed"), actionTitle = L("retryText")) { recorder.start() }
                    is VoiceRecorder.State.Finished -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(24.dp)) {
                        VoiceTime(current.recording.duration)
                        AudioPlayerView(
                            url = current.recording.path,
                            duration = current.recording.duration,
                            waveform = current.recording.waveform,
                            modifier = Modifier.padding(horizontal = 20.dp).fillMaxWidth()
                                .clip(RoundedCornerShape(18.dp)).background(AppColors.inputFill)
                                .padding(horizontal = 14.dp, vertical = 12.dp),
                        )
                    }
                    VoiceRecorder.State.Idle, VoiceRecorder.State.Recording -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(24.dp)) {
                        VoiceTime(recorder.elapsed, Modifier.testTag("voice-elapsed"))
                        WaveformBars(
                            levels = recorder.levels.takeLast(60).map { (it * 100).toInt() },
                            progress = 1.0,
                            tint = AppColors.reaction,
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 28.dp).height(56.dp).alpha(if (recorder.isRecording) 1f else 0.3f),
                        )
                    }
                }
            }
            when (val current = recorder.state) {
                VoiceRecorder.State.Recording -> PrimaryButton(
                    L("voiceStop"),
                    { recorder.stop() },
                    Modifier.fillMaxWidth().padding(horizontal = 20.dp).testTag("voice-stop"),
                    icon = Icons.Filled.Stop,
                )
                is VoiceRecorder.State.Finished -> Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    SecondaryButton(
                        L("voiceRecordAgain"),
                        {
                            AudioPlayback.stop()
                            recorder.cancel()
                            recorder.start()
                        },
                        Modifier.weight(1f).testTag("voice-redo"),
                        icon = Icons.Outlined.Refresh,
                    )
                    PrimaryButton(
                        L("voiceAttach"),
                        {
                            AudioPlayback.stop()
                            attached[0] = true
                            onFinish(current.recording)
                            onDismiss()
                        },
                        Modifier.weight(1f).testTag("voice-attach"),
                        icon = Icons.Outlined.Check,
                    )
                }
                else -> Unit
            }
        }
    }
}

@Composable
private fun VoiceTime(seconds: Double, modifier: Modifier = Modifier) {
    Text(
        VoiceRecorder.format(seconds),
        style = MaterialTheme.typography.displaySmall.copy(fontFeatureSettings = "tnum"),
        fontWeight = FontWeight.SemiBold,
        modifier = modifier,
    )
}
