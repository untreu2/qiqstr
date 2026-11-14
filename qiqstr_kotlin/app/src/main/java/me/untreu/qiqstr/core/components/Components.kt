package me.untreu.qiqstr.core.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarScrollBehavior
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.KeyboardOptions
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import kotlinx.coroutines.delay
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.AppFont
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache

@Composable
fun RemoteImage(
    url: String?,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,
    contentDescription: String? = null,
) {
    if (url.isNullOrBlank()) {
        Box(modifier.background(AppColors.tile))
        return
    }
    AsyncImage(
        model = ImageRequest.Builder(LocalContext.current).data(url).crossfade(true).build(),
        contentDescription = contentDescription,
        contentScale = contentScale,
        modifier = modifier.background(AppColors.tile),
    )
}

@Composable
fun AvatarView(url: String?, size: Dp = 40.dp, modifier: Modifier = Modifier) {
    Box(modifier.size(size).clip(CircleShape).background(AppColors.avatarPlaceholder)) {
        if (!url.isNullOrBlank()) RemoteImage(url, Modifier.fillMaxSize())
    }
}

@Composable
fun ProfileAvatar(pubkey: String, size: Dp = 40.dp, modifier: Modifier = Modifier, fallbackUrl: String? = null) {
    LaunchedEffect(pubkey) { if (ProfileCache.profile(pubkey) == null) ProfileCache.load(listOf(pubkey)) }
    val picture = ProfileCache.profiles[pubkey]?.picture?.ifEmpty { null } ?: fallbackUrl
    AvatarView(picture, size, modifier)
}

@Composable
fun PrimaryButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    loading: Boolean = false,
    icon: ImageVector? = null,
) {
    Button(
        onClick = onClick,
        enabled = enabled && !loading,
        modifier = modifier.heightIn(min = 52.dp),
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
    ) {
        if (loading) {
            CircularProgressIndicator(Modifier.size(20.dp), color = AppColors.background, strokeWidth = 2.dp)
        } else {
            if (icon != null) { Icon(icon, null, Modifier.size(18.dp)); Spacer(Modifier.size(8.dp)) }
            Text(title, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
fun SecondaryButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, icon: ImageVector? = null) {
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.heightIn(min = 52.dp),
        shape = CircleShape,
        colors = ButtonDefaults.outlinedButtonColors(contentColor = AppColors.textPrimary),
    ) {
        if (icon != null) { Icon(icon, null, Modifier.size(18.dp)); Spacer(Modifier.size(8.dp)) }
        Text(title, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun PillButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, filled: Boolean = true, enabled: Boolean = true, icon: ImageVector? = null) {
    Surface(
        onClick = onClick,
        enabled = enabled,
        shape = CircleShape,
        color = if (filled) AppColors.textPrimary else AppColors.tile,
        contentColor = if (filled) AppColors.background else AppColors.textPrimary,
        modifier = modifier,
    ) {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (icon != null) { Icon(icon, null, Modifier.size(16.dp)); Spacer(Modifier.size(6.dp)) }
            Text(title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
fun IconTile(icon: ImageVector, modifier: Modifier = Modifier, size: Dp = 36.dp, tint: Color = AppColors.textPrimary, background: Color = AppColors.tile) {
    Box(modifier.size(size).clip(RoundedCornerShape(size * 0.28f)).background(background), contentAlignment = Alignment.Center) {
        Icon(icon, null, Modifier.size(size * 0.55f), tint = tint)
    }
}

@Composable
fun LoadingView(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = AppColors.textPrimary) }
}

@Composable
fun EmptyStateView(
    icon: ImageVector = Icons.Outlined.ErrorOutline,
    title: String,
    message: String? = null,
    actionTitle: String? = null,
    modifier: Modifier = Modifier,
    action: (() -> Unit)? = null,
) {
    Column(
        modifier.fillMaxWidth().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, null, Modifier.size(44.dp), tint = AppColors.textSecondary)
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        if (message != null) Text(message, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, textAlign = TextAlign.Center)
        if (actionTitle != null && action != null) PillButton(actionTitle, action)
    }
}

@Composable
fun BrandWordmark(size: Int = 34, modifier: Modifier = Modifier) {
    Text("qiqstr", style = AppFont.brand(size.sp), color = AppColors.textPrimary, modifier = modifier)
}

@Composable
fun QiqTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    singleLine: Boolean = true,
    secure: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text,
    minLines: Int = 1,
) {
    TextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(placeholder) },
        singleLine = singleLine,
        minLines = minLines,
        visualTransformation = if (secure) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = if (secure) KeyboardType.Password else keyboardType),
        shape = RoundedCornerShape(14.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = AppColors.inputFill,
            unfocusedContainerColor = AppColors.inputFill,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent,
        ),
        modifier = modifier.fillMaxWidth(),
    )
}

@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier, trailing: (@Composable RowScope.() -> Unit)? = null) {
    Row(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
        trailing?.invoke(this)
    }
}

@Composable
fun BackTopBar(
    title: String,
    actions: @Composable RowScope.() -> Unit = {},
    scrollBehavior: TopAppBarScrollBehavior? = null,
    onBack: () -> Unit = { Router.pop() },
) {
    TopAppBar(
        title = { Text(title, maxLines = 1) },
        navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } },
        actions = actions,
        scrollBehavior = scrollBehavior,
    )
}

@Composable
fun RelativeTimeText(timestamp: Long, prefix: String = "", modifier: Modifier = Modifier, color: Color = AppColors.textSecondary) {
    var tick by remember { mutableLongStateOf(0L) }
    LaunchedEffect(timestamp) { while (true) { delay(30_000); tick++ } }
    Text(prefix + TimeFormat.relative(timestamp).also { tick }, style = MaterialTheme.typography.bodySmall, color = color, modifier = modifier)
}

@Composable
fun ToastHost(modifier: Modifier = Modifier) {
    val toast = ToastCenter.current
    AnimatedVisibility(
        visible = toast != null,
        enter = fadeIn() + slideInVertically { -it },
        exit = fadeOut() + slideOutVertically { -it },
        modifier = modifier.statusBarsPadding().padding(top = 8.dp),
    ) {
        val shown = toast ?: return@AnimatedVisibility
        Surface(
            shape = CircleShape,
            color = when (shown.style) {
                ToastStyle.ERROR -> AppColors.error
                else -> AppColors.textPrimary
            },
            contentColor = AppColors.background,
            shadowElevation = 6.dp,
            modifier = Modifier.padding(horizontal = 24.dp).clickable { ToastCenter.dismiss() },
        ) {
            Text(shown.message, Modifier.padding(horizontal = 18.dp, vertical = 12.dp), style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
        }
    }
}

@Composable
fun TextAction(title: String, onClick: () -> Unit, enabled: Boolean = true, color: Color = AppColors.textPrimary) {
    TextButton(onClick = onClick, enabled = enabled, contentPadding = PaddingValues(horizontal = 12.dp)) {
        Text(title, color = if (enabled) color else AppColors.textTertiary, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun Spacer(height: Dp) = androidx.compose.foundation.layout.Spacer(Modifier.height(height))

@Composable
fun PlaceholderScreen(title: String, showBack: Boolean = true) {
    Column(Modifier.fillMaxSize()) {
        if (showBack) BackTopBar(title) else TopAppBar(title = { Text(title) })
        EmptyStateView(title = title, message = L("loading"))
    }
}
