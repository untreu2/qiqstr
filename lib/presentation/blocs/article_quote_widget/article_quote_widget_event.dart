import '../../../core/bloc/base/base_event.dart';

abstract class ArticleQuoteWidgetEvent extends BaseEvent {
  const ArticleQuoteWidgetEvent();
}

class ArticleQuoteWidgetLoadRequested extends ArticleQuoteWidgetEvent {
  final String naddr;

  const ArticleQuoteWidgetLoadRequested({required this.naddr});

  @override
  List<Object?> get props => [naddr];
}
