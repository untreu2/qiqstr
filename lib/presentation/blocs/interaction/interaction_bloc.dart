import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/interaction_service.dart';
import '../../../data/services/isar_database_service.dart';
import 'interaction_event.dart';
import 'interaction_state.dart';

class InteractionBloc extends Bloc<InteractionEvent, InteractionState> {
  final SyncService _syncService;
  final InteractionService _interactionService;
  final String noteId;
  final String currentUserHex;
  Map<String, dynamic>? note;

  StreamSubscription<InteractionCounts>? _subscription;

  InteractionBloc({
    required SyncService syncService,
    required FeedRepository feedRepository,
    required this.noteId,
    required this.currentUserHex,
    this.note,
    InteractionService? interactionService,
  })  : _syncService = syncService,
        _interactionService = interactionService ?? InteractionService.instance,
        super(const InteractionInitial()) {
    on<InteractionInitialized>(_onInitialized);
    on<InteractionNoteUpdated>(_onNoteUpdated);
    on<InteractionStateRefreshed>(_onRefreshed);
    on<InteractionReactRequested>(_onReact);
    on<InteractionRepostRequested>(_onRepost);
    on<InteractionRepostDeleted>(_onRepostDeleted);
    on<InteractionNoteDeleted>(_onNoteDeleted);
    on<InteractionCountsUpdated>(_onCountsUpdated);
  }

  Future<void> _onInitialized(
      InteractionInitialized event, Emitter<InteractionState> emit) async {
    note = event.note;
    _interactionService.setCurrentUser(currentUserHex);

    InteractionCounts? initialCounts;
    if (note != null) {
      final reactionCount = note!['reactionCount'] as int? ?? 0;
      final repostCount = note!['repostCount'] as int? ?? 0;
      final replyCount = note!['replyCount'] as int? ?? 0;
      final zapCount = note!['zapCount'] as int? ?? 0;

      if (reactionCount > 0 ||
          repostCount > 0 ||
          replyCount > 0 ||
          zapCount > 0) {
        initialCounts = InteractionCounts(
          reactions: reactionCount,
          reposts: repostCount,
          replies: replyCount,
          zapAmount: zapCount,
          hasReacted: _interactionService.hasReacted(noteId),
          hasReposted: _interactionService.hasReposted(noteId),
          hasZapped: false,
        );
        emit(InteractionLoaded(
          reactionCount: reactionCount,
          repostCount: repostCount,
          replyCount: replyCount,
          zapAmount: zapCount,
          hasReacted: initialCounts.hasReacted,
          hasReposted: initialCounts.hasReposted,
          hasZapped: false,
        ));
      } else {
        emit(const InteractionLoaded());
      }
    } else {
      emit(const InteractionLoaded());
    }

    _subscription?.cancel();
    _subscription = _interactionService
        .streamInteractions(noteId, initialCounts: initialCounts)
        .listen(
          (counts) => add(InteractionCountsUpdated(counts)),
        );
  }

  void _onCountsUpdated(
      InteractionCountsUpdated event, Emitter<InteractionState> emit) {
    emit(InteractionLoaded(
      reactionCount: event.counts.reactions,
      repostCount: event.counts.reposts,
      replyCount: event.counts.replies,
      zapAmount: event.counts.zapAmount,
      hasReacted: event.counts.hasReacted,
      hasReposted: event.counts.hasReposted,
      hasZapped: event.counts.hasZapped,
    ));
  }

  void _onNoteUpdated(
      InteractionNoteUpdated event, Emitter<InteractionState> emit) {
    note = event.note;
  }

  Future<void> _onRefreshed(
      InteractionStateRefreshed event, Emitter<InteractionState> emit) async {
    await _interactionService.refreshInteractions(noteId);
  }

  Future<void> _onReact(
      InteractionReactRequested event, Emitter<InteractionState> emit) async {
    final currentState =
        state is InteractionLoaded ? (state as InteractionLoaded) : null;
    if (currentState == null || currentState.hasReacted) return;

    _interactionService.markReacted(noteId);

    try {
      final noteAuthor =
          note?['pubkey'] as String? ?? note?['author'] as String? ?? '';
      await _syncService.publishReaction(
        targetEventId: noteId,
        targetAuthor: noteAuthor,
        content: '+',
      );
    } catch (_) {
      await _interactionService.refreshInteractions(noteId);
    }
  }

  Future<void> _onRepost(
      InteractionRepostRequested event, Emitter<InteractionState> emit) async {
    final currentState =
        state is InteractionLoaded ? (state as InteractionLoaded) : null;
    if (currentState == null || currentState.hasReposted) return;

    _interactionService.markReposted(noteId);

    try {
      final noteAuthor =
          note?['pubkey'] as String? ?? note?['author'] as String? ?? '';
      String originalContent = '';
      final eventModel =
          await IsarDatabaseService.instance.getEventModel(noteId);
      if (eventModel != null) {
        originalContent = eventModel.rawEvent;
      }

      await _syncService.publishRepost(
        noteId: noteId,
        noteAuthor: noteAuthor,
        originalContent: originalContent,
      );
    } catch (e) {
      debugPrint('[InteractionBloc] Repost failed: $e');
      _interactionService.markUnreposted(noteId);
      await _interactionService.refreshInteractions(noteId);
    }
  }

  Future<void> _onRepostDeleted(
      InteractionRepostDeleted event, Emitter<InteractionState> emit) async {
    _interactionService.markUnreposted(noteId);

    try {
      final db = IsarDatabaseService.instance;
      final repostEventId =
          await db.findUserRepostEventId(currentUserHex, noteId);
      if (repostEventId != null) {
        await _syncService.publishDeletion(eventIds: [repostEventId]);
      }
    } catch (_) {}
  }

  Future<void> _onNoteDeleted(
      InteractionNoteDeleted event, Emitter<InteractionState> emit) async {
    try {
      await _syncService.publishDeletion(eventIds: [noteId]);
    } catch (_) {}
  }

  Map<String, dynamic>? getNoteForActions() => note;

  @override
  Future<void> close() {
    _subscription?.cancel();
    _interactionService.disposeStream(noteId);
    return super.close();
  }
}
