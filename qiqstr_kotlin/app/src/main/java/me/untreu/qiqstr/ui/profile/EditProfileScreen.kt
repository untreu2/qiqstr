package me.untreu.qiqstr.ui.profile

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CameraAlt
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.HideImage
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.PersonRemove
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
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
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.AvatarView
import me.untreu.qiqstr.core.components.LoadingView
import me.untreu.qiqstr.core.components.RemoteImage
import me.untreu.qiqstr.core.components.TextAction

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditProfileScreen() {
    val model = viewModel { EditProfileViewModel() }
    val focus = LocalFocusManager.current
    var confirmDiscard by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { model.load() }
    BackHandler(enabled = model.isDirty) { confirmDiscard = true }
    val pictureLauncher = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) model.upload(uri, MediaTarget.PICTURE)
    }
    val bannerLauncher = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) model.upload(uri, MediaTarget.BANNER)
    }
    val imageOnly = PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
    val scroll = TopAppBarDefaults.pinnedScrollBehavior()
    val errors = model.errors
    val enabled = !model.isLoading

    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection).testTag("edit-profile-form"),
        containerColor = AppColors.background,
        topBar = {
            TopAppBar(
                title = { Text(L("editProfile")) },
                navigationIcon = {
                    IconButton(
                        onClick = { if (model.isDirty) confirmDiscard = true else Router.pop() },
                        modifier = Modifier.testTag("edit-profile-cancel"),
                    ) { Icon(Icons.Outlined.Close, L("cancel")) }
                },
                actions = {
                    if (model.isSaving) {
                        CircularProgressIndicator(Modifier.padding(horizontal = 16.dp).size(22.dp), strokeWidth = 2.dp, color = AppColors.textPrimary)
                    } else {
                        Button(
                            onClick = { focus.clearFocus(); model.save { Router.pop() } },
                            enabled = model.canSave,
                            colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
                            modifier = Modifier.padding(end = 8.dp).testTag("edit-profile-save"),
                        ) { Text(L("save"), fontWeight = FontWeight.SemiBold) }
                    }
                },
                scrollBehavior = scroll,
            )
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().padding(horizontal = 16.dp).padding(bottom = 32.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                MediaHeader(model, enabled, onPickBanner = { bannerLauncher.launch(imageOnly) }, onPickPicture = { pictureLauncher.launch(imageOnly) })
                Section(L("profileImageLinks"))
                Field(L("profileImage"), model.draft.picture, { model.draft = model.draft.copy(picture = it) }, errors[ProfileField.PICTURE], "edit-picture-url", enabled, "https://", KeyboardType.Uri)
                Field(L("banner"), model.draft.banner, { model.draft = model.draft.copy(banner = it) }, errors[ProfileField.BANNER], "edit-banner-url", enabled, "https://", KeyboardType.Uri)
                Section(L("profile"))
                Field(L("profileDisplayName"), model.draft.displayName, { model.draft = model.draft.copy(displayName = it) }, errors[ProfileField.DISPLAY_NAME], "edit-display-name", enabled)
                Field(L("username"), model.draft.name, { model.draft = model.draft.copy(name = it) }, errors[ProfileField.NAME], "edit-name", enabled)
                OutlinedTextField(
                    value = model.draft.about,
                    onValueChange = { model.draft = model.draft.copy(about = it) },
                    label = { Text(L("bio")) },
                    placeholder = { Text(L("profileAboutPlaceholder")) },
                    isError = errors[ProfileField.ABOUT] != null,
                    supportingText = errors[ProfileField.ABOUT]?.let { { Text(it) } },
                    minLines = 3,
                    maxLines = 10,
                    enabled = enabled,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                    modifier = Modifier.fillMaxWidth().testTag("edit-about"),
                )
                Section(L("profileDetails"))
                Field(L("nip05"), model.draft.nip05, { model.draft = model.draft.copy(nip05 = it) }, errors[ProfileField.NIP05], "edit-nip05", enabled, "name@example.com", KeyboardType.Email)
                Field(L("lightningAddress"), model.draft.lud16, { model.draft = model.draft.copy(lud16 = it) }, errors[ProfileField.LUD16], "edit-lud16", enabled, "name@wallet.com", KeyboardType.Email)
                Field(L("website"), model.draft.website, { model.draft = model.draft.copy(website = it) }, errors[ProfileField.WEBSITE], "edit-website", enabled, "example.com", KeyboardType.Uri)
                Field(L("profileLocation"), model.draft.location, { model.draft = model.draft.copy(location = it) }, errors[ProfileField.LOCATION], "edit-location", enabled, capitalize = true)
            }
            if (model.isLoading) LoadingView()
        }
    }

    if (confirmDiscard) {
        AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text(L("profileDiscardChanges")) },
            confirmButton = {
                Box(Modifier.testTag("edit-profile-discard")) {
                    TextAction(L("profileDiscard"), { confirmDiscard = false; Router.pop() }, color = AppColors.error)
                }
            },
            dismissButton = { TextAction(L("profileKeepEditing"), { confirmDiscard = false }) },
        )
    }
}

@Composable
private fun MediaHeader(model: EditProfileViewModel, enabled: Boolean, onPickBanner: () -> Unit, onPickPicture: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val canPick = enabled && !model.isUploading
    val bannerLabel = L("banner")
    val pictureLabel = L("profileImage")
    Column(Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 4.dp)) {
        Box(
            Modifier.fillMaxWidth().height(140.dp).clip(RoundedCornerShape(24.dp)).background(AppColors.tile)
                .clickable(enabled = canPick, onClick = onPickBanner)
                .semantics { contentDescription = bannerLabel }
                .testTag("edit-banner-picker"),
            contentAlignment = Alignment.Center,
        ) {
            if (model.draft.banner.isNotEmpty()) RemoteImage(model.draft.banner, Modifier.fillMaxSize())
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.25f)))
            MediaBadge(model.uploadingBanner)
        }
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 14.dp).layout { measurable, constraints ->
                val placeable = measurable.measure(constraints)
                val lift = 48.dp.roundToPx()
                layout(placeable.width, (placeable.height - lift).coerceAtLeast(0)) { placeable.place(0, -lift) }
            },
            verticalAlignment = Alignment.Bottom,
        ) {
            Box(
                Modifier.background(AppColors.background, CircleShape).padding(4.dp).clip(CircleShape)
                    .clickable(enabled = canPick, onClick = onPickPicture)
                    .semantics { contentDescription = pictureLabel }
                    .testTag("edit-picture-picker"),
                contentAlignment = Alignment.Center,
            ) {
                AvatarView(model.draft.picture.ifEmpty { null }, 88.dp)
                Box(Modifier.size(88.dp).background(Color.Black.copy(alpha = 0.25f), CircleShape))
                MediaBadge(model.uploadingPicture)
            }
            Spacer(Modifier.weight(1f))
            if (model.draft.picture.isNotEmpty() || model.draft.banner.isNotEmpty()) {
                Box(Modifier.padding(bottom = 8.dp)) {
                    FilledTonalIconButton(onClick = { menu = true }, modifier = Modifier.testTag("edit-media-menu")) {
                        Icon(Icons.Outlined.MoreHoriz, null)
                    }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        if (model.draft.picture.isNotEmpty()) {
                            DropdownMenuItem(
                                text = { Text(L("profileRemoveImage"), color = AppColors.error) },
                                leadingIcon = { Icon(Icons.Outlined.PersonRemove, null, tint = AppColors.error) },
                                onClick = { menu = false; model.draft = model.draft.copy(picture = "") },
                            )
                        }
                        if (model.draft.banner.isNotEmpty()) {
                            DropdownMenuItem(
                                text = { Text(L("profileRemoveBanner"), color = AppColors.error) },
                                leadingIcon = { Icon(Icons.Outlined.HideImage, null, tint = AppColors.error) },
                                onClick = { menu = false; model.draft = model.draft.copy(banner = "") },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MediaBadge(uploading: Boolean) {
    Surface(shape = CircleShape, color = AppColors.background.copy(alpha = 0.7f), contentColor = AppColors.textPrimary, modifier = Modifier.size(40.dp)) {
        Box(contentAlignment = Alignment.Center) {
            if (uploading) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = AppColors.textPrimary)
            else Icon(Icons.Outlined.CameraAlt, null, Modifier.size(20.dp))
        }
    }
}

@Composable
private fun Section(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
        color = AppColors.textSecondary,
        modifier = Modifier.padding(top = 8.dp),
    )
}

@Composable
private fun Field(
    label: String,
    value: String,
    onChange: (String) -> Unit,
    error: String?,
    tag: String,
    enabled: Boolean,
    prompt: String? = null,
    keyboard: KeyboardType = KeyboardType.Text,
    capitalize: Boolean = false,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        placeholder = { Text(prompt ?: label) },
        singleLine = true,
        isError = error != null,
        supportingText = error?.let { { Text(it) } },
        enabled = enabled,
        keyboardOptions = KeyboardOptions(
            keyboardType = keyboard,
            capitalization = if (capitalize) KeyboardCapitalization.Words else KeyboardCapitalization.None,
            autoCorrectEnabled = capitalize,
            imeAction = ImeAction.Next,
        ),
        modifier = Modifier.fillMaxWidth().testTag(tag),
    )
}
