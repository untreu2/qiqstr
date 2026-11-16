package me.untreu.qiqstr.ui.live

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Sensors
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.VideocamOff
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VolumeOff
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.DisposableEffect
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.LoadingView
import me.untreu.qiqstr.core.components.PillButton
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.RemoteImage
import me.untreu.qiqstr.data.services.LiveStream
import me.untreu.qiqstr.data.services.MuteService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.ui.explore.MenuAction

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LiveStreamScreen(coordinate: String) {
    val model: LiveStreamViewModel = viewModel(key = "live-$coordinate") { LiveStreamViewModel(coordinate) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var menuOpen by remember { mutableStateOf(false) }
    val stream = model.stream

    LaunchedEffect(Unit) { model.load() }
    LaunchedEffect(Unit) { model.refreshStreamPeriodically() }
    LaunchedEffect(stream?.coordinate) { model.runChat() }
    LaunchedEffect(DataBus.profileVersion) { model.refreshProfiles() }
    LaunchedEffect(Session.mutedPubkeys) { model.applyMutes() }
    DisposableEffect(model) { onDispose { if ((context as? android.app.Activity)?.isChangingConfigurations != true) model.stop() } }

    Scaffold(
        modifier = Modifier.fillMaxSize().testTag("live-stream"),
        containerColor = AppColors.background,
        contentWindowInsets = WindowInsets(0),
        topBar = {
            TopAppBar(
                title = { Text(stream?.title?.ifEmpty { null } ?: L("liveTitle"), maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } },
                actions = {
                    if (stream != null) {
                        Box {
                            IconButton(onClick = { menuOpen = true }, modifier = Modifier.testTag("live-menu")) {
                                Icon(Icons.Outlined.MoreVert, L("profileMoreActions"))
                            }
                            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                                stream.naddr?.let { naddr ->
                                    MenuAction(L("share"), Icons.Outlined.Share) {
                                        menuOpen = false
                                        shareText(context, "nostr:$naddr")
                                    }
                                }
                                if (stream.host != Session.pubkey) {
                                    MenuAction(L("mute"), Icons.Outlined.VolumeOff, destructive = true) {
                                        menuOpen = false
                                        scope.launch {
                                            runCatching { MuteService.mute(stream.host) }
                                                .onSuccess {
                                                    ToastCenter.show(L("feedUserMuted"), ToastStyle.SUCCESS)
                                                    Router.pop()
                                                }
                                                .onFailure(ToastCenter::error)
                                        }
                                    }
                                }
                            }
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background),
            )
        },
        bottomBar = {
            if (model.showsChatInput) {
                LiveChatInput(model.draft, { model.draft = it }, model.canSend, model.isSending) { model.send() }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when {
                stream != null -> Column(Modifier.fillMaxSize()) {
                    LivePlayerArea(stream, model.playbackURL, model.isPlaying)
                    LiveStreamHeader(stream, model::openHost, model::zapHost)
                    HorizontalDivider(color = AppColors.divider)
                    LiveChatList(model.messages, model.chatLoaded, stream.isLive, Modifier.weight(1f))
                }
                model.notFound -> EmptyStateView(
                    icon = Icons.Outlined.Sensors,
                    title = L("liveNotFound"),
                    message = L("liveNotFoundMessage"),
                    modifier = Modifier.align(Alignment.Center),
                )
                else -> LoadingView()
            }
        }
    }
}

@Composable
fun LivePlayerArea(stream: LiveStream, playbackURL: String?, playing: Boolean) {
    Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).background(Color.Black).testTag("live-player"), contentAlignment = Alignment.Center) {
        if (playbackURL != null) {
            if (LivePlayback.failed) {
                androidx.compose.material3.TextButton(onClick = { Router.openUrl(playbackURL) }) { Text(L("exploreOpenInBrowser"), color = Color.White) }
            } else LiveStreamPlayer(Modifier.fillMaxSize())
        } else {
            if (stream.image != null) RemoteImage(stream.image, Modifier.fillMaxSize().alpha(0.35f))
            Column(Modifier.padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Outlined.VideocamOff, null, tint = Color.White)
                Text(L("liveEndedMessage"), style = MaterialTheme.typography.bodyMedium, color = Color.White, textAlign = TextAlign.Center)
            }
        }
    }
}

@Composable
fun LiveStreamHeader(stream: LiveStream, onHost: () -> Unit, onZap: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (stream.isLive) {
                LivePill()
            } else if (stream.canReplay) {
                Text(L("liveEnded"), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = AppColors.textSecondary)
            }
            val viewers = stream.participants
            if (stream.isLive && viewers != null) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    Icon(Icons.Outlined.Visibility, null, Modifier.size(14.dp), tint = AppColors.textSecondary)
                    Text(L("liveWatching", "count" to Sats.compact(viewers)), style = MaterialTheme.typography.labelMedium, color = AppColors.textSecondary)
                }
            }
            Text(TimeFormat.relative(stream.startedAt), style = MaterialTheme.typography.labelMedium, color = AppColors.textSecondary)
        }
        if (stream.title.isNotEmpty()) {
            Text(stream.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                Modifier.weight(1f).clickable(onClick = onHost).testTag("live-host"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                ProfileAvatar(stream.host, size = 32.dp)
                Text(liveHostName(stream.host), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.size(8.dp))
            PillButton(L("liveZapHost"), onZap, filled = false, icon = Icons.Filled.Bolt, modifier = Modifier.testTag("live-zap-host"))
        }
        if (stream.summary.isNotEmpty()) {
            Text(stream.summary, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, maxLines = 3, overflow = TextOverflow.Ellipsis)
        }
    }
}
