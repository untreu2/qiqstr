package me.untreu.qiqstr.ui.communities

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.AddPhotoAlternate
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.*
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.*
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.RemoteImage
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.services.ReadOnlyGate
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.compose.MediaSanitizer
import me.untreu.qiqstr.ui.compose.MediaUploadService
import me.untreu.qiqstr.ui.note.NoteRow

class CommunityViewModel(private val coordinate: String) : ViewModel() {
    var community by mutableStateOf<Community?>(null)
        private set
    var posts by mutableStateOf<List<Note>>(emptyList())
        private set
    var loaded by mutableStateOf(false)
        private set
    var refreshing by mutableStateOf(false)
        private set
    var updating by mutableStateOf(false)
        private set
    val joined: Boolean get() = community?.let(CommunityService::isJoined) == true
    suspend fun load() {
        if (refreshing) return
        refreshing = true
        try {
            if (!CommunityService.hasLoaded) CommunityService.load()
            community = CommunityService.community(coordinate)
            community?.let { ProfileCache.load(it.team); posts = CommunityService.posts(it) }
        } catch (error: CancellationException) { throw error } catch (error: Throwable) { ToastCenter.error(error) } finally { refreshing = false; loaded = true }
    }
    fun refresh() { viewModelScope.launch { load() } }
    fun toggleMembership() {
        val target = community ?: return
        if (updating || !ReadOnlyGate.check()) return
        updating = true
        viewModelScope.launch {
            try { if (joined) CommunityService.leave(target) else CommunityService.join(target); ToastCenter.show(L(if (joined) "communityJoinedToast" else "communityLeftToast"), ToastStyle.SUCCESS) }
            catch (error: Throwable) { ToastCenter.error(error) } finally { updating = false }
        }
    }
    fun copyLink() { community?.let { target -> Nip19.naddr(34550, target.pubkey, target.dTag)?.let { me.untreu.qiqstr.ui.articles.ArticleActions.copy("nostr:$it") } } }
}

class CommunityPostViewModel(private val community: Community) : ViewModel() {
    var text by mutableStateOf("")
    var images by mutableStateOf<List<String>>(emptyList())
        private set
    var busy by mutableStateOf(false)
        private set
    var uploading by mutableStateOf(false)
        private set
    val canPost: Boolean get() = (text.isNotBlank() || images.isNotEmpty()) && !busy && !uploading
    fun remove(url: String) { images = images - url }
    fun upload(uris: List<Uri>) {
        if (uploading || busy) return
        uploading = true
        viewModelScope.launch {
            try {
                for (uri in uris) {
                    val prepared = withContext(Dispatchers.IO) {
                        val mime = App.context.contentResolver.getType(uri) ?: "image/jpeg"
                        val bytes = App.context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: throw CoreError(L("errorSelectingMedia"))
                        MediaSanitizer.prepareImage(bytes, mime) ?: throw CoreError(L("errorSelectingMedia"))
                    }
                    images = images + MediaUploadService.upload(prepared.bytes, prepared.mimeType)
                }
            } catch (error: Throwable) { ToastCenter.error(error) } finally { uploading = false }
        }
    }
    fun post(done: () -> Unit) {
        if (!canPost || !ReadOnlyGate.check()) return
        busy = true
        viewModelScope.launch {
            try { CommunityService.post(text, images, community); text = ""; images = emptyList(); ToastCenter.show(L("communityPosted"), ToastStyle.SUCCESS); done() }
            catch (error: Throwable) { ToastCenter.error(error) } finally { busy = false }
        }
    }
}

@Composable
fun CommunityScreen(coordinate: String) {
    val model: CommunityViewModel = viewModel { CommunityViewModel(coordinate) }
    val scope = rememberCoroutineScope()
    var compose by remember { mutableStateOf(false) }
    var rules by remember { mutableStateOf(false) }
    LaunchedEffect(coordinate) { model.load() }
    LaunchedEffect(DataBus.feedVersion) { if (model.loaded) { delay(400); model.load() } }
    Scaffold(topBar = { TopAppBar(title = { Text(model.community?.displayName ?: L("communityCommunity")) }, navigationIcon = { IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } }, actions = {
        if (model.community != null) IconButton(onClick = { if (ReadOnlyGate.check()) compose = true }, modifier = Modifier.testTag("community-new-post")) { Icon(Icons.Outlined.Edit, L("communityNewPost")) }
    }) }, modifier = Modifier.testTag("community")) { padding ->
        PullToRefreshBox(model.refreshing, onRefresh = model::refresh, modifier = Modifier.padding(padding)) {
            LazyColumn(Modifier.fillMaxSize()) {
                model.community?.let { community ->
                    item("header") {
                        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            if (community.image.isNotEmpty()) RemoteImage(community.image, Modifier.size(64.dp))
                            Text(community.displayName, style = MaterialTheme.typography.headlineSmall)
                            Text(community.summary)
                            Text(L("communityModerators", "count" to community.team.size), color = AppColors.textSecondary)
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { community.team.forEach { pubkey -> ProfileAvatar(pubkey, size = 36.dp, modifier = Modifier.clickable { Router.push(Route.Profile(pubkey)) }) } }
                            Row {
                                if (model.joined) OutlinedButton(onClick = model::toggleMembership, enabled = !model.updating, modifier = Modifier.testTag("community-membership")) { Text(L("communityLeave")) } else Button(onClick = model::toggleMembership, enabled = !model.updating, colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background), modifier = Modifier.testTag("community-membership")) { Text(L("communityJoin")) }
                                if (community.rules.isNotBlank()) TextButton(onClick = { rules = true }, modifier = Modifier.testTag("community-rules")) { Text(L("communityRules")) }
                                TextButton(onClick = model::copyLink) { Text(L("communityCopyLink")) }
                            }
                        }
                    }
                }
                if (model.loaded && model.community == null) item { Text(L("communityNotFound"), Modifier.padding(24.dp)) }
                else if (model.loaded && model.posts.isEmpty()) item { Text(L("communityNoPosts"), Modifier.padding(24.dp).testTag("community-posts-empty")) }
                items(model.posts, key = { it.listId }) { note -> Column(Modifier.testTag("community-post-row")) { NoteRow(note); HorizontalDivider() } }
            }
        }
    }
    if (rules) ModalBottomSheet(onDismissRequest = { rules = false }) { Column(Modifier.navigationBarsPadding().padding(20.dp)) { Text(L("communityRules"), style = MaterialTheme.typography.titleLarge); Text(model.community?.rules.orEmpty()) } }
    if (compose) model.community?.let { community ->
        CommunityPostSheet(community, onDismiss = { compose = false }) { compose = false; scope.launch { model.load() } }
    }
}

@Composable
private fun CommunityPostSheet(community: Community, onDismiss: () -> Unit, onPosted: () -> Unit) {
    val session = remember { java.util.UUID.randomUUID().toString() }
    val model: CommunityPostViewModel = viewModel(key = "community-post-${community.id}-$session") { CommunityPostViewModel(community) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(4), model::upload)
    ModalBottomSheet(onDismissRequest = { if (!model.busy) onDismiss() }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().imePadding().navigationBarsPadding().padding(16.dp).testTag("community-post-sheet"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth()) {
                Text(L("communityNewPost"), style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                TextButton(onClick = { model.post(onPosted) }, enabled = model.canPost, modifier = Modifier.testTag("community-post-send")) { Text(L("communityPost")) }
            }
            OutlinedTextField(model.text, { model.text = it }, placeholder = { Text(L("communityPostPlaceholder")) }, enabled = !model.busy, modifier = Modifier.fillMaxWidth().heightIn(min = 180.dp).testTag("community-post-text"))
            if (model.uploading || model.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            FlowRow { model.images.forEach { url -> Box { RemoteImage(url, Modifier.size(80.dp)); IconButton(onClick = { model.remove(url) }, enabled = !model.busy) { Icon(Icons.Outlined.Close, L("removeThisMediaFile")) } } } }
            IconButton(onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, enabled = !model.uploading && !model.busy, modifier = Modifier.testTag("community-post-images")) { Icon(Icons.Outlined.AddPhotoAlternate, L("articleInsertImage")) }
            Text(L("communityPostFooter", "name" to community.displayName), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
        }
    }
}
