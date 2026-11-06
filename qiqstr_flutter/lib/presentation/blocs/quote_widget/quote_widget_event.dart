import '../../../core/bloc/base/base_event.dart';

abstract class QuoteWidgetEvent extends BaseEvent {
  const QuoteWidgetEvent();
}

class QuoteWidgetLoadRequested extends QuoteWidgetEvent {
  final String bech32;

  const QuoteWidgetLoadRequested({required this.bech32});

  @override
  List<Object?> get props => [bech32];
}
