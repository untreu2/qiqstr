import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'locale_event.dart';
import 'locale_state.dart';

class LocaleBloc extends Bloc<LocaleEvent, LocaleState> {
  static const String _localeKey = 'app_locale';

  LocaleBloc() : super(const LocaleState()) {
    on<LocaleInitialized>(_onInitialized);
    on<LocaleChanged>(_onLocaleChanged);
  }

  Future<void> _onInitialized(
      LocaleInitialized event, Emitter<LocaleState> emit) async {
    final prefs = await SharedPreferences.getInstance();
    final localeCode = prefs.getString(_localeKey);

    if (localeCode != null) {
      emit(LocaleState(locale: Locale(localeCode)));
    }
  }

  Future<void> _onLocaleChanged(
      LocaleChanged event, Emitter<LocaleState> emit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, event.locale.languageCode);
    emit(LocaleState(locale: event.locale));
  }
}
