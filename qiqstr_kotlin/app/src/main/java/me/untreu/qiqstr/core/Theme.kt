package me.untreu.qiqstr.core

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import me.untreu.qiqstr.R

val LocalDarkTheme = staticCompositionLocalOf { false }

private fun pick(dark: Boolean, light: Color, darkColor: Color) = if (dark) darkColor else light

object AppColors {
    private val dark: Boolean @Composable get() = LocalDarkTheme.current
    val accent: Color @Composable get() = pick(dark, Color(0xFFFF6A00), Color(0xFFFF8A3D))
    val background: Color @Composable get() = pick(dark, Color.White, Color(0xFF0A0A0A))
    val surface: Color @Composable get() = pick(dark, Color.White, Color(0xFF0F0F0F))
    val textPrimary: Color @Composable get() = pick(dark, Color.Black, Color.White)
    val textSecondary: Color @Composable get() = pick(dark, Color.Black.copy(alpha = 0.54f), Color(0xFFE0E0E0))
    val textTertiary: Color @Composable get() = pick(dark, Color.Black.copy(alpha = 0.38f), Color.White.copy(alpha = 0.45f))
    val error: Color @Composable get() = pick(dark, Color(0xFFD62C2C), Color(0xFFFF6B6B))
    val success: Color @Composable get() = pick(dark, Color(0xFF1E7B3C), Color(0xFF2E9E4F))
    val warning: Color @Composable get() = pick(dark, Color(0xFF9C6500), Color(0xFFFFA726))
    val border: Color @Composable get() = pick(dark, Color.Black.copy(alpha = 0.12f), Color(0xFF333333))
    val divider: Color @Composable get() = pick(dark, Color.Black.copy(alpha = 0.12f), Color(0xFF2A2A2A))
    val overlayLight: Color @Composable get() = pick(dark, Color.Black.copy(alpha = 0.12f), Color.White.copy(alpha = 0.1f))
    val inputFill: Color @Composable get() = pick(dark, Color.Black.copy(alpha = 0.06f), Color(0xFF141414))
    val avatarPlaceholder: Color @Composable get() = pick(dark, Color.Black.copy(alpha = 0.26f), Color(0xFF666666))
    val reaction: Color @Composable get() = pick(dark, Color(0xFFD62C2C), Color(0xFFFF6B6B))
    val reply: Color @Composable get() = pick(dark, Color(0xFF1971C2), Color(0xFF74C0FC))
    val repost: Color @Composable get() = pick(dark, Color(0xFF1E7B3C), Color(0xFF2E9E4F))
    val zap: Color @Composable get() = pick(dark, Color(0xFFA16A00), Color(0xFFECB200))
    val switchActive = Color(0xFF2E9E4F)
    val link: Color @Composable get() = pick(dark, Color(0xFF1971C2), Color(0xFF74C0FC))
    val settingsTile: Color @Composable get() = pick(dark, Color(0xFF3A3A3C), Color(0xFF48484A))
    val tile: Color @Composable get() = pick(dark, Color.Black.copy(alpha = 0.08f), Color.White.copy(alpha = 0.08f))
}

object AppFont {
    val poppins = FontFamily(Font(R.font.poppins_bold, FontWeight.Bold), Font(R.font.poppins_semibold, FontWeight.SemiBold))
    fun brand(size: TextUnit) = TextStyle(fontFamily = poppins, fontWeight = FontWeight.Bold, fontSize = size)
    fun brandSemibold(size: TextUnit) = TextStyle(fontFamily = poppins, fontWeight = FontWeight.SemiBold, fontSize = size)
}

enum class ThemePreference(val raw: String) {
    SYSTEM("system"), LIGHT("light"), DARK("dark");

    companion object {
        fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: SYSTEM
    }
}

object ThemeState {
    var preference by mutableStateOf(ThemePreference.from(Prefs.string("theme_preference")))
        private set
    var language by mutableStateOf(Prefs.string("app_language"))
        private set

    fun applyTheme(value: ThemePreference) {
        Prefs.set("theme_preference", value.raw)
        preference = value
    }

    fun applyLanguage(code: String?) {
        Prefs.set("app_language", code)
        Localizer.apply(code)
        language = code
    }
}

@Composable
fun QiqstrTheme(content: @Composable () -> Unit) {
    val dark = when (ThemeState.preference) {
        ThemePreference.SYSTEM -> isSystemInDarkTheme()
        ThemePreference.LIGHT -> false
        ThemePreference.DARK -> true
    }
    val view = androidx.compose.ui.platform.LocalView.current
    if (!view.isInEditMode) {
        androidx.compose.runtime.SideEffect {
            val window = (view.context as? android.app.Activity)?.window ?: return@SideEffect
            androidx.core.view.WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !dark
                isAppearanceLightNavigationBars = !dark
            }
        }
    }
    val scheme = if (dark) {
        darkColorScheme(
            primary = Color.White, onPrimary = Color.Black,
            primaryContainer = Color(0xFF1F1F1F), onPrimaryContainer = Color.White,
            secondary = Color(0xFFE0E0E0), onSecondary = Color.Black,
            secondaryContainer = Color(0xFF262626), onSecondaryContainer = Color.White,
            tertiary = Color(0xFFFF8A3D),
            background = Color(0xFF0A0A0A), onBackground = Color.White,
            surface = Color(0xFF0A0A0A), onSurface = Color.White,
            surfaceVariant = Color(0xFF1A1A1A), onSurfaceVariant = Color(0xFFBDBDBD),
            surfaceContainerLowest = Color(0xFF050505), surfaceContainerLow = Color(0xFF111111),
            surfaceContainer = Color(0xFF151515), surfaceContainerHigh = Color(0xFF1C1C1C),
            surfaceContainerHighest = Color(0xFF242424),
            outline = Color(0xFF444444), outlineVariant = Color(0xFF2A2A2A),
            error = Color(0xFFFF6B6B), onError = Color.Black,
        )
    } else {
        lightColorScheme(
            primary = Color.Black, onPrimary = Color.White,
            primaryContainer = Color(0xFFEDEDED), onPrimaryContainer = Color.Black,
            secondary = Color(0xFF424242), onSecondary = Color.White,
            secondaryContainer = Color(0xFFEDEDED), onSecondaryContainer = Color.Black,
            tertiary = Color(0xFFFF6A00),
            background = Color.White, onBackground = Color.Black,
            surface = Color.White, onSurface = Color.Black,
            surfaceVariant = Color(0xFFF2F2F2), onSurfaceVariant = Color(0xFF5C5C5C),
            surfaceContainerLowest = Color.White, surfaceContainerLow = Color(0xFFF7F7F7),
            surfaceContainer = Color(0xFFF2F2F2), surfaceContainerHigh = Color(0xFFECECEC),
            surfaceContainerHighest = Color(0xFFE6E6E6),
            outline = Color(0xFFBDBDBD), outlineVariant = Color(0xFFE0E0E0),
            error = Color(0xFFD62C2C), onError = Color.White,
        )
    }
    CompositionLocalProvider(LocalDarkTheme provides dark) {
        MaterialTheme(colorScheme = scheme, typography = AppTypography, content = content)
    }
}

private val AppTypography = androidx.compose.material3.Typography().let {
    it.copy(
        headlineLarge = it.headlineLarge.copy(fontWeight = FontWeight.Bold),
        headlineMedium = it.headlineMedium.copy(fontWeight = FontWeight.Bold),
        headlineSmall = it.headlineSmall.copy(fontWeight = FontWeight.Bold),
        titleLarge = it.titleLarge.copy(fontWeight = FontWeight.SemiBold),
    )
}
