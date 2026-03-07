import '../../../core/bloc/base/base_state.dart';
import '../../../domain/entities/article.dart';

abstract class ArticleQuoteWidgetState extends BaseState {
  const ArticleQuoteWidgetState();
}

class ArticleQuoteWidgetInitial extends ArticleQuoteWidgetState {
  const ArticleQuoteWidgetInitial();
}

class ArticleQuoteWidgetLoading extends ArticleQuoteWidgetState {
  const ArticleQuoteWidgetLoading();
}

class ArticleQuoteWidgetLoaded extends ArticleQuoteWidgetState {
  final Article article;

  const ArticleQuoteWidgetLoaded({required this.article});

  @override
  List<Object?> get props => [article];
}

class ArticleQuoteWidgetError extends ArticleQuoteWidgetState {
  const ArticleQuoteWidgetError();
}
