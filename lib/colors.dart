import 'package:flutter/material.dart';

/// Centralized color definitions for the application
class AppColors {
  // Primary colors
  static const Color primary = Colors.white;
  static const Color secondary = Colors.grey;
  static const Color accent = Color(0xFFECB200); // Golden yellow for links, hashtags, etc.
  
  // Background colors
  static const Color background = Colors.black;
  static const Color surface = Colors.black;
  static const Color surfaceVariant = Color(0xFF1E1E1E);
  
  // Text colors
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Colors.white70;
  static const Color textTertiary = Colors.white54;
  static const Color textDisabled = Colors.white38;
  static const Color textHint = Colors.white54;
  
  // Interactive colors
  static const Color error = Colors.redAccent;
  static const Color success = Colors.greenAccent;
  static const Color warning = Colors.amber;
  
  // Button colors
  static const Color buttonPrimary = Colors.white;
  static const Color buttonSecondary = Colors.white10;
  static const Color buttonBorder = Colors.white30;
  
  // Border and divider colors
  static const Color border = Colors.white12;
  static const Color borderLight = Colors.white24;
  static const Color borderAccent = Colors.white30;
  static const Color divider = Colors.white12;
  
  // Overlay colors
  static const Color overlay = Colors.black54;
  static const Color overlayLight = Colors.white10;
  static const Color overlayDark = Colors.black87;
  
  // Icon colors
  static const Color iconPrimary = Colors.white;
  static const Color iconSecondary = Colors.white70;
  static const Color iconDisabled = Colors.white38;
  
  // Interaction specific colors
  static const Color reaction = Color(0xFFFF6B6B); // Red for reactions
  static const Color reply = Color(0xFF74C0FC); // Blue for replies  
  static const Color repost = Color(0xFF51CF66); // Green for reposts
  static const Color zap = Color(0xFFECB200); // Golden for zaps
  
  // Profile and avatar colors
  static const Color avatarBackground = Colors.grey;
  static const Color avatarPlaceholder = Colors.white24;
  
  // Input field colors
  static const Color inputFill = Colors.white10;
  static const Color inputBorder = Colors.white24;
  static const Color inputFocused = Colors.white;
  static const Color inputLabel = Colors.white70;
  
  // Loading and progress colors
  static const Color loading = Colors.white;
  static const Color loadingBackground = Colors.white38;
  
  // Notification colors
  static const Color notificationBackground = Colors.grey;
  
  // Transparent variations
  static Color get backgroundTransparent => Colors.black.withOpacity(0.3);
  static Color get surfaceTransparent => Colors.transparent;
  static Color get overlayTransparent => Colors.black.withOpacity(0.7);
  static Color get borderTransparent => Colors.white.withOpacity(0.2);
  static Color get hoverTransparent => Colors.white.withOpacity(0.05);
  
  // Gradient colors
  static const List<Color> backgroundGradient = [
    Colors.black,
    Color(0xFF1A1A1A),
  ];
  
  // Specific component colors
  static Color get cardBackground => Colors.grey.shade900.withOpacity(0.3);
  static Color get cardBorder => Colors.grey.shade800;
  static Color get profileBorder => Colors.black;
  static Color get videoBorder => Colors.white.withOpacity(0.2);
  
  // Slider colors
  static const Color sliderActive = Colors.amber;
  static const Color sliderInactive = Colors.white24;
  static const Color sliderThumb = Colors.white;
  
  // Glass morphism colors
  static const Color glassBackground = Color(0xFF000000);
  
  // Specific shade variations
  static Color get grey600 => Colors.grey.shade600;
  static Color get grey700 => Colors.grey.shade700;
  static Color get grey800 => Colors.grey.shade800;
  static Color get grey900 => Colors.grey.shade900;
  
  // Red variations
  static Color get red400 => Colors.red.shade400;
  
  // Blue variations  
  static Color get blue200 => Colors.blue.shade200;
  
  // Green variations
  static Color get green400 => Colors.green.shade400;
}