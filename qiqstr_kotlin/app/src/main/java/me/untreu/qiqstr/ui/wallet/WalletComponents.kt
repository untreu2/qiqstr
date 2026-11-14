package me.untreu.qiqstr.ui.wallet

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.CallMade
import androidx.compose.material.icons.automirrored.outlined.CallReceived
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.PrimaryButton

@Composable
fun FormSection(
    modifier: Modifier = Modifier,
    header: String? = null,
    footer: (@Composable ColumnScope.() -> Unit)? = null,
    plain: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        if (header != null) {
            Text(
                header,
                style = MaterialTheme.typography.labelLarge,
                color = AppColors.textSecondary,
                modifier = Modifier.padding(start = 16.dp, bottom = 8.dp),
            )
        }
        if (plain) {
            Column(content = content)
        } else {
            Surface(shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh) {
                Column(Modifier.fillMaxWidth(), content = content)
            }
        }
        if (footer != null) {
            Column(
                Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                androidx.compose.runtime.CompositionLocalProvider(
                    androidx.compose.material3.LocalTextStyle provides MaterialTheme.typography.bodySmall,
                    androidx.compose.material3.LocalContentColor provides AppColors.textSecondary,
                ) { footer() }
            }
        }
    }
}

@Composable
fun FooterText(text: String, color: Color = AppColors.textSecondary, modifier: Modifier = Modifier) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = color, modifier = modifier)
}

@Composable
fun NoticeLabel(text: String, icon: ImageVector, color: Color, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(icon, null, Modifier.size(16.dp), tint = color)
        Text(text, style = MaterialTheme.typography.bodySmall, color = color)
    }
}

@Composable
fun LabeledRow(label: String, modifier: Modifier = Modifier, value: @Composable () -> Unit) {
    Row(
        modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge, color = AppColors.textPrimary)
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) { value() }
    }
}

@Composable
fun LabeledValue(label: String, value: String, modifier: Modifier = Modifier, monospace: Boolean = false) {
    LabeledRow(label, modifier) {
        Text(
            value,
            style = if (monospace) MaterialTheme.typography.bodySmall.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace) else MaterialTheme.typography.bodyLarge,
            color = AppColors.textSecondary,
            textAlign = TextAlign.End,
            maxLines = 3,
        )
    }
}

@Composable
fun SatsAmountField(value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier, placeholder: String = L("walletSats")) {
    TextField(
        value = value,
        onValueChange = { onValueChange(it.filter(Char::isDigit)) },
        placeholder = { Text(placeholder, textAlign = TextAlign.End, modifier = Modifier.fillMaxWidth()) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        textStyle = MaterialTheme.typography.bodyLarge.copy(textAlign = TextAlign.End),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Color.Transparent,
            unfocusedContainerColor = Color.Transparent,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
        ),
        modifier = modifier.widthIn(min = 120.dp),
    )
}

@Composable
fun FormTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    minLines: Int = 1,
    maxLines: Int = 1,
    monospace: Boolean = false,
) {
    TextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(placeholder) },
        singleLine = maxLines == 1,
        minLines = minLines,
        maxLines = maxLines,
        keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, keyboardType = if (monospace) KeyboardType.Uri else KeyboardType.Text),
        textStyle = if (monospace) MaterialTheme.typography.bodyMedium.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace) else MaterialTheme.typography.bodyLarge,
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Color.Transparent,
            unfocusedContainerColor = Color.Transparent,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
        ),
        modifier = modifier.fillMaxWidth(),
    )
}

@Composable
fun TransactionIcon(isIncoming: Boolean, size: Dp = 34.dp) {
    val color = if (isIncoming) AppColors.success else AppColors.textPrimary
    Box(Modifier.size(size).background(color.copy(alpha = 0.12f), CircleShape), contentAlignment = Alignment.Center) {
        Icon(
            if (isIncoming) Icons.AutoMirrored.Outlined.CallReceived else Icons.AutoMirrored.Outlined.CallMade,
            null,
            Modifier.size(size * 0.55f),
            tint = color,
        )
    }
}

@Composable
fun SatsText(amount: Long, modifier: Modifier = Modifier, color: Color = AppColors.textPrimary) {
    Text("${Sats.format(amount)} ${L("walletSats")}", modifier, color = color, style = MaterialTheme.typography.bodyLarge)
}

@Composable
fun Countdown(expiresAt: Long, modifier: Modifier = Modifier) {
    var now by remember { mutableLongStateOf(TimeFormat.now) }
    LaunchedEffect(expiresAt) {
        while (now < expiresAt) {
            delay(1000)
            now = TimeFormat.now
        }
    }
    Text(WalletFormat.countdown(expiresAt - now), modifier, style = MaterialTheme.typography.bodyLarge, color = AppColors.textSecondary)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SheetTopBar(
    title: String,
    onCancel: (() -> Unit)?,
    cancelEnabled: Boolean = true,
    cancelTag: String? = null,
    action: @Composable () -> Unit = {},
) {
    CenterAlignedTopAppBar(
        title = { Text(title, maxLines = 1, style = MaterialTheme.typography.titleMedium) },
        navigationIcon = {
            if (onCancel != null) {
                IconButton(onClick = onCancel, enabled = cancelEnabled, modifier = cancelTag?.let { Modifier.testTag(it) } ?: Modifier) {
                    Icon(Icons.Outlined.Close, L("cancel"))
                }
            }
        },
        actions = { action() },
        colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = Color.Transparent),
        windowInsets = androidx.compose.foundation.layout.WindowInsets(0),
    )
}

@Composable
fun PaymentSuccessView(title: String, amount: Long, fee: Long?, modifier: Modifier = Modifier, onDone: () -> Unit) {
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { appeared = true }
    val progress by animateFloatAsState(if (appeared) 1f else 0f, tween(250), label = "success")
    Column(
        modifier.fillMaxWidth().padding(20.dp).testTag("payment-success"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Spacer(Modifier.size(24.dp))
        Icon(
            Icons.Filled.CheckCircle,
            null,
            Modifier.size(72.dp).scale(0.8f + 0.2f * progress).alpha(progress),
            tint = AppColors.success,
        )
        Spacer(Modifier.size(4.dp))
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Text("${Sats.format(amount)} ${L("walletSats")}", style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.SemiBold)
        if (fee != null && fee > 0) {
            Text("${L("fee")}: ${Sats.format(fee)} ${L("walletSats")}", style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
        }
        Spacer(Modifier.size(24.dp))
        PrimaryButton(L("done"), onDone, Modifier.fillMaxWidth().testTag("payment-success-done"))
    }
}

@Composable
fun SectionDivider() {
    androidx.compose.material3.HorizontalDivider(Modifier.padding(start = 16.dp), color = AppColors.divider)
}

private class ScopedViewModelOwner : androidx.lifecycle.ViewModelStoreOwner {
    override val viewModelStore = androidx.lifecycle.ViewModelStore()
}

@Composable
fun ScopedViewModels(content: @Composable () -> Unit) {
    val owner = remember { ScopedViewModelOwner() }
    androidx.compose.runtime.DisposableEffect(owner) { onDispose { owner.viewModelStore.clear() } }
    androidx.compose.runtime.CompositionLocalProvider(androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner provides owner, content = content)
}
