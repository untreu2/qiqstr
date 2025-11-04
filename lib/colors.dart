import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF4A4A4A);
  static const Color secondary = Color(0xFF888888);
  static const Color accent = Color.fromARGB(255, 222, 169, 54);

  static const Color background = Colors.black;
  static const Color surface = Colors.black;
  static const Color surfaceVariant = Colors.black;

  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Colors.white70;
  static const Color textTertiary = Colors.white54;
  static const Color textDisabled = Colors.white38;
  static const Color textHint = Colors.white54;

  static const Color error = Colors.redAccent;
  static const Color success = Colors.greenAccent;
  static const Color warning = Colors.amber;

  static const Color buttonPrimary = Color(0xFF4A4A4A);
  static const Color buttonText = Colors.white;
  static const Color buttonSecondary = Color(0xFF2A2A2A);
  static const Color buttonBorder = Color(0xFF666666);

  static const Color border = Color(0xFF333333);
  static const Color borderLight = Color(0xFF444444);
  static const Color borderAccent = Color(0xFF666666);
  static const Color divider = Color(0xFF333333);

  static const Color overlay = Colors.black54;
  static const Color overlayLight = Colors.white10;
  static const Color overlayDark = Colors.black87;

  static const Color iconPrimary = Color(0xFF888888);
  static const Color iconSecondary = Color(0xFFB3B3B3);
  static const Color iconDisabled = Color(0xFF555555);

  static const Color reaction = Color(0xFFFF6B6B);
  static const Color reply = Color(0xFF74C0FC);
  static const Color repost = Color(0xFF51CF66);
  static const Color zap = Color(0xFFECB200);

  static const Color avatarBackground = Color(0xFF444444);
  static const Color avatarPlaceholder = Color(0xFF666666);

  static const Color inputFill = Color(0xFF1A1A1A);
  static const Color inputBorder = Color(0xFF444444);
  static const Color inputFocused = Color(0xFF666666);
  static const Color inputLabel = Color(0xFFB3B3B3);

  static const Color loading = Color(0xFF666666);
  static const Color loadingBackground = Color(0xFF333333);

  static const Color notificationBackground = Color(0xFF2A2A2A);

  static Color get backgroundTransparent => Colors.black.withValues(alpha: 0.3);
  static Color get surfaceTransparent => Colors.transparent;
  static Color get overlayTransparent => Colors.black.withValues(alpha: 0.7);
  static Color get borderTransparent => Colors.white.withValues(alpha: 0.3);
  static Color get hoverTransparent => Colors.white.withValues(alpha: 0.08);

  static const List<Color> backgroundGradient = [
    Colors.black,
    Colors.black,
  ];

  static Color get cardBackground => Color(0xFF1A1A1A);
  static Color get cardBorder => Color(0xFF333333);
  static Color get profileBorder => Colors.black;
  static Color get videoBorder => Colors.white.withValues(alpha: 0.2);

  static const Color sliderActive = Colors.amber;
  static const Color sliderInactive = Color(0xFF444444);
  static const Color sliderThumb = Color(0xFF666666);

  static const Color glassBackground = Color(0xFF000000);

  static Color get grey600 => Colors.grey.shade600;
  static Color get grey700 => Colors.grey.shade700;
  static Color get grey800 => Colors.grey.shade800;
  static Color get grey900 => Colors.grey.shade900;

  static Color get red400 => Colors.red.shade400;

  static Color get blue200 => Colors.blue.shade200;

  static Color get green400 => Colors.green.shade400;
}

class AppColorsLight {
  static const Color primary = Color(0xFF2D2D2D);
  static const Color secondary = Color.fromARGB(255, 74, 69, 69);
  static const Color accent = Color(0xFF8B0000);

  static const Color background = Colors.white;
  static const Color surface = Colors.white;
  static const Color surfaceVariant = Color(0xFFF5F5F5);

  static const Color textPrimary = Colors.black;
  static const Color textSecondary = Colors.black54;
  static const Color textTertiary = Colors.black38;
  static const Color textDisabled = Colors.black26;
  static const Color textHint = Colors.black38;

  static const Color error = Colors.redAccent;
  static const Color success = Colors.greenAccent;
  static const Color warning = Colors.amber;

  static const Color buttonPrimary = Color(0xFF2D2D2D);
  static const Color buttonText = Colors.white;
  static const Color buttonSecondary = Colors.black12;
  static const Color buttonBorder = Colors.black26;

  static const Color border = Colors.black12;
  static const Color borderLight = Colors.black26;
  static const Color borderAccent = Colors.black38;
  static const Color divider = Colors.black12;

  static const Color overlay = Colors.white54;
  static const Color overlayLight = Colors.black12;
  static const Color overlayDark = Colors.white70;

  static const Color iconPrimary = Color(0xFF2D2D2D);
  static const Color iconSecondary = Colors.black54;
  static const Color iconDisabled = Colors.black26;

  static const Color reaction = Color(0xFFFF6B6B);
  static const Color reply = Color(0xFF74C0FC);
  static const Color repost = Color(0xFF51CF66);
  static const Color zap = Color(0xFFECB200);

  static const Color avatarBackground = Color(0xFFE0E0E0);
  static const Color avatarPlaceholder = Colors.black26;

  static const Color inputFill = Colors.black12;
  static const Color inputBorder = Colors.black26;
  static const Color inputFocused = Colors.black;
  static const Color inputLabel = Colors.black54;

  static const Color loading = Colors.black;
  static const Color loadingBackground = Colors.black26;

  static const Color notificationBackground = Color(0xFFF0F0F0);

  static Color get backgroundTransparent => Colors.white.withValues(alpha: 0.3);
  static Color get surfaceTransparent => Colors.transparent;
  static Color get overlayTransparent => Colors.white.withValues(alpha: 0.7);
  static Color get borderTransparent => Colors.black.withValues(alpha: 0.2);
  static Color get hoverTransparent => Colors.black.withValues(alpha: 0.05);

  static const List<Color> backgroundGradient = [
    Colors.white,
    Color(0xFFF8F8F8),
  ];

  static Color get cardBackground => Colors.grey.shade100.withValues(alpha: 0.5);
  static Color get cardBorder => Colors.grey.shade300;
  static Color get profileBorder => Colors.white;
  static Color get videoBorder => Colors.black.withValues(alpha: 0.2);

  static const Color sliderActive = Colors.amber;
  static const Color sliderInactive = Colors.black26;
  static const Color sliderThumb = Colors.black;

  static const Color glassBackground = Color(0xFFFFFFFF);

  static Color get grey600 => Colors.grey.shade600;
  static Color get grey700 => Colors.grey.shade700;
  static Color get grey800 => Colors.grey.shade800;
  static Color get grey900 => Colors.grey.shade900;

  static Color get red400 => Colors.red.shade400;

  static Color get blue200 => Colors.blue.shade200;

  static Color get green400 => Colors.green.shade400;
}
