import 'package:flutter/material.dart';
import '../../../core/bloc/base/base_state.dart';
import '../../../ui/theme/theme_manager.dart';

class ThemeState extends BaseState {
  final bool? isDarkModeOverride;
  final bool isExpandedNoteMode;
  final List<int> bottomNavOrder;
  final bool oneTapZap;
  final int defaultZapAmount;

  const ThemeState({
    this.isDarkModeOverride,
    this.isExpandedNoteMode = false,
    this.bottomNavOrder = const [0, 1, 2, 3],
    this.oneTapZap = false,
    this.defaultZapAmount = 21,
  });

  bool get isDarkMode {
    if (isDarkModeOverride != null) {
      return isDarkModeOverride!;
    }
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark;
  }

  bool get isSystemTheme => isDarkModeOverride == null;

  AppThemeColors get colors =>
      isDarkMode ? AppThemeColors.dark() : AppThemeColors.light();

  ThemeState copyWith({
    bool? isDarkModeOverride,
    bool clearDarkModeOverride = false,
    bool? isExpandedNoteMode,
    List<int>? bottomNavOrder,
    bool? oneTapZap,
    int? defaultZapAmount,
  }) {
    return ThemeState(
      isDarkModeOverride: clearDarkModeOverride
          ? null
          : (isDarkModeOverride ?? this.isDarkModeOverride),
      isExpandedNoteMode: isExpandedNoteMode ?? this.isExpandedNoteMode,
      bottomNavOrder: bottomNavOrder ?? this.bottomNavOrder,
      oneTapZap: oneTapZap ?? this.oneTapZap,
      defaultZapAmount: defaultZapAmount ?? this.defaultZapAmount,
    );
  }

  @override
  List<Object?> get props => [
        isDarkModeOverride,
        isExpandedNoteMode,
        bottomNavOrder,
        oneTapZap,
        defaultZapAmount,
      ];
}
