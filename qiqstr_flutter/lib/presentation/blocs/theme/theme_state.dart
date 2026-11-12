import '../../../core/bloc/base/base_state.dart';

class ThemeState extends BaseState {
  final bool? isDarkModeOverride;
  final bool systemIsDark;
  final bool isExpandedNoteMode;
  final List<int> bottomNavOrder;
  final bool oneTapZap;
  final int defaultZapAmount;

  const ThemeState({
    this.isDarkModeOverride,
    this.systemIsDark = false,
    this.isExpandedNoteMode = false,
    this.bottomNavOrder = const [0, 1, 2, 3],
    this.oneTapZap = false,
    this.defaultZapAmount = 21,
  });

  bool get isDarkMode => isDarkModeOverride ?? systemIsDark;

  bool get isSystemTheme => isDarkModeOverride == null;

  ThemeState copyWith({
    bool? isDarkModeOverride,
    bool? systemIsDark,
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
      systemIsDark: systemIsDark ?? this.systemIsDark,
      isExpandedNoteMode: isExpandedNoteMode ?? this.isExpandedNoteMode,
      bottomNavOrder: bottomNavOrder ?? this.bottomNavOrder,
      oneTapZap: oneTapZap ?? this.oneTapZap,
      defaultZapAmount: defaultZapAmount ?? this.defaultZapAmount,
    );
  }

  @override
  List<Object?> get props => [
    isDarkModeOverride,
    systemIsDark,
    isExpandedNoteMode,
    bottomNavOrder,
    oneTapZap,
    defaultZapAmount,
  ];
}
