import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/feed_loader_service.dart';
import 'article_event.dart';
import 'article_state.dart';

class ArticleBloc extends Bloc<ArticleEvent, ArticleState> {
  final AuthRepository _authRepository;
  final UserRepository _userRepository;
  final FeedLoaderService _feedLoader;

  static const int _pageSize = 50;
  bool _isLoadingArticles = false;
  final List<StreamSubscription> _subscriptions = [];

  ArticleBloc({
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required FeedLoaderService feedLoader,
  })  : _authRepository = authRepository,
        _userRepository = userRepository,
        _feedLoader = feedLoader,
        super(const ArticleInitial()) {
    on<ArticleInitialized>(_onArticleInitialized);
    on<ArticleRefreshed>(_onArticleRefreshed);
    on<ArticleLoadMoreRequested>(_onArticleLoadMoreRequested);
    on<ArticleSearchQueryChanged>(_onArticleSearchQueryChanged);
    on<ArticleUserProfileUpdated>(_onArticleUserProfileUpdated);
  }

  Future<void> _onArticleInitialized(
    ArticleInitialized event,
    Emitter<ArticleState> emit,
  ) async {
    final currentUserHex = _authRepository.npubToHex(event.npub);
    if (currentUserHex == null) {
      emit(const ArticleError('Could not convert npub to hex'));
      return;
    }

    final initialState = ArticleLoaded(
      articles: const [],
      filteredArticles: const [],
      profiles: const {},
      currentUserNpub: event.npub,
    );
    emit(initialState);

    await _loadArticlesFromCache(emit, event.npub);

    await _loadArticlesFromNetwork(emit, event.npub);
    await _loadCurrentUserProfile(emit, event.npub);
  }

  Future<void> _onArticleRefreshed(
    ArticleRefreshed event,
    Emitter<ArticleState> emit,
  ) async {
    if (state is! ArticleLoaded) return;

    final currentState = state as ArticleLoaded;
    if (_isLoadingArticles) return;

    await _loadArticlesFromNetwork(emit, currentState.currentUserNpub);
    _loadCurrentUserProfile(emit, currentState.currentUserNpub);
  }

  Future<void> _onArticleLoadMoreRequested(
    ArticleLoadMoreRequested event,
    Emitter<ArticleState> emit,
  ) async {
    if (state is! ArticleLoaded) return;

    final currentState = state as ArticleLoaded;
    if (_isLoadingArticles || currentState.isLoadingMore || !currentState.canLoadMore) return;

    emit(currentState.copyWith(isLoadingMore: true));

    final currentArticles = currentState.articles;
    if (currentArticles.isEmpty) {
      emit(currentState.copyWith(isLoadingMore: false));
      return;
    }

    final oldestArticle = currentArticles.reduce((a, b) {
      final aTimestamp = a['timestamp'] as DateTime? ?? DateTime(2000);
      final bTimestamp = b['timestamp'] as DateTime? ?? DateTime(2000);
      return aTimestamp.isBefore(bTimestamp) ? a : b;
    });

    final oldestTimestamp = oldestArticle['timestamp'] as DateTime? ?? DateTime(2000);
    final until = oldestTimestamp.subtract(const Duration(milliseconds: 100));

    final params = FeedLoadParams(
      type: FeedType.article,
      currentUserNpub: currentState.currentUserNpub,
      limit: _pageSize,
      until: until,
      skipCache: true,
    );

    final result = await _feedLoader.loadFeed(params);

    if (result.isSuccess && result.notes.isNotEmpty) {
      final currentIds = currentArticles.map((a) => a['id'] as String? ?? '').where((id) => id.isNotEmpty).toSet();
      final uniqueNewArticles = result.notes.where((a) {
        final articleId = a['id'] as String? ?? '';
        return articleId.isNotEmpty && !currentIds.contains(articleId);
      }).toList();

      if (uniqueNewArticles.isNotEmpty) {
        final updatedArticles = [...currentArticles, ...uniqueNewArticles];
        final sortedArticles = _feedLoader.sortNotes(updatedArticles, FeedSortMode.latest);
        final filteredArticles = _filterArticles(sortedArticles, currentState.searchQuery);

        emit(currentState.copyWith(
          articles: sortedArticles,
          filteredArticles: filteredArticles,
          isLoadingMore: false,
        ));

        _feedLoader.loadProfilesAndInteractionsForNotes(
          uniqueNewArticles,
          Map.from(currentState.profiles),
          (profiles) {
            if (state is ArticleLoaded) {
              final updatedState = state as ArticleLoaded;
              emit(updatedState.copyWith(profiles: profiles));
            }
          },
        );
      } else {
        emit(currentState.copyWith(isLoadingMore: false));
      }
    } else {
      emit(currentState.copyWith(isLoadingMore: false));
    }
  }

  void _onArticleSearchQueryChanged(
    ArticleSearchQueryChanged event,
    Emitter<ArticleState> emit,
  ) {
    if (state is! ArticleLoaded) return;

    final currentState = state as ArticleLoaded;
    final query = event.query.trim().toLowerCase();

    final filteredArticles = _filterArticles(currentState.articles, query);

    emit(currentState.copyWith(
      searchQuery: query,
      filteredArticles: filteredArticles,
    ));
  }

  List<Map<String, dynamic>> _filterArticles(List<Map<String, dynamic>> articles, String query) {
    if (query.isEmpty) {
      return articles;
    }

    return articles.where((article) {
      final title = (article['title'] as String? ?? '').toLowerCase();
      final summary = (article['summary'] as String? ?? '').toLowerCase();
      final author = (article['author'] as String? ?? '').toLowerCase();
      final content = (article['content'] as String? ?? '').toLowerCase();
      final tTags = (article['tTags'] as List<dynamic>? ?? [])
          .map((tag) => tag.toString().toLowerCase())
          .toList();

      return title.contains(query) ||
          summary.contains(query) ||
          author.contains(query) ||
          content.contains(query) ||
          tTags.any((tag) => tag.contains(query));
    }).toList();
  }

  void _onArticleUserProfileUpdated(
    ArticleUserProfileUpdated event,
    Emitter<ArticleState> emit,
  ) {
    if (state is ArticleLoaded) {
      final currentState = state as ArticleLoaded;
      final updatedProfiles = Map<String, Map<String, dynamic>>.from(currentState.profiles);
      final existingProfile = updatedProfiles[event.userId];
      final existingImage = existingProfile?['profileImage'] as String? ?? '';
      if (!updatedProfiles.containsKey(event.userId) || existingImage.isEmpty) {
        updatedProfiles[event.userId] = event.user;
        emit(currentState.copyWith(profiles: updatedProfiles));
      }
    }
  }

  Future<void> _loadArticlesFromCache(
    Emitter<ArticleState> emit,
    String npub,
  ) async {
    try {
      final params = FeedLoadParams(
        type: FeedType.article,
        currentUserNpub: npub,
        limit: _pageSize,
        cacheOnly: true,
      );

      final result = await _feedLoader.loadFeed(params);

      if (result.isSuccess && result.notes.isNotEmpty) {
        final sortedArticles = _feedLoader.sortNotes(result.notes, FeedSortMode.latest);
        final existingState = state is ArticleLoaded ? (state as ArticleLoaded) : null;

        emit(ArticleLoaded(
          articles: sortedArticles,
          filteredArticles: sortedArticles,
          profiles: existingState?.profiles ?? const {},
          currentUserNpub: npub,
        ));

        _feedLoader.loadProfilesAndInteractionsForNotes(
          sortedArticles,
          existingState?.profiles ?? const {},
          (profiles) {
            if (state is ArticleLoaded) {
              final updatedState = state as ArticleLoaded;
              emit(updatedState.copyWith(profiles: profiles));
            }
          },
        );
      }
    } catch (e) {
      // Silently fail cache load, network will handle it
    }
  }

  Future<void> _loadArticlesFromNetwork(
    Emitter<ArticleState> emit,
    String npub,
  ) async {
    if (_isLoadingArticles) return;

    _isLoadingArticles = true;

    try {
      final params = FeedLoadParams(
        type: FeedType.article,
        currentUserNpub: npub,
        limit: _pageSize,
        skipCache: true,
        cacheOnly: false,
      );

      final result = await _feedLoader.loadFeed(params);

      if (result.isSuccess && result.notes.isNotEmpty) {
        final sortedArticles = _feedLoader.sortNotes(result.notes, FeedSortMode.latest);
        final existingState = state is ArticleLoaded ? (state as ArticleLoaded) : null;
        final searchQuery = existingState?.searchQuery ?? '';

        final currentArticles = existingState?.articles ?? [];
        final mergedArticles = _feedLoader.mergeNotesWithUpdates(
          currentArticles,
          sortedArticles,
          FeedSortMode.latest,
        );

        final finalArticles = mergedArticles.length >= currentArticles.length ? mergedArticles : currentArticles;
        final filteredArticles = _filterArticles(finalArticles, searchQuery);

        emit(ArticleLoaded(
          articles: finalArticles,
          filteredArticles: filteredArticles,
          profiles: existingState?.profiles ?? const {},
          currentUserNpub: npub,
          searchQuery: searchQuery,
        ));

        _feedLoader.loadProfilesAndInteractionsForNotes(
          finalArticles,
          existingState?.profiles ?? const {},
          (profiles) {
            if (state is ArticleLoaded) {
              final updatedState = state as ArticleLoaded;
              emit(updatedState.copyWith(profiles: profiles));
            }
          },
        );
      }
    } catch (e) {
      // Network errors are non-fatal if we have cached data
    } finally {
      _isLoadingArticles = false;
    }
  }

  Future<void> _loadCurrentUserProfile(Emitter<ArticleState> emit, String npub) async {
    if (state is! ArticleLoaded) return;

    final currentState = state as ArticleLoaded;
    if (currentState.profiles.containsKey(npub)) {
      final existingUser = currentState.profiles[npub];
      final existingImage = existingUser?['profileImage'] as String? ?? '';
      if (existingUser != null && existingImage.isNotEmpty) {
        return;
      }
    }

    final userResult = await _userRepository.getUserProfile(npub);
    userResult.fold(
      (user) {
        if (state is ArticleLoaded) {
          final updatedState = state as ArticleLoaded;
          final updatedProfiles = Map<String, Map<String, dynamic>>.from(updatedState.profiles);
          updatedProfiles[npub] = user;
          emit(updatedState.copyWith(profiles: updatedProfiles));
        }
      },
      (error) {},
    );
  }

  @override
  Future<void> close() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    return super.close();
  }
}
