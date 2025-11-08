import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFFFFFFFF);
  static const Color primaryVariant = Color(0xFFE5E5E5);
  static const Color secondary = Color(0xFFB3B3B3);
  static const Color accent = Color.fromARGB(255, 222, 169, 54);

  static const Color background = Color(0xFF000000);
  static const Color backgroundElevated = Color(0xFF111111);
  static const Color surface = Color(0xFF000000);
  static const Color surfaceVariant = Color(0xFF141414);
  static const Color surfaceElevated = Color(0xFF1A1A1A);
  static const Color surfaceHighest = Color(0xFF242424);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFE0E0E0);
  static const Color textTertiary = Color(0xFFB3B3B3);
  static const Color textDisabled = Color(0xFF666666);
  static const Color textHint = Color(0xFF808080);
  static const Color textMuted = Color(0xFF999999);

  static const Color error = Color(0xFFFFFFFF);
  static const Color errorBackground = Color(0xFF333333);
  static const Color success = Color(0xFFFFFFFF);
  static const Color successBackground = Color(0xFF2A2A2A);
  static const Color warning = Color(0xFFE0E0E0);
  static const Color warningBackground = Color(0xFF1A1A1A);
  static const Color info = Color(0xFFCCCCCC);
  static const Color infoBackground = Color(0xFF0F0F0F);

  static const Color buttonPrimary = Color(0xFF333333);
  static const Color buttonPrimaryHover = Color(0xFF404040);
  static const Color buttonSecondary = Color(0xFF1A1A1A);
  static const Color buttonSecondaryHover = Color(0xFF2A2A2A);
  static const Color buttonText = Color(0xFFFFFFFF);
  static const Color buttonTextSecondary = Color(0xFFE0E0E0);
  static const Color buttonBorder = Color(0xFF666666);
  static const Color buttonDisabled = Color(0xFF1A1A1A);

  static const Color border = Color(0xFF333333);
  static const Color borderLight = Color(0xFF4D4D4D);
  static const Color borderAccent = Color(0xFF666666);
  static const Color borderFocused = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFF2A2A2A);
  static const Color dividerLight = Color(0xFF404040);

  static const Color overlay = Color(0x80000000);
  static const Color overlayLight = Color(0x1AFFFFFF);
  static const Color overlayDark = Color(0xCC000000);
  static const Color overlayGlass = Color(0x40111111);

  static const Color iconPrimary = Color(0xFFE0E0E0);
  static const Color iconSecondary = Color(0xFFB3B3B3);
  static const Color iconTertiary = Color(0xFF808080);
  static const Color iconDisabled = Color(0xFF4D4D4D);
  static const Color iconActive = Color(0xFFFFFFFF);

  static const Color reaction = Color(0xFFFF6B6B);
  static const Color reactionBackground = Color(0xFF2A2A2A);
  static const Color reply = Color(0xFF74C0FC);
  static const Color replyBackground = Color(0xFF1A1A1A);
  static const Color repost = Color(0xFF51CF66);
  static const Color repostBackground = Color(0xFF141414);
  static const Color zap = Color(0xFFECB200);
  static const Color zapBackground = Color(0xFF0F0F0F);

  static const Color avatarBackground = Color(0xFF2A2A2A);
  static const Color avatarPlaceholder = Color(0xFF666666);
  static const Color profileBadge = Color(0xFFFFFFFF);
  static const Color profileBorder = Color(0xFF404040);

  static const Color inputFill = Color(0xFF141414);
  static const Color inputBorder = Color(0xFF333333);
  static const Color inputFocused = Color(0xFFFFFFFF);
  static const Color inputLabel = Color(0xFFB3B3B3);
  static const Color inputPlaceholder = Color(0xFF808080);
  static const Color inputError = Color(0xFFFFFFFF);

  static const Color loading = Color(0xFFFFFFFF);
  static const Color loadingBackground = Color(0xFF2A2A2A);
  static const Color progressBar = Color(0xFFE0E0E0);
  static const Color progressBackground = Color(0xFF333333);

  static const Color notificationBackground = Color(0xFF1A1A1A);
  static const Color notificationBorder = Color(0xFF404040);
  static const Color notificationDot = Color(0xFFFFFFFF);

  static Color get backgroundTransparent => Color(0xFF000000).withValues(alpha: 0.85);
  static Color get surfaceTransparent => Color(0xFF0A0A0A).withValues(alpha: 0.9);
  static Color get overlayTransparent => Color(0xFF000000).withValues(alpha: 0.75);
  static Color get borderTransparent => Color(0xFFFFFFFF).withValues(alpha: 0.3);
  static Color get hoverTransparent => Color(0xFFFFFFFF).withValues(alpha: 0.1);
  static Color get focusTransparent => Color(0xFFFFFFFF).withValues(alpha: 0.2);
  static Color get pressedTransparent => Color(0xFFFFFFFF).withValues(alpha: 0.15);

  static const List<Color> backgroundGradient = [
    Color(0xFF000000),
    Color(0xFF0A0A0A),
    Color(0xFF000000),
  ];

  static const List<Color> primaryGradient = [
    Color(0xFFFFFFFF),
    Color(0xFFE0E0E0),
  ];

  static const List<Color> accentGradient = [
    Color(0xFFE0E0E0),
    Color(0xFFB3B3B3),
  ];

  static Color get cardBackground => Color(0xFF141414);
  static Color get cardBackgroundElevated => Color(0xFF1A1A1A);
  static Color get cardBorder => Color(0xFF333333);
  static Color get cardShadow => Color(0xFF000000).withValues(alpha: 0.5);
  static Color get videoBorder => Color(0xFFFFFFFF).withValues(alpha: 0.3);

  static const Color sliderActive = Color(0xFFFFFFFF);
  static const Color sliderInactive = Color(0xFF404040);
  static const Color sliderThumb = Color(0xFFFFFFFF);
  static const Color sliderTrack = Color(0xFF2A2A2A);

  static Color get glassBackground => Color(0xFF0A0A0A).withValues(alpha: 0.7);
  static Color get glassBorder => Color(0xFFFFFFFF).withValues(alpha: 0.2);

  static Color get grey50 => Color(0xFFF5F5F5);
  static Color get grey100 => Color(0xFFEBEBEB);
  static Color get grey200 => Color(0xFFE0E0E0);
  static Color get grey300 => Color(0xFFCCCCCC);
  static Color get grey400 => Color(0xFFB3B3B3);
  static Color get grey500 => Color(0xFF999999);
  static Color get grey600 => Color(0xFF808080);
  static Color get grey700 => Color(0xFF666666);
  static Color get grey800 => Color(0xFF4D4D4D);
  static Color get grey900 => Color(0xFF333333);

  static Color get red400 => Color(0xFFE0E0E0);
  static Color get red500 => Color(0xFFCCCCCC);
  static Color get red600 => Color(0xFFB3B3B3);

  static Color get blue400 => Color(0xFFE0E0E0);
  static Color get blue500 => Color(0xFFCCCCCC);
  static Color get blue600 => Color(0xFFB3B3B3);

  static Color get green400 => Color(0xFFE0E0E0);
  static Color get green500 => Color(0xFFCCCCCC);
  static Color get green600 => Color(0xFFB3B3B3);

  static Color get purple400 => Color(0xFFE0E0E0);
  static Color get purple500 => Color(0xFFCCCCCC);
  static Color get purple600 => Color(0xFFB3B3B3);

  static Color get amber400 => Color(0xFFE0E0E0);
  static Color get amber500 => Color(0xFFCCCCCC);
  static Color get amber600 => Color(0xFFB3B3B3);
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
