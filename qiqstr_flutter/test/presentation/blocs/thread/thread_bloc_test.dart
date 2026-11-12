import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/data/repositories/feed_repository.dart';
import '../../../../lib/data/repositories/profile_repository.dart';
import '../../../../lib/data/services/auth_service.dart';
import '../../../../lib/data/services/encrypted_mute_service.dart';
import '../../../../lib/data/services/interaction_service.dart';
import '../../../../lib/data/sync/sync_service.dart';
import '../../../../lib/domain/entities/user_profile.dart';
import '../../../../lib/presentation/blocs/thread/thread_bloc.dart';
import '../../../../lib/presentation/blocs/thread/thread_event.dart';
import '../../../../lib/presentation/blocs/thread/thread_state.dart';

class _Feed implements FeedRepository {
  @override
  Future<Map<String, dynamic>?> getThreadStructure(
    String id, {
    int limit = 500,
  }) async => null;

  @override
  Stream<Map<String, dynamic>?> watchThreadStructure(
    String id, {
    int limit = 500,
  }) => const Stream.empty();

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

class _Auth implements AuthService {
  @override
  String? get currentUserPubkeyHex => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Interactions implements InteractionService {
  @override
  Future<void> fetchCountsFromRelays(List<String> ids) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync implements SyncService {
  final networkRequests = <String, Completer<Map<String, dynamic>>>{};

  @override
  Future<Map<String, dynamic>> fetchFullThread(
    String id, {
    String? currentUserPubkeyHex,
  }) => (networkRequests[id] = Completer<Map<String, dynamic>>()).future;

  @override
  Future<Map<String, dynamic>?> fetchFullThreadLocal(
    String id, {
    String? currentUserPubkeyHex,
    List<String> mutedPubkeys = const [],
    List<String> mutedWords = const [],
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ThreadBloc bloc;
  late _Sync sync;

  setUp(() {
    sync = _Sync();
    bloc = ThreadBloc(
      feedRepository: _Feed(),
      profileRepository: _Profiles(),
      syncService: sync,
      authService: _Auth(),
      muteService: EncryptedMuteService.instance,
      interactionService: _Interactions(),
    );
  });

  tearDown(() async => bloc.close());

  test('a missing thread ends loading with an error', () async {
    bloc.add(const ThreadLoadRequested(chain: ['missing']));
    await Future<void>.delayed(Duration.zero);
    final failed = bloc.stream.firstWhere((state) => state is ThreadError);
    sync.networkRequests['missing']!.complete({});
    await failed;
  });

  test(
    'the latest thread wins when network replies arrive out of order',
    () async {
      bloc.add(const ThreadLoadRequested(chain: ['old']));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const ThreadLoadRequested(chain: ['new']));
      await Future<void>.delayed(Duration.zero);
      sync.networkRequests['new']!.complete({
        'rootNote': {'id': 'new', 'content': 'New'},
      });
      await bloc.stream.firstWhere(
        (state) => state is ThreadLoaded && state.rootNoteId == 'new',
      );
      sync.networkRequests['old']!.complete({
        'rootNote': {'id': 'old', 'content': 'Old'},
      });
      await Future<void>.delayed(Duration.zero);
      expect((bloc.state as ThreadLoaded).rootNoteId, 'new');
    },
  );

  test('repost previews are displayed as the original note', () async {
    bloc.add(
      const ThreadLoadRequested(
        chain: ['original'],
        initialNoteData: {
          'id': 'repost',
          'content': 'Text',
          'isRepost': true,
          'repostedBy': 'other',
          'repostCreatedAt': 100,
        },
      ),
    );
    await bloc.stream.firstWhere((state) => state is ThreadLoaded);
    final note = (bloc.state as ThreadLoaded).rootNote;
    expect(note['id'], 'original');
    expect(note['isRepost'], isFalse);
    expect(note.containsKey('repostedBy'), isFalse);
    sync.networkRequests['original']!.complete({});
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state, isA<ThreadLoaded>());
  });
}
