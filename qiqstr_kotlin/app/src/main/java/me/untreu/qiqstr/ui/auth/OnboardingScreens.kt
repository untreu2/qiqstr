package me.untreu.qiqstr.ui.auth

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.CameraAlt
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.qiqstr.core.signEvent
import com.qiqstr.core.signBlossomAuthEvent
import com.qiqstr.core.sha256Hash
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.AvatarView
import me.untreu.qiqstr.core.components.PrimaryButton
import me.untreu.qiqstr.core.components.RemoteImage
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.services.RelayConfig
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Profile
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun OnboardingTopBar(step: Int, onBack: (() -> Unit)?, actions: @Composable () -> Unit = {}) {
    CenterAlignedTopAppBar(
        title = { OnboardingStepIndicator(step) },
        navigationIcon = { if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } },
        actions = { actions() },
        colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = AppColors.background),
    )
}

@Composable
private fun OnboardingBottom(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxWidth().background(AppColors.background).navigationBarsPadding().imePadding().padding(horizontal = 24.dp, vertical = 8.dp)) { content() }
}

private data class PendingCopy(val label: String, val value: String)

@Composable
fun OnboardingKeysScreen(onContinue: () -> Unit) {
    val words = remember { Session.revealMnemonic().orEmpty().split(" ").filter { it.isNotEmpty() } }
    val nsec = remember { Session.revealSigningKey()?.let { Nip19.nsec(it) }.orEmpty() }
    var revealNsec by remember { mutableStateOf(false) }
    var pendingCopy by remember { mutableStateOf<PendingCopy?>(null) }
    val haptics = rememberHaptics()
    Scaffold(
        containerColor = AppColors.background,
        topBar = { OnboardingTopBar(1, null) },
        bottomBar = {
            OnboardingBottom {
                PrimaryButton(L("iHaveWrittenDownSeedPhrase"), onContinue, Modifier.fillMaxWidth().testTag("onboarding-keys-continue"))
            }
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 8.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            AuthHeader(L("backupYourAccount"), L("secureYourAccount"))
            if (words.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    KeySectionTitle(L("seedPhrase"), "onboarding-copy-seed") { pendingCopy = PendingCopy(L("seedPhrase"), words.joinToString(" ")) }
                    SeedGrid(words, Modifier.testTag("onboarding-seed-grid"))
                }
            }
            if (nsec.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    KeySectionTitle(L("privateKeyNsec"), "onboarding-copy-nsec") { pendingCopy = PendingCopy(L("privateKeyNsec"), nsec) }
                    Surface(
                        onClick = { revealNsec = !revealNsec },
                        color = AppColors.overlayLight,
                        shape = RoundedCornerShape(22.dp),
                        modifier = Modifier.fillMaxWidth().testTag("onboarding-reveal-nsec")
                            .semantics { contentDescription = if (revealNsec) L("hideKey") else L("showKey") },
                    ) {
                        Row(Modifier.padding(horizontal = 18.dp, vertical = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text(
                                if (revealNsec) nsec else "•".repeat(32),
                                style = MaterialTheme.typography.bodyMedium,
                                fontFamily = FontFamily.Monospace,
                                modifier = Modifier.weight(1f),
                            )
                            Icon(if (revealNsec) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility, null, tint = AppColors.textSecondary)
                        }
                    }
                    Text(L("useThisToRecoverAccount"), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, modifier = Modifier.padding(horizontal = 4.dp))
                }
            }
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(AppColors.error.copy(alpha = 0.08f)).padding(18.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Outlined.WarningAmber, null, tint = AppColors.error)
                    Text(L("important"), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, color = AppColors.error)
                }
                listOf("writeSeedPhraseInOrder", "storeItSafely", "neverShareIt", "ifYouLoseIt", "accessFromSettings").forEach { key ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("•", style = MaterialTheme.typography.bodyMedium)
                        Text(L(key), style = MaterialTheme.typography.bodyMedium, color = AppColors.textPrimary)
                    }
                }
            }
        }
    }
    pendingCopy?.let { item ->
        AlertDialog(
            onDismissRequest = { pendingCopy = null },
            title = { Text(L("warning")) },
            text = { Text(L("copyKeyWarning")) },
            confirmButton = {
                Box(Modifier.testTag("copy-warning-confirm")) {
                    TextAction(L("copy"), {
                        pendingCopy = null
                        SecureClipboard.copy(item.value)
                        haptics.success()
                        ToastCenter.show(L("copiedToClipboardWithType", "type" to item.label), ToastStyle.SUCCESS)
                    })
                }
            },
            dismissButton = { TextAction(L("cancel"), { pendingCopy = null }) },
        )
    }
}

@Composable
private fun KeySectionTitle(title: String, tag: String, onCopy: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MaterialTheme.typography.labelLarge, color = AppColors.textSecondary, modifier = Modifier.weight(1f))
        FilledTonalButton(onClick = onCopy, modifier = Modifier.testTag(tag)) {
            Icon(Icons.Outlined.ContentCopy, null, Modifier.size(16.dp))
            Text("  " + L("copy"), fontWeight = FontWeight.SemiBold)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SeedGrid(words: List<String>, modifier: Modifier = Modifier, masked: Boolean = false, tiled: Boolean = true) {
    val fontScale = LocalDensity.current.fontScale
    val columns = when {
        fontScale >= 1.8f -> 1
        fontScale >= 1.3f -> 2
        else -> 3
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        words.chunked(columns).forEachIndexed { row, chunk ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                chunk.forEachIndexed { column, word ->
                    val index = row * columns + column
                    Row(
                        Modifier.weight(1f).then(
                            if (tiled) Modifier.clip(RoundedCornerShape(14.dp)).background(AppColors.overlayLight).padding(10.dp) else Modifier,
                        ),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("${index + 1}", style = MaterialTheme.typography.labelSmall, color = AppColors.textSecondary, modifier = Modifier.widthIn(min = 16.dp))
                        Text(
                            if (masked) "•".repeat(5) else word,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium,
                            fontFamily = if (tiled) null else FontFamily.Monospace,
                            color = if (masked) AppColors.textSecondary else AppColors.textPrimary,
                        )
                    }
                }
                repeat(columns - chunk.size) { Box(Modifier.weight(1f)) }
            }
        }
    }
}

class OnboardingProfileViewModel : ViewModel() {
    enum class Field { NAME, ABOUT, PICTURE, LUD16, WEBSITE }

    var name by mutableStateOf("")
    var about by mutableStateOf("")
    var picture by mutableStateOf("")
    var banner by mutableStateOf("")
        private set
    var lud16 by mutableStateOf("")
    var website by mutableStateOf("")
    var isUploadingPicture by mutableStateOf(false)
        private set
    var isUploadingBanner by mutableStateOf(false)
        private set
    var isSaving by mutableStateOf(false)
        private set
    var showErrors by mutableStateOf(false)
        private set
    var savedCount by mutableIntStateOf(0)
        private set
    var failureCount by mutableIntStateOf(0)
        private set

    val isBusy: Boolean get() = isSaving || isUploadingPicture || isUploadingBanner

    fun error(field: Field): String? = when (field) {
        Field.NAME -> if (name.trim().length > 50) L("usernameTooLong") else null
        Field.ABOUT -> if (about.trim().length > 300) L("bioTooLong") else null
        Field.PICTURE -> picture.trim().takeIf { it.isNotEmpty() }?.let { value ->
            if (Uri.parse(value).scheme?.startsWith("http") == true) null else L("pleaseEnterValidWebsiteUrl")
        }
        Field.LUD16 -> lud16.trim().takeIf { it.isNotEmpty() }?.let { value ->
            val parts = value.split("@")
            if (parts.size == 2 && parts[0].isNotEmpty() && parts[1].isNotEmpty()) null else L("invalidLightningAddress")
        }
        Field.WEBSITE -> website.trim().takeIf { it.isNotEmpty() }?.let { value ->
            if (value.contains(".") && !value.contains(" ")) null else L("pleaseEnterValidWebsiteUrl")
        }
    }

    val isValid: Boolean get() = Field.entries.all { error(it) == null }

    fun upload(uri: Uri, isPicture: Boolean) {
        if (isPicture) isUploadingPicture = true else isUploadingBanner = true
        viewModelScope.launch {
            try {
                val (data, mime) = withContext(Dispatchers.IO) { prepareImage(uri, if (isPicture) 1024 else 2048) }
                val url = OnboardingMediaUpload.upload(data, mime)
                if (url.isEmpty()) throw CoreError(L("authUploadNoUrl"))
                if (isPicture) picture = url else banner = url
                ToastCenter.show(L(if (isPicture) "profileImageUploadedSuccessfully" else "bannerUploadedSuccessfully"), ToastStyle.SUCCESS)
            } catch (error: Throwable) {
                ToastCenter.show(L("uploadFailed", "message" to coreErrorMessage(error)), ToastStyle.ERROR)
            } finally {
                if (isPicture) isUploadingPicture = false else isUploadingBanner = false
            }
        }
    }

    fun save(onDone: () -> Unit) {
        showErrors = true
        if (!isValid || isBusy) {
            failureCount += 1
            return
        }
        val me = Session.pubkey
        if (me == null || !Session.canSign) {
            ToastCenter.show(L("privateKeyNotFound"), ToastStyle.ERROR)
            return
        }
        if (listOf(name, about, picture, banner, lud16, website).all { it.isBlank() }) {
            onDone()
            return
        }
        isSaving = true
        val profile = Profile(
            pubkey = me,
            name = name.trim(),
            about = about.trim(),
            picture = picture.trim(),
            banner = banner.trim(),
            lud16 = lud16.trim(),
            website = website.trim(),
        )
        viewModelScope.launch {
            try {
                val event = signEvent(0u, profile.metadataJSON, emptyList())
                SyncService.publish(event)
                ProfileCache.set(profile)
                DataBus.profileChanged()
                savedCount += 1
                onDone()
            } catch (error: Throwable) {
                failureCount += 1
                ToastCenter.error(error)
            } finally {
                isSaving = false
            }
        }
    }

    private fun prepareImage(uri: Uri, maxPixel: Int): Pair<ByteArray, String> {
        val resolver = App.context.contentResolver
        val type = resolver.getType(uri)
        val raw = resolver.openInputStream(uri)?.use { it.readBytes() } ?: throw CoreError(L("mediaUploadFailed"))
        if (type == "image/gif") return raw to "image/gif"
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(raw, 0, raw.size, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxPixel) sample *= 2
        val decoded = BitmapFactory.decodeByteArray(raw, 0, raw.size, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: return raw to (type ?: "image/jpeg")
        val longest = maxOf(decoded.width, decoded.height)
        val scaled = if (longest > maxPixel) {
            val ratio = maxPixel.toFloat() / longest
            Bitmap.createScaledBitmap(decoded, (decoded.width * ratio).toInt().coerceAtLeast(1), (decoded.height * ratio).toInt().coerceAtLeast(1), true)
        } else decoded
        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, 85, out)
        return out.toByteArray() to "image/jpeg"
    }
}

private object OnboardingMediaUpload {
    private val http by lazy {
        OkHttpClient.Builder().connectTimeout(30, TimeUnit.SECONDS).writeTimeout(120, TimeUnit.SECONDS).readTimeout(120, TimeUnit.SECONDS).callTimeout(600, TimeUnit.SECONDS).build()
    }

    suspend fun upload(data: ByteArray, mimeType: String): String = withContext(Dispatchers.IO) {
        Session.requireSigner()
        val hash = sha256Hash(data)
        val auth = signBlossomAuthEvent("Upload $hash", hash, TimeFormat.now + 600)
        val token = android.util.Base64.encodeToString(auth.toByteArray(), android.util.Base64.NO_WRAP)
        val base = RelayConfig.blossomServer.trimEnd('/')
        val request = Request.Builder()
            .url("$base/upload")
            .put(data.toRequestBody(mimeType.toMediaTypeOrNull()))
            .header("Authorization", "Nostr $token")
            .header("Content-Type", mimeType)
            .build()
        http.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                val reason = response.header("X-Reason") ?: body.take(200)
                throw CoreError("${L("mediaUploadFailed")} (${response.code}) $reason".trim())
            }
            val json = Json.obj(body)
            val sha = json?.str("sha256") ?: hash
            json?.str("url") ?: if (sha.isEmpty()) throw CoreError(L("mediaUploadFailed")) else "$base/$sha"
        }
    }
}

@Composable
fun OnboardingProfileScreen(onBack: () -> Unit, onDone: () -> Unit) {
    val model: OnboardingProfileViewModel = viewModel()
    val haptics = rememberHaptics()
    val pictureLauncher = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri?.let { model.upload(it, true) } }
    val bannerLauncher = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri?.let { model.upload(it, false) } }
    val imagesOnly = PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
    LaunchedEffect(model.savedCount) { if (model.savedCount > 0) haptics.success() }
    LaunchedEffect(model.failureCount) { if (model.failureCount > 0) haptics.error() }
    Scaffold(
        containerColor = AppColors.background,
        topBar = {
            OnboardingTopBar(2, onBack) {
                Box(Modifier.testTag("onboarding-profile-skip")) { TextAction(L("skip"), onDone, enabled = !model.isSaving) }
            }
        },
        bottomBar = {
            OnboardingBottom {
                PrimaryButton(
                    L("continueButton"),
                    { model.save(onDone) },
                    Modifier.fillMaxWidth().testTag("onboarding-profile-continue"),
                    enabled = !model.isUploadingPicture && !model.isUploadingBanner,
                    loading = model.isSaving,
                )
            }
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            AuthHeader(L("setUpProfile"), L("profileSetupSubtitle"), modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
            Column(Modifier.padding(horizontal = 16.dp).clip(RoundedCornerShape(22.dp)).background(MaterialTheme.colorScheme.surfaceContainerLow)) {
                Box(
                    Modifier.fillMaxWidth().aspectRatio(10f / 3.5f).background(AppColors.overlayLight)
                        .clickableRow(enabled = !model.isUploadingBanner) { bannerLauncher.launch(imagesOnly) }
                        .semantics { contentDescription = L("banner") }
                        .testTag("onboarding-banner-picker"),
                    contentAlignment = Alignment.Center,
                ) {
                    if (model.banner.isNotEmpty()) RemoteImage(model.banner, Modifier.fillMaxSize())
                    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.25f)))
                    if (model.isUploadingBanner) CircularProgressIndicator(color = Color.White) else CameraBadge(48)
                }
                Box(
                    Modifier.padding(start = 16.dp).offset(y = (-28).dp).size(92.dp).clip(CircleShape)
                        .background(MaterialTheme.colorScheme.surfaceContainerLow).padding(4.dp)
                        .clickableRow(enabled = !model.isUploadingPicture) { pictureLauncher.launch(imagesOnly) }
                        .semantics { contentDescription = L("profileImage") }
                        .testTag("onboarding-avatar-picker"),
                    contentAlignment = Alignment.Center,
                ) {
                    if (model.picture.isEmpty()) {
                        Box(Modifier.fillMaxSize().clip(CircleShape).background(AppColors.avatarPlaceholder))
                    } else {
                        AvatarView(model.picture, size = 84.dp)
                        Box(Modifier.fillMaxSize().clip(CircleShape).background(Color.Black.copy(alpha = 0.3f)))
                    }
                    if (model.isUploadingPicture) CircularProgressIndicator(Modifier.size(28.dp), color = Color.White) else CameraBadge(36)
                }
            }
            FieldGroup(L("profile")) {
                ProfileField(model, OnboardingProfileViewModel.Field.NAME, model.name, { model.name = it }, L("username"), "onboarding-name")
                ProfileField(model, OnboardingProfileViewModel.Field.ABOUT, model.about, { model.about = it }, L("bio"), "onboarding-about", singleLine = false)
            }
            FieldGroup(L("details")) {
                ProfileField(model, OnboardingProfileViewModel.Field.PICTURE, model.picture, { model.picture = it }, L("authPictureUrlOptional"), "onboarding-picture-url", KeyboardType.Uri)
                ProfileField(model, OnboardingProfileViewModel.Field.LUD16, model.lud16, { model.lud16 = it }, L("lightningAddressOptional"), "onboarding-lud16", KeyboardType.Email)
                ProfileField(model, OnboardingProfileViewModel.Field.WEBSITE, model.website, { model.website = it }, L("websiteOptional"), "onboarding-website", KeyboardType.Uri)
            }
        }
    }
}

@Composable
private fun CameraBadge(size: Int) {
    Box(
        Modifier.size(size.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surface.copy(alpha = 0.75f)),
        contentAlignment = Alignment.Center,
    ) { Icon(Icons.Outlined.CameraAlt, null, Modifier.size((size * 0.48).dp), tint = AppColors.textPrimary) }
}

@Composable
private fun FieldGroup(title: String, content: @Composable () -> Unit) {
    Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, style = MaterialTheme.typography.labelLarge, color = AppColors.textSecondary, modifier = Modifier.padding(horizontal = 4.dp))
        content()
    }
}

@Composable
private fun ProfileField(
    model: OnboardingProfileViewModel,
    field: OnboardingProfileViewModel.Field,
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    tag: String,
    keyboardType: KeyboardType = KeyboardType.Text,
    singleLine: Boolean = true,
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        AuthTextField(
            value = value,
            onValueChange = onChange,
            placeholder = placeholder,
            singleLine = singleLine,
            keyboardType = keyboardType,
            imeAction = if (singleLine) ImeAction.Next else ImeAction.Default,
            enabled = !model.isSaving,
            modifier = Modifier.testTag(tag),
        )
        val message = if (model.showErrors) model.error(field) else null
        AnimatedVisibility(message != null) {
            Text(message.orEmpty(), style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium, color = AppColors.error, modifier = Modifier.padding(horizontal = 4.dp))
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun OnboardingInterestsScreen(onBack: () -> Unit, onSkip: () -> Unit, onContinue: (Set<FollowInterest>) -> Unit) {
    var selection by remember { mutableStateOf<Set<FollowInterest>>(emptySet()) }
    val haptics = rememberHaptics()
    Scaffold(
        containerColor = AppColors.background,
        topBar = {
            OnboardingTopBar(3, onBack) {
                Box(Modifier.testTag("onboarding-interests-skip")) { TextAction(L("skip"), onSkip) }
            }
        },
        bottomBar = {
            OnboardingBottom {
                PrimaryButton(
                    L("continueButton"),
                    {
                        FollowInterest.saved = selection
                        onContinue(selection)
                    },
                    Modifier.fillMaxWidth().testTag("onboarding-interests-continue"),
                    enabled = selection.isNotEmpty(),
                )
            }
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 8.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(28.dp),
        ) {
            AuthHeader(L("authInterestsTitle"), L("authInterestsSubtitle"))
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.testTag("onboarding-interests"),
            ) {
                FollowInterest.entries.forEach { interest ->
                    InterestChip(interest, interest in selection) {
                        haptics.selection()
                        selection = if (interest in selection) selection - interest else selection + interest
                    }
                }
            }
        }
    }
}

@Composable
fun InterestChip(interest: FollowInterest, isSelected: Boolean, compact: Boolean = false, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        shape = CircleShape,
        color = if (isSelected) AppColors.textPrimary else AppColors.tile,
        contentColor = if (isSelected) AppColors.background else AppColors.textPrimary,
        modifier = modifier.testTag("interest-${interest.raw}"),
    ) {
        Row(
            Modifier.padding(horizontal = if (compact) 12.dp else 16.dp, vertical = if (compact) 7.dp else 11.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(if (isSelected) Icons.Filled.Check else interest.icon, null, Modifier.size(if (compact) 16.dp else 18.dp))
            Text(
                interest.title,
                style = if (compact) MaterialTheme.typography.labelLarge else MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

