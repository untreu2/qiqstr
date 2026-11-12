import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/core/base/result.dart';
import '../../../../lib/data/repositories/feed_repository.dart';
import '../../../../lib/data/services/auth_service.dart';
import '../../../../lib/data/services/encrypted_bookmark_service.dart';
import '../../../../lib/data/sync/sync_service.dart';
import '../../../../lib/domain/entities/feed_note.dart';
import '../../../../lib/presentation/blocs/bookmark/bookmark_bloc.dart';
import '../../../../lib/presentation/blocs/bookmark/bookmark_event.dart';
import '../../../../lib/presentation/blocs/bookmark/bookmark_state.dart';

class _Auth implements AuthService {
  @override
  String? currentUserPubkeyHex = 'user';

  @override
  Future<Result<String>> getCurrentUserPublicKeyHex() async =>
      currentUserPubkeyHex == null
      ? Result.error('Not authenticated')
      : Success(currentUserPubkeyHex!);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Feed implements FeedRepository {
  @override
  Future<List<FeedNote>> getNotesByIds(List<String> ids) async =>
      List.unmodifiable(
        ids.map(
          (id) => FeedNote(
            id: id,
            pubkey: 'author',
            content: id,
            createdAt: 1,
            tags: const [],
          ),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync implements SyncService {
  Future<void> Function()? onSync;
  Future<Map<String, dynamic>> Function(List<String>)? onPublish;
  final published = <List<String>>[];

  @override
  Future<void> syncBookmarkList(String userPubkey) async => onSync?.call();

  @override
  Future<Map<String, dynamic>> publishBookmark({
    required List<String> bookmarkedEventIds,
  }) async {
    published.add([...bookmarkedEventIds]);
    return await onPublish?.call(bookmarkedEventIds) ?? {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late _Sync sync;
  late _Auth auth;
  late BookmarkBloc bloc;
  final service = EncryptedBookmarkService.instance;

  setUp(() async {
    service.updateCache(eventIds: ['one', 'two']);
    sync = _Sync();
    auth = _Auth();
    bloc = BookmarkBloc(
      feedRepository: _Feed(),
      syncService: sync,
      authService: auth,
    );
    bloc.add(const BookmarkLoadRequested());
    await bloc.stream.firstWhere(
      (state) => state is BookmarkLoaded && !state.isSyncing,
    );
  });

  tearDown(() async {
    await bloc.close();
    service.clear();
  });

  test('serializes removals so removed notes cannot reappear', () async {
    final firstPublish = Completer<Map<String, dynamic>>();
    sync.onPublish = (_) =>
        sync.published.length == 1 ? firstPublish.future : Future.value({});
    bloc.add(const BookmarkRemoved('one'));
    bloc.add(const BookmarkRemoved('two'));
    await _flush();
    expect(sync.published, [
      ['two'],
    ]);
    firstPublish.complete({});
    await bloc.stream.firstWhere(
      (state) => state is BookmarkLoaded && state.bookmarkedNotes.isEmpty,
    );
    expect(service.bookmarkedEventIds, isEmpty);
    expect(sync.published, [
      ['two'],
      <String>[],
    ]);
  });

  test(
    'rolls back failed removals and clears the progress indicator',
    () async {
      sync.onPublish = (_) => Future.error(StateError('offline'));
      final error = bloc.stream.firstWhere((state) => state is BookmarkError);
      bloc.add(const BookmarkRemoved('one'));
      await error;
      await _flush();
      expect(service.bookmarkedEventIds, ['one', 'two']);
      expect((bloc.state as BookmarkLoaded).removingStates, isEmpty);
      expect((bloc.state as BookmarkLoaded).bookmarkedNotes.length, 2);
    },
  );

  test(
    'refresh removes cached notes when the remote list becomes empty',
    () async {
      sync.onSync = () async => service.updateCache(eventIds: []);
      bloc.add(const BookmarkRefreshed());
      await bloc.stream.firstWhere(
        (state) =>
            state is BookmarkLoaded &&
            !state.isSyncing &&
            state.bookmarkedNotes.isEmpty,
      );
      expect(service.bookmarkedEventIds, isEmpty);
    },
  );

  test(
    'adding an existing bookmark does not duplicate or republish it',
    () async {
      bloc.add(const BookmarkAdded('one'));
      await _flush();
      expect((bloc.state as BookmarkLoaded).bookmarkedNotes.length, 2);
      expect(sync.published, isEmpty);
    },
  );

  test('failed additions restore the cache', () async {
    sync.onPublish = (_) => Future.error(StateError('offline'));
    final error = bloc.stream.firstWhere((state) => state is BookmarkError);
    bloc.add(const BookmarkAdded('three'));
    await error;
    await _flush();
    expect(service.bookmarkedEventIds, ['one', 'two']);
    expect((bloc.state as BookmarkLoaded).bookmarkedNotes.length, 2);
  });
  for (final event in [
    const BookmarkAdded('three'),
    const BookmarkRemoved('one'),
  ]) {
    for (final transition in ['clear', 'identity', 'switchAndClose']) {
      test(
        '${event.runtimeType} cannot restore a prior session after $transition',
        () async {
          final pending = Completer<Map<String, dynamic>>();
          final started = Completer<void>();
          sync.onPublish = (_) {
            started.complete();
            return pending.future;
          };
          bloc.add(event);
          await started.future;
          if (transition != 'identity') service.clear();
          if (transition != 'clear') auth.currentUserPubkeyHex = 'other';
          service.updateCache(eventIds: ['other-account-bookmark']);
          final states = <BookmarkState>[];
          final subscription = bloc.stream.listen(states.add);
          final closing = transition == 'switchAndClose' ? bloc.close() : null;
          await _flush();
          pending.completeError(StateError('old publication failed'));
          if (closing != null) await closing;
          await _flush();
          expect(service.bookmarkedEventIds, ['other-account-bookmark']);
          expect(states, isEmpty);
          await subscription.cancel();
        },
      );
    }
  }
}
