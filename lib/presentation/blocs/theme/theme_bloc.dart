import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_event.dart';
import 'theme_state.dart';

class ThemeBloc extends Bloc<ThemeEvent, ThemeState> {
  static const String _themeKey = 'theme_mode';
  static const String _expandedNoteModeKey = 'expanded_note_mode';
  static const String _bottomNavOrderKey = 'bottom_nav_order';
  static const String _oneTapZapKey = 'one_tap_zap';
  static const String _defaultZapAmountKey = 'default_zap_amount';

  ThemeBloc() : super(const ThemeState()) {
    on<ThemeInitialized>(_onInitialized);
    on<ThemeToggled>(_onToggled);
    on<ThemeSetDark>(_onSetDark);
    on<ThemeSetSystem>(_onSetSystem);
    on<ExpandedNoteModeToggled>(_onExpandedNoteModeToggled);
    on<ExpandedNoteModeSet>(_onExpandedNoteModeSet);
    on<BottomNavOrderSet>(_onBottomNavOrderSet);
    on<OneTapZapSet>(_onOneTapZapSet);
    on<DefaultZapAmountSet>(_onDefaultZapAmountSet);
  }

  Future<void> _onInitialized(
      ThemeInitialized event, Emitter<ThemeState> emit) async {
    final prefs = await SharedPreferences.getInstance();

    bool? isDarkModeOverride;
    if (prefs.containsKey(_themeKey)) {
      isDarkModeOverride = prefs.getBool(_themeKey);
    }

    final isExpandedNoteMode = prefs.getBool(_expandedNoteModeKey) ?? false;

    List<int> bottomNavOrder = [0, 1, 2, 3];
    final orderList = prefs.getStringList(_bottomNavOrderKey);
    if (orderList != null && orderList.length == 4) {
      bottomNavOrder = orderList.map((e) => int.parse(e)).toList();
    }

    final oneTapZap = prefs.getBool(_oneTapZapKey) ?? false;
    final defaultZapAmount = prefs.getInt(_defaultZapAmountKey) ?? 21;

    emit(ThemeState(
      isDarkModeOverride: isDarkModeOverride,
      isExpandedNoteMode: isExpandedNoteMode,
      bottomNavOrder: bottomNavOrder,
      oneTapZap: oneTapZap,
      defaultZapAmount: defaultZapAmount,
    ));
  }

  Future<void> _onToggled(ThemeToggled event, Emitter<ThemeState> emit) async {
    bool newDarkMode;
    if (state.isDarkModeOverride == null) {
      final brightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      newDarkMode = brightness == Brightness.light;
    } else {
      newDarkMode = !state.isDarkModeOverride!;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeKey, newDarkMode);

    emit(state.copyWith(isDarkModeOverride: newDarkMode));
  }

  Future<void> _onSetDark(ThemeSetDark event, Emitter<ThemeState> emit) async {
    if (state.isDarkModeOverride != event.isDark) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_themeKey, event.isDark);
      emit(state.copyWith(isDarkModeOverride: event.isDark));
    }
  }

  Future<void> _onSetSystem(
      ThemeSetSystem event, Emitter<ThemeState> emit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_themeKey);
    emit(state.copyWith(clearDarkModeOverride: true));
  }

  Future<void> _onExpandedNoteModeToggled(
      ExpandedNoteModeToggled event, Emitter<ThemeState> emit) async {
    final newValue = !state.isExpandedNoteMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_expandedNoteModeKey, newValue);
    emit(state.copyWith(isExpandedNoteMode: newValue));
  }

  Future<void> _onExpandedNoteModeSet(
      ExpandedNoteModeSet event, Emitter<ThemeState> emit) async {
    if (state.isExpandedNoteMode != event.isExpanded) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_expandedNoteModeKey, event.isExpanded);
      emit(state.copyWith(isExpandedNoteMode: event.isExpanded));
    }
  }

  Future<void> _onBottomNavOrderSet(
      BottomNavOrderSet event, Emitter<ThemeState> emit) async {
    if (event.order.length == 4 && event.order.toSet().length == 4) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _bottomNavOrderKey, event.order.map((e) => e.toString()).toList());
      emit(state.copyWith(bottomNavOrder: List.from(event.order)));
    }
  }

  Future<void> _onOneTapZapSet(
      OneTapZapSet event, Emitter<ThemeState> emit) async {
    if (state.oneTapZap != event.enabled) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_oneTapZapKey, event.enabled);
      emit(state.copyWith(oneTapZap: event.enabled));
    }
  }

  Future<void> _onDefaultZapAmountSet(
      DefaultZapAmountSet event, Emitter<ThemeState> emit) async {
    if (event.amount > 0 && state.defaultZapAmount != event.amount) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_defaultZapAmountKey, event.amount);
      emit(state.copyWith(defaultZapAmount: event.amount));
    }
  }

}
