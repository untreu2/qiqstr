import 'dart:ui';
import '../../../core/bloc/base/base_event.dart';

abstract class LocaleEvent extends BaseEvent {
  const LocaleEvent();

  @override
  List<Object?> get props => [];
}

class LocaleInitialized extends LocaleEvent {
  const LocaleInitialized();
}

class LocaleChanged extends LocaleEvent {
  final Locale locale;

  const LocaleChanged(this.locale);

  @override
  List<Object?> get props => [locale];
}
