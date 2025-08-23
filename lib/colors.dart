import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Colors.white;
  static const Color secondary = Colors.grey;
  static const Color accent = Color.fromARGB(255, 195, 60, 150);

  static const Color background = Color.fromARGB(255, 25, 25, 25);
  static const Color surface = Color.fromARGB(255, 25, 25, 25);
  static const Color surfaceVariant = Color.fromARGB(255, 25, 25, 25);

  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Colors.white70;
  static const Color textTertiary = Colors.white54;
  static const Color textDisabled = Colors.white38;
  static const Color textHint = Colors.white54;

  static const Color error = Colors.redAccent;
  static const Color success = Colors.greenAccent;
  static const Color warning = Colors.amber;

  static const Color buttonPrimary = Colors.white;
  static const Color buttonSecondary = Colors.white10;
  static const Color buttonBorder = Colors.white30;

  static const Color border = Colors.white12;
  static const Color borderLight = Colors.white24;
  static const Color borderAccent = Colors.white30;
  static const Color divider = Colors.white12;

  static const Color overlay = Colors.black54;
  static const Color overlayLight = Colors.white10;
  static const Color overlayDark = Colors.black87;

  static const Color iconPrimary = Colors.white;
  static const Color iconSecondary = Colors.white70;
  static const Color iconDisabled = Colors.white38;

  static const Color reaction = Color(0xFFFF6B6B);
  static const Color reply = Color(0xFF74C0FC);
  static const Color repost = Color(0xFF51CF66);
  static const Color zap = Color(0xFFECB200);

  static const Color avatarBackground = Colors.grey;
  static const Color avatarPlaceholder = Colors.white24;

  static const Color inputFill = Colors.white10;
  static const Color inputBorder = Colors.white24;
  static const Color inputFocused = Colors.white;
  static const Color inputLabel = Colors.white70;

  static const Color loading = Colors.white;
  static const Color loadingBackground = Colors.white38;

  static const Color notificationBackground = Colors.grey;

  static Color get backgroundTransparent => Colors.black.withOpacity(0.3);
  static Color get surfaceTransparent => Colors.transparent;
  static Color get overlayTransparent => Colors.black.withOpacity(0.7);
  static Color get borderTransparent => Colors.white.withOpacity(0.2);
  static Color get hoverTransparent => Colors.white.withOpacity(0.05);

  static const List<Color> backgroundGradient = [
    Colors.black,
    Color(0xFF1A1A1A),
  ];

  static Color get cardBackground => Colors.grey.shade900.withOpacity(0.3);
  static Color get cardBorder => Colors.grey.shade800;
  static Color get profileBorder => Colors.black;
  static Color get videoBorder => Colors.white.withOpacity(0.2);

  static const Color sliderActive = Colors.amber;
  static const Color sliderInactive = Colors.white24;
  static const Color sliderThumb = Colors.white;

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
  static const Color primary = Colors.black;
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

  static const Color buttonPrimary = Colors.black;
  static const Color buttonSecondary = Colors.black12;
  static const Color buttonBorder = Colors.black26;

  static const Color border = Colors.black12;
  static const Color borderLight = Colors.black26;
  static const Color borderAccent = Colors.black38;
  static const Color divider = Colors.black12;

  static const Color overlay = Colors.white54;
  static const Color overlayLight = Colors.black12;
  static const Color overlayDark = Colors.white70;

  static const Color iconPrimary = Colors.black;
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

  static Color get backgroundTransparent => Colors.white.withOpacity(0.3);
  static Color get surfaceTransparent => Colors.transparent;
  static Color get overlayTransparent => Colors.white.withOpacity(0.7);
  static Color get borderTransparent => Colors.black.withOpacity(0.2);
  static Color get hoverTransparent => Colors.black.withOpacity(0.05);

  static const List<Color> backgroundGradient = [
    Colors.white,
    Color(0xFFF8F8F8),
  ];

  static Color get cardBackground => Colors.grey.shade100.withOpacity(0.5);
  static Color get cardBorder => Colors.grey.shade300;
  static Color get profileBorder => Colors.white;
  static Color get videoBorder => Colors.black.withOpacity(0.2);

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
