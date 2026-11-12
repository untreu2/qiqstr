import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/data/repositories/feed_repository.dart';
import '../../../../lib/data/repositories/following_repository.dart';
import '../../../../lib/data/repositories/profile_repository.dart';
import '../../../../lib/data/services/follow_set_service.dart';
import '../../../../lib/data/sync/sync_service.dart';
import '../../../../lib/domain/entities/feed_note.dart';
import '../../../../lib/domain/entities/user_profile.dart';
import '../../../../lib/presentation/blocs/feed/feed_bloc.dart';
import '../../../../lib/presentation/blocs/feed/feed_event.dart';
import '../../../../lib/presentation/blocs/feed/feed_state.dart';

class _Feed implements FeedRepository {
  final updates = StreamController<FeedUpdate>.broadcast();
  final watchedAuthors = <List<String>?>[];
  final requestedAuthors = <List<String>?>[];
  Future<List<FeedNote>> Function()? onLoadMore;

  @override
  Stream<FeedUpdate> watchHashtag(String hashtag, {int limit = 50}) =>
      updates.stream;

  @override
  Stream<FeedUpdate> watchFeed(
    String pubkey, {
    List<String>? authors,
    int limit = 50,
    String sortMode = 'latest',
  }) {
    watchedAuthors.add(authors);
    return updates.stream;
  }

  @override
  Future<List<FeedNote>> getFeed(
    String pubkey, {
    List<String>? authors,
    int limit = 50,
    String sortMode = 'latest',
  }) {
    requestedAuthors.add(authors);
    return onLoadMore?.call() ?? Future.value([]);
  }

  @override
  Future<List<FeedNote>> getHashtag(String hashtag, {int limit = 50}) =>
      onLoadMore?.call() ?? Future.value([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profiles implements ProfileRepository {
  final profiles = <String, UserProfile>{};

  @override
  Future<UserProfile?> getProfile(String pubkey) async => profiles[pubkey];

  @override
  Future<Map<String, UserProfile>> getProfiles(List<String> pubkeys) async =>
      {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Following implements FollowingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync implements SyncService {
  @override
  Future<void> syncHashtag(String hashtag, {bool force = false}) async {}

  @override
  Future<void> syncListFeed(List<String> pubkeys, {bool force = false}) async {}

  @override
  Future<void> syncProfiles(List<String> pubkeys) async {}

  @override
  Future<void> syncInteractionsForNotes(List<String> ids) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<FeedNote> _notes(int count, {int start = 0}) => List.generate(
  count,
  (index) => FeedNote(
    id: 'note-${index + start}',
    pubkey: 'author',
    authorName: 'Author',
    content: '',
    createdAt: 1000 - index - start,
    tags: const [],
  ),
);

void main() {
  late FeedBloc bloc;
  late _Feed feed;
  late _Profiles profiles;
  final user = 'a' * 64;

  setUp(() async {
    feed = _Feed();
    profiles = _Profiles();
    profiles.profiles[user] = UserProfile(pubkey: user, name: 'First account');
    bloc = FeedBloc(
      feedRepository: feed,
      followingRepository: _Following(),
      profileRepository: profiles,
      syncService: _Sync(),
      followSetService: FollowSetService.instance,
    );
    bloc.add(FeedInitialized(userHex: user, hashtag: 'nostr'));
    await bloc.stream.firstWhere(
      (state) => state is FeedLoaded && !state.isSyncing,
    );
    feed.updates.add(FeedSnapshot(_notes(50)));
    await bloc.stream.firstWhere(
      (state) => state is FeedLoaded && state.notes.length == 50,
    );
  });

  tearDown(() async {
    await bloc.close();
    await feed.updates.close();
  });

  test('list pagination and sorting use the selected author list', () async {
    bloc.add(
      const FeedListChanged(listId: 'external:list', pubkeys: ['selected']),
    );
    await bloc.stream.firstWhere(
      (state) =>
          state is FeedLoaded &&
          state.activeListId == 'external:list' &&
          !state.isSyncing,
    );
    feed.updates.add(FeedSnapshot(_notes(50)));
    await bloc.stream.firstWhere(
      (state) => state is FeedLoaded && state.notes.length == 50,
    );
    feed.onLoadMore = () async => _notes(100);
    bloc.add(const FeedLoadMoreRequested());
    await bloc.stream.firstWhere(
      (state) => state is FeedLoaded && state.notes.length == 100,
    );
    expect(feed.requestedAuthors.last, ['selected']);
    bloc.add(const FeedSortModeChanged(FeedSortMode.mostInteracted));
    await bloc.stream.firstWhere(
      (state) =>
          state is FeedLoaded && state.sortMode == FeedSortMode.mostInteracted,
    );
    expect(feed.watchedAuthors.last, ['selected']);
  });

  for (final contextChange in <FeedEvent>[
    const FeedRefreshed(),
    const FeedHashtagChanged('other'),
    const FeedListChanged(listId: 'new', pubkeys: ['author']),
    const FeedSortModeChanged(FeedSortMode.mostInteracted),
  ]) {
    test(
      '${contextChange.runtimeType} clears pagination state and rejects the old page',
      () async {
        final pending = Completer<List<FeedNote>>();
        feed.onLoadMore = () => pending.future;
        bloc.add(const FeedLoadMoreRequested());
        await bloc.stream.firstWhere(
          (state) => state is FeedLoaded && state.isLoadingMore,
        );
        bloc.add(contextChange);
        await bloc.stream.firstWhere(
          (state) => state is FeedLoaded && !state.isLoadingMore,
        );
        pending.complete(_notes(100));
        await Future<void>.delayed(Duration.zero);
        final state = bloc.state as FeedLoaded;
        expect(state.isLoadingMore, isFalse);
        expect(state.notes.where((note) => note.id == 'note-99'), isEmpty);
      },
    );
  }

  test(
    'account switching cannot attach the previous account profile to the new key',
    () async {
      final newUser = 'b' * 64;
      bloc.add(FeedInitialized(userHex: newUser, hashtag: 'nostr'));
      await bloc.stream.firstWhere(
        (state) => state is FeedLoaded && state.currentUserHex == newUser,
      );
      feed.updates.add(FeedSnapshot(_notes(1)));
      await bloc.stream.firstWhere(
        (state) => state is FeedLoaded && state.notes.length == 1,
      );
      expect((bloc.state as FeedLoaded).profiles.containsKey(newUser), isFalse);
    },
  );

  test(
    'new notes wait for acceptance while deletions remain immediate',
    () async {
      final newer = _notes(1, start: -1).single;
      feed.updates.add(FeedDelta(changed: [newer], removed: const ['note-0']));
      await bloc.stream.firstWhere(
        (state) => state is FeedLoaded && state.pendingNotesCount == 1,
      );
      expect(
        (bloc.state as FeedLoaded).notes.any((note) => note.id == newer.id),
        isFalse,
      );
      expect(
        (bloc.state as FeedLoaded).notes.any((note) => note.id == 'note-0'),
        isFalse,
      );
      bloc.add(const FeedNewNotesAccepted());
      await bloc.stream.firstWhere(
        (state) => state is FeedLoaded && state.pendingNotesCount == 0,
      );
      expect((bloc.state as FeedLoaded).notes.first.id, newer.id);
    },
  );
}
