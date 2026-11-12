import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/data/repositories/feed_repository.dart';
import '../../../../lib/data/repositories/interaction_repository.dart';
import '../../../../lib/data/services/encrypted_bookmark_service.dart';
import '../../../../lib/data/services/interaction_service.dart';
import '../../../../lib/data/sync/sync_service.dart';
import '../../../../lib/presentation/blocs/interaction/interaction_bloc.dart';
import '../../../../lib/presentation/blocs/interaction/interaction_event.dart';
import '../../../../lib/presentation/blocs/interaction/interaction_state.dart';

class _Feed implements FeedRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Interactions implements InteractionService {
  bool reacted = false;
  final updates = StreamController<InteractionCounts>.broadcast();

  @override
  void setCurrentUser(String? user) {}

  @override
  InteractionCounts? getCachedInteractions(String noteId) => null;

  @override
  bool hasReacted(String noteId) => reacted;

  @override
  bool hasReposted(String noteId) => false;

  @override
  bool hasZapped(String noteId) => false;

  @override
  void markReacted(String noteId) => reacted = true;

  @override
  void markUnreacted(String noteId) => reacted = false;

  @override
  void markZapped(String noteId, int amount) {}

  @override
  void disposeStream(String noteId) {}

  @override
  Future<void> refreshInteractions(String noteId) async {}

  @override
  Stream<InteractionCounts> streamInteractions(
    String noteId, {
    InteractionCounts? initialCounts,
  }) => updates.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync implements SyncService {
  final reaction = Completer<Map<String, dynamic>>();
  final deletion = Completer<Map<String, dynamic>>();
  int reactionsPublished = 0;

  @override
  Future<Map<String, dynamic>> publishReaction({
    required String targetEventId,
    required String targetAuthor,
    String content = '+',
  }) {
    reactionsPublished++;
    return reaction.future;
  }

  @override
  Future<Map<String, dynamic>> publishBookmark({
    required List<String> bookmarkedEventIds,
  }) async => throw StateError('offline');

  @override
  Future<Map<String, dynamic>> publishDeletion({
    required List<String> eventIds,
    String? reason,
  }) => deletion.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late InteractionBloc bloc;
  late _Interactions interactions;
  late _Sync sync;

  setUp(() async {
    EncryptedBookmarkService.instance.clear();
    interactions = _Interactions();
    sync = _Sync();
    bloc = InteractionBloc(
      syncService: sync,
      feedRepository: _Feed(),
      interactionRepository: const InteractionRepository(),
      noteId: 'note',
      currentUserHex: 'user',
      interactionService: interactions,
    );
    bloc.add(
      const InteractionInitialized(
        noteId: 'note',
        currentUserHex: 'user',
        note: {'pubkey': 'author', 'reactionCount': 3, 'zapCount': 50},
      ),
    );
    await bloc.stream.firstWhere((state) => state is InteractionLoaded);
  });

  tearDown(() async {
    await bloc.close();
    await interactions.updates.close();
    EncryptedBookmarkService.instance.clear();
  });

  test(
    'reaction taps are deduplicated and failed publication rolls back',
    () async {
      bloc.add(const InteractionReactRequested());
      bloc.add(const InteractionReactRequested());
      await bloc.stream.firstWhere(
        (state) => state is InteractionLoaded && state.hasReacted,
      );
      await _flush();
      expect(sync.reactionsPublished, 1);
      expect((bloc.state as InteractionLoaded).reactionCount, 4);
      sync.reaction.completeError(StateError('offline'));
      await bloc.stream.firstWhere(
        (state) => state is InteractionLoaded && !state.hasReacted,
      );
      expect((bloc.state as InteractionLoaded).reactionCount, 3);
      expect(interactions.reacted, isFalse);
    },
  );

  test(
    'failed bookmark toggles restore both state and bookmark cache',
    () async {
      bloc.add(const InteractionBookmarkToggled());
      await bloc.stream.firstWhere(
        (state) => state is InteractionLoaded && state.isBookmarked,
      );
      await bloc.stream.firstWhere(
        (state) => state is InteractionLoaded && !state.isBookmarked,
      );
      expect(EncryptedBookmarkService.instance.isBookmarked('note'), isFalse);
    },
  );

  test(
    'duplicate zap starts cannot corrupt the pending amount or rollback baseline',
    () async {
      bloc.add(const InteractionZapStarted(amount: 10));
      bloc.add(const InteractionZapStarted(amount: 10));
      await _flush();
      expect((bloc.state as InteractionLoaded).zapAmount, 60);
      bloc.add(const InteractionZapFailed());
      await _flush();
      expect((bloc.state as InteractionLoaded).zapAmount, 50);
      expect((bloc.state as InteractionLoaded).hasZapped, isFalse);
    },
  );

  test('a late failure cannot undo a completed zap', () async {
    bloc.add(const InteractionZapStarted(amount: 10));
    await _flush();
    bloc.add(const InteractionZapCompleted(amount: 10));
    await _flush();
    bloc.add(const InteractionZapFailed());
    await _flush();
    expect((bloc.state as InteractionLoaded).zapAmount, 60);
    expect((bloc.state as InteractionLoaded).hasZapped, isTrue);
    expect((bloc.state as InteractionLoaded).zapProcessing, isFalse);
  });

  test('deletion is visible only after publication succeeds', () async {
    bloc.add(const InteractionNoteDeleted());
    await _flush();
    expect((bloc.state as InteractionLoaded).noteDeleted, isFalse);
    sync.deletion.complete({'id': 'deletion'});
    await bloc.stream.firstWhere(
      (state) => state is InteractionLoaded && state.noteDeleted,
    );
  });
}
