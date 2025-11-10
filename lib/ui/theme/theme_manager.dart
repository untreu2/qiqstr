import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'colors.dart';

class ThemeManager extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  static const String _expandedNoteModeKey = 'expanded_note_mode';
  bool? _isDarkMode;
  bool _isExpandedNoteMode = false;

  bool get isDarkMode {
    if (_isDarkMode != null) {
      return _isDarkMode!;
    }
    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark;
  }

  bool get isSystemTheme => _isDarkMode == null;
  bool get isExpandedNoteMode => _isExpandedNoteMode;

  ThemeManager() {
    _loadTheme();
    _loadExpandedNoteMode();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_themeKey)) {
      _isDarkMode = prefs.getBool(_themeKey);
    } else {
      _isDarkMode = null;
    }
    notifyListeners();
  }

  Future<void> _loadExpandedNoteMode() async {
    final prefs = await SharedPreferences.getInstance();
    _isExpandedNoteMode = prefs.getBool(_expandedNoteModeKey) ?? false;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    if (_isDarkMode == null) {
      final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      _isDarkMode = brightness == Brightness.light;
    } else {
      _isDarkMode = !_isDarkMode!;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeKey, _isDarkMode!);
    notifyListeners();
  }

  Future<void> setTheme(bool isDark) async {
    if (_isDarkMode != isDark) {
      _isDarkMode = isDark;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_themeKey, _isDarkMode!);
      notifyListeners();
    }
  }

  Future<void> setSystemTheme() async {
    _isDarkMode = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_themeKey);
    notifyListeners();
  }

  Future<void> toggleExpandedNoteMode() async {
    _isExpandedNoteMode = !_isExpandedNoteMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_expandedNoteModeKey, _isExpandedNoteMode);
    notifyListeners();
  }

  Future<void> setExpandedNoteMode(bool isExpanded) async {
    if (_isExpandedNoteMode != isExpanded) {
      _isExpandedNoteMode = isExpanded;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_expandedNoteModeKey, _isExpandedNoteMode);
      notifyListeners();
    }
  }

  AppThemeColors get colors => isDarkMode ? AppThemeColors.dark() : AppThemeColors.light();
}

class AppThemeColors {
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;
  final Color textHint;
  final Color error;
  final Color success;
  final Color warning;
  final Color buttonPrimary;
  final Color buttonText;
  final Color buttonSecondary;
  final Color buttonBorder;
  final Color border;
  final Color borderLight;
  final Color borderAccent;
  final Color divider;
  final Color overlay;
  final Color overlayLight;
  final Color overlayDark;
  final Color iconPrimary;
  final Color iconSecondary;
  final Color iconDisabled;
  final Color reaction;
  final Color reply;
  final Color repost;
  final Color zap;
  final Color avatarBackground;
  final Color avatarPlaceholder;
  final Color inputFill;
  final Color inputBorder;
  final Color inputFocused;
  final Color inputLabel;
  final Color loading;
  final Color loadingBackground;
  final Color notificationBackground;
  final Color backgroundTransparent;
  final Color surfaceTransparent;
  final Color overlayTransparent;
  final Color borderTransparent;
  final Color hoverTransparent;
  final List<Color> backgroundGradient;
  final Color cardBackground;
  final Color cardBorder;
  final Color profileBorder;
  final Color videoBorder;
  final Color sliderActive;
  final Color sliderInactive;
  final Color sliderThumb;
  final Color glassBackground;
  final Color grey600;
  final Color grey700;
  final Color grey800;
  final Color grey900;
  final Color red400;
  final Color blue200;
  final Color green400;

  AppThemeColors({
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.textHint,
    required this.error,
    required this.success,
    required this.warning,
    required this.buttonPrimary,
    required this.buttonText,
    required this.buttonSecondary,
    required this.buttonBorder,
    required this.border,
    required this.borderLight,
    required this.borderAccent,
    required this.divider,
    required this.overlay,
    required this.overlayLight,
    required this.overlayDark,
    required this.iconPrimary,
    required this.iconSecondary,
    required this.iconDisabled,
    required this.reaction,
    required this.reply,
    required this.repost,
    required this.zap,
    required this.avatarBackground,
    required this.avatarPlaceholder,
    required this.inputFill,
    required this.inputBorder,
    required this.inputFocused,
    required this.inputLabel,
    required this.loading,
    required this.loadingBackground,
    required this.notificationBackground,
    required this.backgroundTransparent,
    required this.surfaceTransparent,
    required this.overlayTransparent,
    required this.borderTransparent,
    required this.hoverTransparent,
    required this.backgroundGradient,
    required this.cardBackground,
    required this.cardBorder,
    required this.profileBorder,
    required this.videoBorder,
    required this.sliderActive,
    required this.sliderInactive,
    required this.sliderThumb,
    required this.glassBackground,
    required this.grey600,
    required this.grey700,
    required this.grey800,
    required this.grey900,
    required this.red400,
    required this.blue200,
    required this.green400,
  });

  factory AppThemeColors.dark() {
    return AppThemeColors(
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      accent: AppColors.accent,
      background: AppColors.background,
      surface: AppColors.surface,
      surfaceVariant: AppColors.surfaceVariant,
      textPrimary: AppColors.textPrimary,
      textSecondary: AppColors.textSecondary,
      textTertiary: AppColors.textTertiary,
      textDisabled: AppColors.textDisabled,
      textHint: AppColors.textHint,
      error: AppColors.error,
      success: AppColors.success,
      warning: AppColors.warning,
      buttonPrimary: AppColors.buttonPrimary,
      buttonText: AppColors.buttonText,
      buttonSecondary: AppColors.buttonSecondary,
      buttonBorder: AppColors.buttonBorder,
      border: AppColors.border,
      borderLight: AppColors.borderLight,
      borderAccent: AppColors.borderAccent,
      divider: AppColors.divider,
      overlay: AppColors.overlay,
      overlayLight: AppColors.overlayLight,
      overlayDark: AppColors.overlayDark,
      iconPrimary: AppColors.iconPrimary,
      iconSecondary: AppColors.iconSecondary,
      iconDisabled: AppColors.iconDisabled,
      reaction: AppColors.reaction,
      reply: AppColors.reply,
      repost: AppColors.repost,
      zap: AppColors.zap,
      avatarBackground: AppColors.avatarBackground,
      avatarPlaceholder: AppColors.avatarPlaceholder,
      inputFill: AppColors.inputFill,
      inputBorder: AppColors.inputBorder,
      inputFocused: AppColors.inputFocused,
      inputLabel: AppColors.inputLabel,
      loading: AppColors.loading,
      loadingBackground: AppColors.loadingBackground,
      notificationBackground: AppColors.notificationBackground,
      backgroundTransparent: AppColors.backgroundTransparent,
      surfaceTransparent: AppColors.surfaceTransparent,
      overlayTransparent: AppColors.overlayTransparent,
      borderTransparent: AppColors.borderTransparent,
      hoverTransparent: AppColors.hoverTransparent,
      backgroundGradient: AppColors.backgroundGradient,
      cardBackground: AppColors.cardBackground,
      cardBorder: AppColors.cardBorder,
      profileBorder: AppColors.profileBorder,
      videoBorder: AppColors.videoBorder,
      sliderActive: AppColors.sliderActive,
      sliderInactive: AppColors.sliderInactive,
      sliderThumb: AppColors.sliderThumb,
      glassBackground: AppColors.glassBackground,
      grey600: AppColors.grey600,
      grey700: AppColors.grey700,
      grey800: AppColors.grey800,
      grey900: AppColors.grey900,
      red400: AppColors.red400,
      blue200: AppColors.blue400,
      green400: AppColors.green400,
    );
  }

  factory AppThemeColors.light() {
    return AppThemeColors(
      primary: AppColorsLight.primary,
      secondary: AppColorsLight.secondary,
      accent: AppColorsLight.accent,
      background: AppColorsLight.background,
      surface: AppColorsLight.surface,
      surfaceVariant: AppColorsLight.surfaceVariant,
      textPrimary: AppColorsLight.textPrimary,
      textSecondary: AppColorsLight.textSecondary,
      textTertiary: AppColorsLight.textTertiary,
      textDisabled: AppColorsLight.textDisabled,
      textHint: AppColorsLight.textHint,
      error: AppColorsLight.error,
      success: AppColorsLight.success,
      warning: AppColorsLight.warning,
      buttonPrimary: AppColorsLight.buttonPrimary,
      buttonText: AppColorsLight.buttonText,
      buttonSecondary: AppColorsLight.buttonSecondary,
      buttonBorder: AppColorsLight.buttonBorder,
      border: AppColorsLight.border,
      borderLight: AppColorsLight.borderLight,
      borderAccent: AppColorsLight.borderAccent,
      divider: AppColorsLight.divider,
      overlay: AppColorsLight.overlay,
      overlayLight: AppColorsLight.overlayLight,
      overlayDark: AppColorsLight.overlayDark,
      iconPrimary: AppColorsLight.iconPrimary,
      iconSecondary: AppColorsLight.iconSecondary,
      iconDisabled: AppColorsLight.iconDisabled,
      reaction: AppColorsLight.reaction,
      reply: AppColorsLight.reply,
      repost: AppColorsLight.repost,
      zap: AppColorsLight.zap,
      avatarBackground: AppColorsLight.avatarBackground,
      avatarPlaceholder: AppColorsLight.avatarPlaceholder,
      inputFill: AppColorsLight.inputFill,
      inputBorder: AppColorsLight.inputBorder,
      inputFocused: AppColorsLight.inputFocused,
      inputLabel: AppColorsLight.inputLabel,
      loading: AppColorsLight.loading,
      loadingBackground: AppColorsLight.loadingBackground,
      notificationBackground: AppColorsLight.notificationBackground,
      backgroundTransparent: AppColorsLight.backgroundTransparent,
      surfaceTransparent: AppColorsLight.surfaceTransparent,
      overlayTransparent: AppColorsLight.overlayTransparent,
      borderTransparent: AppColorsLight.borderTransparent,
      hoverTransparent: AppColorsLight.hoverTransparent,
      backgroundGradient: AppColorsLight.backgroundGradient,
      cardBackground: AppColorsLight.cardBackground,
      cardBorder: AppColorsLight.cardBorder,
      profileBorder: AppColorsLight.profileBorder,
      videoBorder: AppColorsLight.videoBorder,
      sliderActive: AppColorsLight.sliderActive,
      sliderInactive: AppColorsLight.sliderInactive,
      sliderThumb: AppColorsLight.sliderThumb,
      glassBackground: AppColorsLight.glassBackground,
      grey600: AppColorsLight.grey600,
      grey700: AppColorsLight.grey700,
      grey800: AppColorsLight.grey800,
      grey900: AppColorsLight.grey900,
      red400: AppColorsLight.red400,
      blue200: AppColorsLight.blue200,
      green400: AppColorsLight.green400,
    );
  }
}

extension ThemeExtension on BuildContext {
  AppThemeColors get colors {
    try {
      final themeManager = Provider.of<ThemeManager>(this, listen: false);
      return themeManager.colors;
    } catch (e) {
      return AppThemeColors.dark();
    }
  }

  ThemeManager? get themeManager {
    try {
      return Provider.of<ThemeManager>(this, listen: false);
    } catch (e) {
      return null;
    }
  }
}
