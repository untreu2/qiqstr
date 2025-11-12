import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFFFFFFFF);
  static const Color secondary = Color(0xFFB3B3B3);
  static const Color accent = Color.fromARGB(255, 240, 160, 90);

  static const Color background = Color(0xFF0D0B0A);
  static const Color surface = Color(0xFF0D0B0A);
  static const Color surfaceVariant = Color(0xFF141414);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFE0E0E0);
  static const Color textTertiary = Color(0xFFB3B3B3);
  static const Color textDisabled = Color(0xFF666666);
  static const Color textHint = Color(0xFF808080);

  static const Color error = Color(0xFFFF6B6B);
  static const Color success = Color(0xFFFFFFFF);
  static const Color warning = Color(0xFFE0E0E0);

  static const Color buttonPrimary = Color(0xFF333333);
  static const Color buttonSecondary = Color(0xFF1A1A1A);
  static const Color buttonText = Color(0xFFFFFFFF);
  static const Color buttonBorder = Color(0xFF666666);

  static const Color border = Color(0xFF333333);
  static const Color borderLight = Color(0xFF4D4D4D);
  static const Color borderAccent = Color(0xFF666666);
  static const Color divider = Color(0xFF2A2A2A);

  static const Color overlay = Color(0x800D0B0A);
  static const Color overlayLight = Color(0x1AFFFFFF);
  static const Color overlayDark = Color(0xCC0D0B0A);

  static const Color iconPrimary = Color(0xFFE0E0E0);
  static const Color iconSecondary = Color(0xFFB3B3B3);
  static const Color iconDisabled = Color(0xFF4D4D4D);

  static const Color reaction = Color(0xFFFF6B6B);
  static const Color reply = Color(0xFF74C0FC);
  static const Color repost = Color(0xFF51CF66);
  static const Color zap = Color(0xFFECB200);

  static const Color avatarBackground = Color(0xFF2A2A2A);
  static const Color avatarPlaceholder = Color(0xFF666666);
  static const Color profileBorder = Color(0xFF404040);

  static const Color inputFill = Color(0xFF141414);
  static const Color inputBorder = Color(0xFF333333);
  static const Color inputFocused = Color(0xFFFFFFFF);
  static const Color inputLabel = Color(0xFFB3B3B3);

  static const Color loading = Color(0xFFFFFFFF);
  static const Color loadingBackground = Color(0xFF2A2A2A);

  static const Color notificationBackground = Color(0xFF1A1A1A);

  static Color get backgroundTransparent => Color(0xFF0D0B0A).withValues(alpha: 0.85);
  static Color get surfaceTransparent => Color(0xFF0F0D0B).withValues(alpha: 0.9);
  static Color get overlayTransparent => Color(0xFF0D0B0A).withValues(alpha: 0.75);
  static Color get borderTransparent => Color(0xFFFFFFFF).withValues(alpha: 0.3);
  static Color get hoverTransparent => Color(0xFFFFFFFF).withValues(alpha: 0.1);

  static const List<Color> backgroundGradient = [
    Color(0xFF0D0B0A),
    Color(0xFF0F0D0B),
    Color(0xFF0D0B0A),
  ];

  static Color get cardBackground => Color(0xFF141414);
  static Color get cardBorder => Color(0xFF333333);
  static Color get videoBorder => Color(0xFFFFFFFF).withValues(alpha: 0.3);

  static const Color sliderActive = Color(0xFFFFFFFF);
  static const Color sliderInactive = Color(0xFF404040);
  static const Color sliderThumb = Color(0xFFFFFFFF);

  static Color get glassBackground => Color(0xFF0F0D0B).withValues(alpha: 0.7);

  static Color get grey600 => Color(0xFF808080);
  static Color get grey700 => Color(0xFF666666);
  static Color get grey800 => Color(0xFF4D4D4D);
  static Color get grey900 => Color(0xFF333333);

  static Color get red400 => Color(0xFFE0E0E0);

  static Color get blue400 => Color(0xFFE0E0E0);

  static Color get green400 => Color(0xFFE0E0E0);
}

class AppColorsLight {
  static const Color primary = Color(0xFF2D2D2D);
  static const Color secondary = Color.fromARGB(255, 74, 69, 69);
  static const Color accent = Color.fromARGB(255, 140, 0, 125);

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
