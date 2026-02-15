import '../../../core/bloc/base/base_event.dart';

abstract class ThemeEvent extends BaseEvent {
  const ThemeEvent();
}

class ThemeInitialized extends ThemeEvent {
  const ThemeInitialized();
}

class ThemeToggled extends ThemeEvent {
  const ThemeToggled();
}

class ThemeSetDark extends ThemeEvent {
  final bool isDark;

  const ThemeSetDark(this.isDark);

  @override
  List<Object?> get props => [isDark];
}

class ThemeSetSystem extends ThemeEvent {
  const ThemeSetSystem();
}

class ExpandedNoteModeToggled extends ThemeEvent {
  const ExpandedNoteModeToggled();
}

class ExpandedNoteModeSet extends ThemeEvent {
  final bool isExpanded;

  const ExpandedNoteModeSet(this.isExpanded);

  @override
  List<Object?> get props => [isExpanded];
}

class BottomNavOrderSet extends ThemeEvent {
  final List<int> order;

  const BottomNavOrderSet(this.order);

  @override
  List<Object?> get props => [order];
}

class OneTapZapSet extends ThemeEvent {
  final bool enabled;

  const OneTapZapSet(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

class DefaultZapAmountSet extends ThemeEvent {
  final int amount;

  const DefaultZapAmountSet(this.amount);

  @override
  List<Object?> get props => [amount];
}

