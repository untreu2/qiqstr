import '../../../core/bloc/base/base_event.dart';

abstract class ArticleEvent extends BaseEvent {
  const ArticleEvent();
}

class ArticleInitialized extends ArticleEvent {
  final String npub;

  const ArticleInitialized({required this.npub});

  @override
  List<Object?> get props => [npub];
}

class ArticleRefreshed extends ArticleEvent {
  const ArticleRefreshed();
}

class ArticleLoadMoreRequested extends ArticleEvent {
  const ArticleLoadMoreRequested();
}

class ArticleSearchQueryChanged extends ArticleEvent {
  final String query;

  const ArticleSearchQueryChanged(this.query);

  @override
  List<Object?> get props => [query];
}

class ArticleUserProfileUpdated extends ArticleEvent {
  final String userId;
  final Map<String, dynamic> user;

  const ArticleUserProfileUpdated(this.userId, this.user);

  @override
  List<Object?> get props => [userId, user];
}
