package me.untreu.qiqstr.ui.settings

import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.IconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.ui.auth.clickableRow

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScaffold(
    title: String,
    tag: String? = null,
    actions: @Composable () -> Unit = {},
    isRefreshing: Boolean = false,
    onRefresh: (() -> Unit)? = null,
    content: LazyListScope.() -> Unit,
) {
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    Scaffold(
        containerColor = AppColors.background,
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } },
                actions = { actions() },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.largeTopAppBarColors(containerColor = AppColors.background, scrolledContainerColor = AppColors.background),
            )
        },
    ) { padding ->
        val list = @Composable {
            LazyColumn(
                Modifier.fillMaxSize().then(if (tag != null) Modifier.testTag(tag) else Modifier),
                contentPadding = PaddingValues(top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 32.dp),
                content = content,
            )
        }
        if (onRefresh != null) {
            PullToRefreshBox(isRefreshing = isRefreshing, onRefresh = onRefresh, modifier = Modifier.fillMaxSize()) { list() }
        } else {
            list()
        }
    }
}

fun LazyListScope.settingsSection(
    key: String,
    header: String? = null,
    footer: (@Composable () -> Unit)? = null,
    content: @Composable () -> Unit,
) = sectionItem(key, header, footer, content)

private fun LazyListScope.sectionItem(
    key: String,
    header: String?,
    footer: (@Composable () -> Unit)?,
    content: @Composable () -> Unit,
) {
    item(key) {
        Column(Modifier.padding(top = 8.dp)) {
            if (header != null) {
                Text(
                    header,
                    style = MaterialTheme.typography.labelLarge,
                    color = AppColors.textSecondary,
                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 4.dp),
                )
            }
            content()
            if (footer != null) {
                Box(Modifier.padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 8.dp)) {
                    androidx.compose.material3.ProvideTextStyle(MaterialTheme.typography.bodySmall.copy(color = AppColors.textSecondary)) { footer() }
                }
            }
            HorizontalDivider(Modifier.padding(top = 8.dp), color = AppColors.divider)
        }
    }
}

fun LazyListScope.settingsSection(key: String, header: String? = null, footer: String?, content: @Composable () -> Unit) =
    sectionItem(key, header, footer?.let { text -> @Composable { Text(text) } }, content)

@Composable
fun SettingsIcon(icon: ImageVector, tint: Color = AppColors.textPrimary, fill: Color? = null, size: Dp = 32.dp) {
    if (fill != null) {
        Box(
            Modifier.size(size).clip(RoundedCornerShape(size * 0.26f))
                .background(Brush.verticalGradient(listOf(fill.copy(alpha = 0.85f), fill))),
            contentAlignment = Alignment.Center,
        ) { Icon(icon, null, Modifier.size(size * 0.58f), tint = Color.White) }
    } else {
        Box(Modifier.size(size), contentAlignment = Alignment.Center) { Icon(icon, null, Modifier.size(size * 0.72f), tint = tint) }
    }
}

@Composable
fun SettingsRow(
    title: String,
    icon: ImageVector? = null,
    modifier: Modifier = Modifier,
    tint: Color = AppColors.textPrimary,
    fill: Color? = null,
    value: String? = null,
    subtitle: String? = null,
    enabled: Boolean = true,
    trailing: (@Composable () -> Unit)? = null,
    onClick: (() -> Unit)? = null,
) {
    ListItem(
        headlineContent = { Text(title, color = if (enabled) tint else AppColors.textTertiary) },
        supportingContent = subtitle?.let { { Text(it) } },
        leadingContent = icon?.let { { SettingsIcon(it, tint, fill) } },
        trailingContent = when {
            trailing != null -> trailing
            value != null -> ({ Text(value, color = AppColors.textSecondary, maxLines = 1) })
            else -> null
        },
        colors = ListItemDefaults.colors(containerColor = AppColors.background),
        modifier = modifier.then(if (onClick != null) Modifier.clickableRow(enabled = enabled, onClick = onClick) else Modifier),
    )
}

@Composable
fun SettingsToggle(title: String, icon: ImageVector?, checked: Boolean, modifier: Modifier = Modifier, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    SettingsRow(
        title = title,
        icon = icon,
        modifier = modifier,
        enabled = enabled,
        trailing = {
            Switch(
                checked = checked,
                onCheckedChange = onChange,
                enabled = enabled,
                colors = SwitchDefaults.colors(checkedTrackColor = AppColors.switchActive, checkedThumbColor = Color.White, checkedBorderColor = AppColors.switchActive),
            )
        },
        onClick = { onChange(!checked) },
    )
}

@Composable
fun SettingsCenteredAction(title: String, color: Color, modifier: Modifier = Modifier, enabled: Boolean = true, loading: Boolean = false, onClick: () -> Unit) {
    Row(
        modifier.fillMaxWidth().clickableRow(enabled = enabled && !loading, onClick = onClick).padding(vertical = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = if (enabled) color else AppColors.textTertiary, style = MaterialTheme.typography.bodyLarge)
        if (loading) androidx.compose.material3.CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = color)
    }
}

object SettingsByteFormat {
    fun string(bytes: Long): String {
        if (bytes < 1024) return "$bytes bytes"
        val units = listOf("KB", "MB", "GB", "TB")
        var value = bytes.toDouble() / 1024
        var index = 0
        while (value >= 1024 && index < units.lastIndex) {
            value /= 1024
            index++
        }
        val formatted = if (value >= 100) "%.0f".format(value) else "%.1f".format(value)
        return "$formatted ${units[index]}"
    }
}

object SettingsShare {
    fun text(text: String, subject: String? = null) {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
            subject?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
        }
        runCatching { App.context.startActivity(Intent.createChooser(send, L("share")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }
}

@Composable
fun SettingsQRCode(content: String, size: Dp = 220.dp, modifier: Modifier = Modifier) {
    val bitmap = remember(content) {
        runCatching {
            val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, 512, 512, mapOf(EncodeHintType.MARGIN to 1))
            val pixels = IntArray(matrix.width * matrix.height) { index ->
                if (matrix.get(index % matrix.width, index / matrix.width)) android.graphics.Color.BLACK else android.graphics.Color.WHITE
            }
            Bitmap.createBitmap(pixels, matrix.width, matrix.height, Bitmap.Config.ARGB_8888).asImageBitmap()
        }.getOrNull()
    }
    Box(modifier.size(size).clip(RoundedCornerShape(16.dp)).background(Color.White).padding(10.dp), contentAlignment = Alignment.Center) {
        bitmap?.let { Image(it, L("keysBackupQRCode"), Modifier.fillMaxSize()) }
    }
}
