import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../presentation/blocs/theme/theme_bloc.dart';
import '../../../presentation/blocs/theme/theme_state.dart';
import 'colors.dart';

class AppThemeColors {
  final Color accent;
  final Color background;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color error;
  final Color success;
  final Color warning;
  final Color border;
  final Color divider;
  final Color overlayLight;
  final Color inputFill;
  final Color avatarPlaceholder;
  final Color reaction;
  final Color reply;
  final Color repost;
  final Color zap;
  final Color switchActive;

  AppThemeColors({
    required this.accent,
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.error,
    required this.success,
    required this.warning,
    required this.border,
    required this.divider,
    required this.overlayLight,
    required this.inputFill,
    required this.avatarPlaceholder,
    required this.reaction,
    required this.reply,
    required this.repost,
    required this.zap,
    required this.switchActive,
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
      border: AppColors.border,
      divider: AppColors.divider,
      overlayLight: AppColors.overlayLight,
      inputFill: AppColors.inputFill,
      avatarPlaceholder: AppColors.avatarPlaceholder,
      reaction: AppColors.reaction,
      reply: AppColors.reply,
      repost: AppColors.repost,
      zap: AppColors.zap,
      switchActive: AppColors.switchActive,
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
      border: AppColorsLight.border,
      divider: AppColorsLight.divider,
      overlayLight: AppColorsLight.overlayLight,
      inputFill: AppColorsLight.inputFill,
      avatarPlaceholder: AppColorsLight.avatarPlaceholder,
      reaction: AppColorsLight.reaction,
      reply: AppColorsLight.reply,
      repost: AppColorsLight.repost,
      zap: AppColorsLight.zap,
      switchActive: AppColorsLight.switchActive,
    );
  }
}

extension ThemeExtension on BuildContext {
  AppThemeColors get colors {
    try {
      final themeState = read<ThemeBloc>().state;
      return themeState.colors;
    } catch (e) {
      return AppThemeColors.dark();
    }
  }

  ThemeState? get themeState {
    try {
      return read<ThemeBloc>().state;
    } catch (e) {
      return null;
    }
  }
}
