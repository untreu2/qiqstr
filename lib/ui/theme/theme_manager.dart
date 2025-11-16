import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'colors.dart';

class ThemeManager extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  static const String _expandedNoteModeKey = 'expanded_note_mode';
  static const String _bottomNavOrderKey = 'bottom_nav_order';
  bool? _isDarkMode;
  bool _isExpandedNoteMode = false;
  List<int> _bottomNavOrder = [0, 1, 2, 3];

  bool get isDarkMode {
    if (_isDarkMode != null) {
      return _isDarkMode!;
    }
    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark;
  }

  bool get isSystemTheme => _isDarkMode == null;
  bool get isExpandedNoteMode => _isExpandedNoteMode;
  List<int> get bottomNavOrder => List.unmodifiable(_bottomNavOrder);

  ThemeManager() {
    _loadTheme();
    _loadExpandedNoteMode();
    _loadBottomNavOrder();
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

  Future<void> _loadBottomNavOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final orderList = prefs.getStringList(_bottomNavOrderKey);
    if (orderList != null && orderList.length == 4) {
      _bottomNavOrder = orderList.map((e) => int.parse(e)).toList();
      notifyListeners();
    }
  }

  Future<void> setBottomNavOrder(List<int> order) async {
    if (order.length == 4 && order.toSet().length == 4) {
      _bottomNavOrder = List.from(order);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_bottomNavOrderKey, order.map((e) => e.toString()).toList());
      notifyListeners();
    }
  }

  AppThemeColors get colors => isDarkMode ? AppThemeColors.dark() : AppThemeColors.light();
}

class AppThemeColors {
  final Color accent;
  final Color background;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color error;
  final Color success;
  final Color warning;
  final Color buttonPrimary;
  final Color buttonText;
  final Color border;
  final Color divider;
  final Color overlayLight;
  final Color inputFill;
  final Color avatarPlaceholder;
  final Color reaction;
  final Color reply;
  final Color repost;
  final Color zap;

  AppThemeColors({
    required this.accent,
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.error,
    required this.success,
    required this.warning,
    required this.buttonPrimary,
    required this.buttonText,
    required this.border,
    required this.divider,
    required this.overlayLight,
    required this.inputFill,
    required this.avatarPlaceholder,
    required this.reaction,
    required this.reply,
    required this.repost,
    required this.zap,
  });

  Color get primary => textPrimary;
  Color get secondary => textSecondary;
  Color get surfaceVariant => surface;
  Color get textTertiary => textSecondary;
  Color get textDisabled => textSecondary.withValues(alpha: 0.5);
  Color get textHint => textSecondary;
  Color get buttonSecondary => overlayLight;
  Color get buttonBorder => border;
  Color get borderLight => border;
  Color get borderAccent => border;
  Color get overlay => background.withValues(alpha: 0.5);
  Color get overlayDark => background.withValues(alpha: 0.8);
  Color get iconPrimary => textPrimary;
  Color get iconSecondary => textSecondary;
  Color get iconDisabled => textSecondary.withValues(alpha: 0.5);
  Color get avatarBackground => surface;
  Color get inputBorder => border;
  Color get inputFocused => textPrimary;
  Color get inputLabel => textSecondary;
  Color get loading => textPrimary;
  Color get loadingBackground => surface;
  Color get notificationBackground => surface;
  Color get backgroundTransparent => background.withValues(alpha: 0.85);
  Color get surfaceTransparent => surface.withValues(alpha: 0.9);
  Color get overlayTransparent => background.withValues(alpha: 0.75);
  Color get borderTransparent => textPrimary.withValues(alpha: 0.3);
  Color get hoverTransparent => textPrimary.withValues(alpha: 0.1);
  List<Color> get backgroundGradient => [background, surface, background];
  Color get cardBackground => surface;
  Color get cardBorder => border;
  Color get profileBorder => border;
  Color get videoBorder => textPrimary.withValues(alpha: 0.3);
  Color get sliderActive => textPrimary;
  Color get sliderInactive => border;
  Color get sliderThumb => textPrimary;
  Color get glassBackground => surface.withValues(alpha: 0.7);
  Color get grey600 => textSecondary;
  Color get grey700 => textSecondary;
  Color get grey800 => border;
  Color get grey900 => border;
  Color get red400 => reaction;
  Color get blue200 => reply;
  Color get green400 => repost;

  factory AppThemeColors.dark() {
    return AppThemeColors(
      accent: AppColors.accent,
      background: AppColors.background,
      surface: AppColors.surface,
      textPrimary: AppColors.textPrimary,
      textSecondary: AppColors.textSecondary,
      error: AppColors.error,
      success: AppColors.success,
      warning: AppColors.warning,
      buttonPrimary: AppColors.buttonPrimary,
      buttonText: AppColors.buttonText,
      border: AppColors.border,
      divider: AppColors.divider,
      overlayLight: AppColors.overlayLight,
      inputFill: AppColors.inputFill,
      avatarPlaceholder: AppColors.avatarPlaceholder,
      reaction: AppColors.reaction,
      reply: AppColors.reply,
      repost: AppColors.repost,
      zap: AppColors.zap,
    );
  }

  factory AppThemeColors.light() {
    return AppThemeColors(
      accent: AppColorsLight.accent,
      background: AppColorsLight.background,
      surface: AppColorsLight.surface,
      textPrimary: AppColorsLight.textPrimary,
      textSecondary: AppColorsLight.textSecondary,
      error: AppColorsLight.error,
      success: AppColorsLight.success,
      warning: AppColorsLight.warning,
      buttonPrimary: AppColorsLight.buttonPrimary,
      buttonText: AppColorsLight.buttonText,
      border: AppColorsLight.border,
      divider: AppColorsLight.divider,
      overlayLight: AppColorsLight.overlayLight,
      inputFill: AppColorsLight.inputFill,
      avatarPlaceholder: AppColorsLight.avatarPlaceholder,
      reaction: AppColorsLight.reaction,
      reply: AppColorsLight.reply,
      repost: AppColorsLight.repost,
      zap: AppColorsLight.zap,
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
