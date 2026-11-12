import 'dart:ui';
import '../../../core/bloc/base/base_state.dart';

class LocaleState extends BaseState {
  final Locale locale;

  const LocaleState({this.locale = const Locale('en')});

  LocaleState copyWith({Locale? locale}) {
    return LocaleState(locale: locale ?? this.locale);
  }

  @override
  List<Object?> get props => [locale];
}
