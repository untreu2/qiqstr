import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/article_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/sync/sync_service.dart';
import 'article_event.dart';
import 'article_state.dart';

class _InternalArticlesUpdate extends ArticleEvent {
  final List<Map<String, dynamic>> articles;
  const _InternalArticlesUpdate(this.articles);

  @override
  List<Object?> get props => [articles];
}

class _InternalProfilesUpdate extends ArticleEvent {
  final Map<String, Map<String, dynamic>> profiles;
  const _InternalProfilesUpdate(this.profiles);

  @override
  List<Object?> get props => [profiles];
}

class ArticleBloc extends Bloc<ArticleEvent, ArticleState> {
  final ArticleRepository _articleRepository;
  final ProfileRepository _profileRepository;
  final FollowingRepository _followingRepository;
  final SyncService _syncService;

  static const int _pageSize = 50;
  StreamSubscription<List<Map<String, dynamic>>>? _articlesSubscription;
  String _currentUserHex = '';
  List<String>? _followingList;
  bool _initialSyncDone = false;

  ArticleBloc({
    required ArticleRepository articleRepository,
    required ProfileRepository profileRepository,
    required FollowingRepository followingRepository,
    required SyncService syncService,
  })  : _articleRepository = articleRepository,
        _profileRepository = profileRepository,
        _followingRepository = followingRepository,
        _syncService = syncService,
        super(const ArticleInitial()) {
    on<ArticleInitialized>(_onArticleInitialized);
    on<ArticleRefreshed>(_onArticleRefreshed);
    on<ArticleLoadMoreRequested>(_onArticleLoadMoreRequested);
    on<ArticleSearchQueryChanged>(_onArticleSearchQueryChanged);
    on<ArticleUserProfileUpdated>(_onArticleUserProfileUpdated);
    on<_InternalArticlesUpdate>(_onInternalArticlesUpdate);
    on<_InternalProfilesUpdate>(_onInternalProfilesUpdate);
  }

  Future<void> _onArticleInitialized(
    ArticleInitialized event,
    Emitter<ArticleState> emit,
  ) async {
    _currentUserHex = event.userHex;
    emit(const ArticleLoading());

    _followingList = await _followingRepository.getFollowing(_currentUserHex);

    final cached = await _articleRepository.getArticles(
      limit: _pageSize,
      authors: _followingList,
    );
    if (!isClosed && cached.isNotEmpty) {
      final articleMaps = cached.map((a) => a.toMap()).toList();
      articleMaps.sort((a, b) {
        final aTime = a['created_at'] as int? ?? 0;
        final bTime = b['created_at'] as int? ?? 0;
        return bTime.compareTo(aTime);
      });
      if (articleMaps.isNotEmpty) {
        emit(ArticleLoaded(
          articles: articleMaps,
          filteredArticles: articleMaps,
          profiles: const {},
          currentUserHex: _currentUserHex,
        ));
        _loadAuthorProfilesInBackground(articleMaps);
      }
    }

    _watchArticles();

    Future.microtask(() async {
      if (isClosed) return;
      try {
        await _syncService.syncArticles(
          authors: _followingList,
          limit: _pageSize,
        );
      } catch (_) {}
      _initialSyncDone = true;
      if (!isClosed && state is ArticleLoading) {
        final articles = await _articleRepository.getArticles(
          limit: _pageSize,
          authors: _followingList,
        );
        if (articles.isEmpty) {
          add(_InternalArticlesUpdate(const []));
        }
      }
    });
  }

  void _watchArticles() {
    _articlesSubscription?.cancel();
    _articlesSubscription = _articleRepository
        .watchArticles(limit: _pageSize, authors: _followingList)
        .map((articles) => articles.map((a) => a.toMap()).toList())
        .listen((maps) {
      if (isClosed) return;

      final articleMaps = maps;

      articleMaps.sort((a, b) {
        final aTime = a['created_at'] as int? ?? 0;
        final bTime = b['created_at'] as int? ?? 0;
        return bTime.compareTo(aTime);
      });

      add(_InternalArticlesUpdate(articleMaps));
      _loadAuthorProfilesInBackground(articleMaps);
    });
  }

  void _loadAuthorProfilesInBackground(List<Map<String, dynamic>> articles) {
    Future.microtask(() async {
      if (isClosed) return;

      final pubkeys = articles
          .map((a) => a['pubkey'] as String?)
          .where((p) => p != null && p.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList();

      if (pubkeys.isEmpty) return;

      try {
        final profiles = await _profileRepository.getProfiles(pubkeys);

        if (isClosed) return;

        final profileMaps = <String, Map<String, dynamic>>{};
        for (final entry in profiles.entries) {
          profileMaps[entry.key] = entry.value.toMap();
        }

        add(_InternalProfilesUpdate(profileMaps));
      } catch (_) {}
    });
  }

  void _onInternalArticlesUpdate(
    _InternalArticlesUpdate event,
    Emitter<ArticleState> emit,
  ) {
    final articles = event.articles;

    if (articles.isEmpty) {
      if (state is ArticleLoaded) return;
      if (!_initialSyncDone) return;
      emit(const ArticleEmpty());
      return;
    }

    final currentState = state;
    final currentProfiles = currentState is ArticleLoaded
        ? currentState.profiles
        : <String, Map<String, dynamic>>{};
    final searchQuery =
        currentState is ArticleLoaded ? currentState.searchQuery : '';

    final articlesWithAuthors =
        _enrichArticlesWithProfiles(articles, currentProfiles);
    final filteredArticles = _filterArticles(articlesWithAuthors, searchQuery);

    emit(ArticleLoaded(
      articles: articlesWithAuthors,
      filteredArticles: filteredArticles,
      profiles: currentProfiles,
      currentUserHex: _currentUserHex,
    ));
  }

  void _onInternalProfilesUpdate(
    _InternalProfilesUpdate event,
    Emitter<ArticleState> emit,
  ) {
    final currentState = state;
    if (currentState is! ArticleLoaded) return;

    final updatedProfiles =
        Map<String, Map<String, dynamic>>.from(currentState.profiles);
    updatedProfiles.addAll(event.profiles);

    final articlesWithAuthors = _enrichArticlesWithProfiles(
      currentState.articles,
      updatedProfiles,
    );
    final filteredArticles =
        _filterArticles(articlesWithAuthors, currentState.searchQuery);

    emit(currentState.copyWith(
      articles: articlesWithAuthors,
      filteredArticles: filteredArticles,
      profiles: updatedProfiles,
    ));
  }

  List<Map<String, dynamic>> _enrichArticlesWithProfiles(
    List<Map<String, dynamic>> articles,
    Map<String, Map<String, dynamic>> profiles,
  ) {
    return articles.map((article) {
      final pubkey = article['pubkey'] as String?;
      if (pubkey != null && profiles.containsKey(pubkey)) {
        final profile = profiles[pubkey]!;
        return {
          ...article,
          'author': profile['name'] ?? profile['display_name'] ?? '',
          'authorImage': profile['picture'] ?? profile['picture'] ?? '',
        };
      }
      return article;
    }).toList();
  }

  Future<void> _onArticleRefreshed(
    ArticleRefreshed event,
    Emitter<ArticleState> emit,
  ) async {
    _followingList = await _followingRepository.getFollowing(_currentUserHex);
    try {
      await _syncService.syncArticles(
        authors: _followingList,
        limit: _pageSize,
        force: true,
      );
    } catch (_) {}
  }

  Future<void> _onArticleLoadMoreRequested(
    ArticleLoadMoreRequested event,
    Emitter<ArticleState> emit,
  ) async {
    if (state is! ArticleLoaded) return;

    final currentState = state as ArticleLoaded;
    if (currentState.isLoadingMore || !currentState.canLoadMore) return;

    emit(currentState.copyWith(isLoadingMore: true));

    try {
      final currentCount = currentState.articles.length;
      final moreArticles = await _articleRepository.getArticles(
        limit: _pageSize + currentCount,
      );

      final filteredMore = moreArticles.where((a) {
        if (_followingList == null || _followingList!.isEmpty) return true;
        return _followingList!.contains(a.pubkey);
      }).toList();

      final moreArticleMaps = filteredMore.map((a) => a.toMap()).toList();

      if (moreArticleMaps.length > currentCount) {
        final currentIds = currentState.articles
            .map((a) => a['id'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();

        final uniqueNewArticles = moreArticleMaps.where((a) {
          final articleId = a['id'] as String? ?? '';
          return articleId.isNotEmpty && !currentIds.contains(articleId);
        }).toList();

        if (uniqueNewArticles.isNotEmpty) {
          final updatedArticles = [
            ...currentState.articles,
            ...uniqueNewArticles
          ];
          updatedArticles.sort((a, b) {
            final aTime = a['created_at'] as int? ?? 0;
            final bTime = b['created_at'] as int? ?? 0;
            return bTime.compareTo(aTime);
          });

          final enriched = _enrichArticlesWithProfiles(
              updatedArticles, currentState.profiles);
          final filteredArticles =
              _filterArticles(enriched, currentState.searchQuery);

          emit(currentState.copyWith(
            articles: enriched,
            filteredArticles: filteredArticles,
            isLoadingMore: false,
          ));

          _loadAuthorProfilesInBackground(uniqueNewArticles);
          return;
        }
      }

      emit(currentState.copyWith(isLoadingMore: false, canLoadMore: false));
    } catch (e) {
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

  List<Map<String, dynamic>> _filterArticles(
      List<Map<String, dynamic>> articles, String query) {
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
      final updatedProfiles =
          Map<String, Map<String, dynamic>>.from(currentState.profiles);
      final existingProfile = updatedProfiles[event.userId];
      final existingImage = existingProfile?['picture'] as String? ??
          existingProfile?['picture'] as String? ??
          '';
      if (!updatedProfiles.containsKey(event.userId) || existingImage.isEmpty) {
        updatedProfiles[event.userId] = event.user;

        final enriched =
            _enrichArticlesWithProfiles(currentState.articles, updatedProfiles);
        final filteredArticles =
            _filterArticles(enriched, currentState.searchQuery);

        emit(currentState.copyWith(
          articles: enriched,
          filteredArticles: filteredArticles,
          profiles: updatedProfiles,
        ));
      }
    }
  }

  @override
  Future<void> close() {
    _articlesSubscription?.cancel();
    return super.close();
  }
}
