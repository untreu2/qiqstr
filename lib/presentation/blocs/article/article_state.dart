import '../../../core/bloc/base/base_state.dart';

abstract class ArticleState extends BaseState {
  const ArticleState();
}

class ArticleInitial extends ArticleState {
  const ArticleInitial();
}

class ArticleLoading extends ArticleState {
  const ArticleLoading();
}

class ArticleLoaded extends ArticleState {
  final List<Map<String, dynamic>> articles;
  final List<Map<String, dynamic>> filteredArticles;
  final Map<String, Map<String, dynamic>> profiles;
  final String currentUserNpub;
  final bool canLoadMore;
  final bool isLoadingMore;
  final String searchQuery;

  const ArticleLoaded({
    required this.articles,
    required this.filteredArticles,
    required this.profiles,
    required this.currentUserNpub,
    this.canLoadMore = true,
    this.isLoadingMore = false,
    this.searchQuery = '',
  });

  @override
  List<Object?> get props => [
        articles,
        filteredArticles,
        profiles,
        currentUserNpub,
        canLoadMore,
        isLoadingMore,
        searchQuery,
      ];

  ArticleLoaded copyWith({
    List<Map<String, dynamic>>? articles,
    List<Map<String, dynamic>>? filteredArticles,
    Map<String, Map<String, dynamic>>? profiles,
    String? currentUserNpub,
    bool? canLoadMore,
    bool? isLoadingMore,
    String? searchQuery,
  }) {
    return ArticleLoaded(
      articles: articles ?? this.articles,
      filteredArticles: filteredArticles ?? this.filteredArticles,
      profiles: profiles ?? this.profiles,
      currentUserNpub: currentUserNpub ?? this.currentUserNpub,
      canLoadMore: canLoadMore ?? this.canLoadMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class ArticleError extends ArticleState {
  final String message;

  const ArticleError(this.message);

  @override
  List<Object?> get props => [message];
}

class ArticleEmpty extends ArticleState {
  const ArticleEmpty();
}
