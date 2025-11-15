import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import 'common_buttons.dart';

enum SnackbarType {
  success,
  error,
  info,
  warning,
}

class AppSnackbar {
  static void show(
    BuildContext context,
    String message, {
    SnackbarType type = SnackbarType.info,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;

    final colors = _getColors(context);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(40),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: 12),
                TextActionButton(
                  label: action.label,
                  onPressed: action.onPressed,
                  size: ButtonSize.small,
                  foregroundColor: colors.accent,
                ),
              ],
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(40),
        ),
        margin: const EdgeInsets.all(16),
        duration: duration,
        elevation: 0,
      ),
    );
  }

  static void success(BuildContext context, String message, {Duration? duration, SnackBarAction? action}) {
    show(
      context,
      message,
      type: SnackbarType.success,
      duration: duration ?? const Duration(seconds: 3),
      action: action,
    );
  }

  static void error(BuildContext context, String message, {Duration? duration, SnackBarAction? action}) {
    show(
      context,
      message,
      type: SnackbarType.error,
      duration: duration ?? const Duration(seconds: 4),
      action: action,
    );
  }

  static void info(BuildContext context, String message, {Duration? duration, SnackBarAction? action}) {
    show(
      context,
      message,
      type: SnackbarType.info,
      duration: duration ?? const Duration(seconds: 3),
      action: action,
    );
  }

  static void warning(BuildContext context, String message, {Duration? duration, SnackBarAction? action}) {
    show(
      context,
      message,
      type: SnackbarType.warning,
      duration: duration ?? const Duration(seconds: 3),
      action: action,
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
}
