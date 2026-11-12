import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/data/repositories/article_repository.dart';
import '../../../../lib/data/repositories/following_repository.dart';
import '../../../../lib/data/repositories/profile_repository.dart';
import '../../../../lib/data/sync/sync_service.dart';
import '../../../../lib/domain/entities/article.dart';
import '../../../../lib/domain/entities/user_profile.dart';
import '../../../../lib/presentation/blocs/article/article_bloc.dart';
import '../../../../lib/presentation/blocs/article/article_event.dart';
import '../../../../lib/presentation/blocs/article/article_state.dart';

class _Articles implements ArticleRepository {
  final updates = StreamController<List<Article>>.broadcast();
  List<Article> articles = [];
  final requestedAuthors = <List<String>?>[];

  @override
  Stream<List<Article>> watchArticles({
    List<String>? authors,
    int limit = 50,
  }) => updates.stream;

  @override
  Future<List<Article>> getArticles({
    List<String>? authors,
    int limit = 50,
  }) async {
    requestedAuthors.add(authors);
    return articles;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profiles implements ProfileRepository {
  @override
  Future<Map<String, UserProfile>> getProfiles(List<String> pubkeys) async =>
      {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Following implements FollowingRepository {
  Future<List<String>?> Function(String)? onGet;

  @override
  Future<List<String>?> getFollowing(String pubkey) async =>
      await onGet?.call(pubkey) ?? [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync implements SyncService {
  @override
  Future<void> syncArticles({
    List<String>? authors,
    int limit = 50,
    bool force = false,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Article> _articles(int count) => List.generate(
  count,
  (index) => Article(
    id: 'article-$index',
    pubkey: 'author',
    title: index == 0 ? 'Nostr' : 'Other',
    content: 'Content',
    dTag: 'article-$index',
    publishedAt: 1000 - index,
    createdAt: 1000 - index,
  ),
);

void main() {
  late ArticleBloc bloc;
  late _Articles articles;
  late _Following following;

  setUp(() {
    articles = _Articles()..articles = _articles(50);
    following = _Following();
    bloc = ArticleBloc(
      articleRepository: articles,
      followingRepository: following,
      profileRepository: _Profiles(),
      syncService: _Sync(),
    );
  });

  tearDown(() async {
    await bloc.close();
    await articles.updates.close();
  });

  test('an empty watched snapshot clears deleted or muted articles', () async {
    bloc.add(const ArticleInitialized(userHex: 'user'));
    await bloc.stream.firstWhere((state) => state is ArticleLoaded);
    articles.updates.add([]);
    await bloc.stream.firstWhere(
      (state) => state is ArticleLoaded && state.articles.isEmpty,
    );
    expect((bloc.state as ArticleLoaded).filteredArticles, isEmpty);
    expect((bloc.state as ArticleLoaded).canLoadMore, isFalse);
  });

  test(
    'stale following requests cannot change pagination authors after account switching',
    () async {
      final oldFollowing = Completer<List<String>?>();
      following.onGet = (pubkey) =>
          pubkey == 'old' ? oldFollowing.future : Future.value(['new-follow']);
      bloc.add(const ArticleInitialized(userHex: 'old'));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const ArticleInitialized(userHex: 'new'));
      await bloc.stream.firstWhere(
        (state) => state is ArticleLoaded && state.currentUserHex == 'new',
      );
      oldFollowing.complete(['old-follow']);
      await Future<void>.delayed(Duration.zero);
      articles.articles = _articles(100);
      bloc.add(const ArticleLoadMoreRequested());
      await bloc.stream.firstWhere(
        (state) => state is ArticleLoaded && state.articles.length == 100,
      );
      expect(articles.requestedAuthors.last, ['new', 'new-follow']);
    },
  );

  test('search remains applied when pagination adds articles', () async {
    bloc.add(const ArticleInitialized(userHex: 'user'));
    await bloc.stream.firstWhere((state) => state is ArticleLoaded);
    bloc.add(const ArticleSearchQueryChanged('nostr'));
    await bloc.stream.firstWhere(
      (state) => state is ArticleLoaded && state.searchQuery == 'nostr',
    );
    articles.articles = _articles(100);
    bloc.add(const ArticleLoadMoreRequested());
    await bloc.stream.firstWhere(
      (state) => state is ArticleLoaded && state.articles.length == 100,
    );
    expect(
      (bloc.state as ArticleLoaded).filteredArticles.single['id'],
      'article-0',
    );
  });
}
