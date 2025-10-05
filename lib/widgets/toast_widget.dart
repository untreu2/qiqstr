import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme_manager.dart';

enum ToastType {
  success,
  error,
  info,
  warning,
}

class AppToast {
  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;

    final colors = _getColors(context);
    final backgroundColor = _getBackgroundColor(colors, type);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(16),
        duration: duration,
        action: action,
      ),
    );
  }

  static void success(BuildContext context, String message, {Duration? duration}) {
    show(
      context,
      message,
      type: ToastType.success,
      duration: duration ?? const Duration(seconds: 3),
    );
  }

  static void error(BuildContext context, String message, {Duration? duration}) {
    show(
      context,
      message,
      type: ToastType.error,
      duration: duration ?? const Duration(seconds: 3),
    );
  }

  static void info(BuildContext context, String message, {Duration? duration}) {
    show(
      context,
      message,
      type: ToastType.info,
      duration: duration ?? const Duration(seconds: 3),
    );
  }

  static void warning(BuildContext context, String message, {Duration? duration}) {
    show(
      context,
      message,
      type: ToastType.warning,
      duration: duration ?? const Duration(seconds: 3),
    );
  }

  static void hide(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  static AppThemeColors _getColors(BuildContext context) {
    try {
      final themeManager = Provider.of<ThemeManager>(context, listen: false);
      return themeManager.colors;
    } catch (e) {
      return AppThemeColors.dark();
    }
  }

  static Color _getBackgroundColor(AppThemeColors colors, ToastType type) {
    return colors.secondary.withValues(alpha: 0.9);
  }
}

