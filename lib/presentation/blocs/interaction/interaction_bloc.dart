import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/interaction_service.dart';
import 'dart:convert';
import 'interaction_event.dart';
import 'interaction_state.dart';

class InteractionBloc extends Bloc<InteractionEvent, InteractionState> {
  final SyncService _syncService;
  final FeedRepository _feedRepository;
  final InteractionRepository _interactionRepository;
  final InteractionService _interactionService;
  final String noteId;
  final String currentUserHex;
  Map<String, dynamic>? note;

  StreamSubscription<InteractionCounts>? _subscription;

  InteractionBloc({
    required SyncService syncService,
    required FeedRepository feedRepository,
    required InteractionRepository interactionRepository,
    required this.noteId,
    required this.currentUserHex,
    this.note,
    InteractionService? interactionService,
  })  : _syncService = syncService,
        _feedRepository = feedRepository,
        _interactionRepository = interactionRepository,
        _interactionService = interactionService ?? InteractionService.instance,
        super(const InteractionInitial()) {
    on<InteractionInitialized>(_onInitialized);
    on<InteractionNoteUpdated>(_onNoteUpdated);
    on<InteractionStateRefreshed>(_onRefreshed);
    on<InteractionReactRequested>(_onReact);
    on<InteractionRepostRequested>(_onRepost);
    on<InteractionRepostDeleted>(_onRepostDeleted);
    on<InteractionNoteDeleted>(_onNoteDeleted);
    on<InteractionZapStarted>(_onZapStarted);
    on<InteractionZapCompleted>(_onZapCompleted);
    on<InteractionZapFailed>(_onZapFailed);
    on<InteractionCountsUpdated>(_onCountsUpdated);
  }

  Future<void> _onInitialized(
      InteractionInitialized event, Emitter<InteractionState> emit) async {
    note = event.note;
    _interactionService.setCurrentUser(currentUserHex);

    final cached = _interactionService.getCachedInteractions(noteId);

    InteractionCounts? initialCounts;
    if (note != null) {
      final reactionCount = note!['reactionCount'] as int? ?? 0;
      final repostCount = note!['repostCount'] as int? ?? 0;
      final replyCount = note!['replyCount'] as int? ?? 0;
      final zapCount = note!['zapCount'] as int? ?? 0;
      final noteHasReacted = note!['hasReacted'] == true;
      final noteHasReposted = note!['hasReposted'] == true;
      final noteHasZapped = note!['hasZapped'] == true;

      final hasReacted = _interactionService.hasReacted(noteId) ||
          noteHasReacted ||
          (cached?.hasReacted ?? false);
      final hasReposted = _interactionService.hasReposted(noteId) ||
          noteHasReposted ||
          (cached?.hasReposted ?? false);
      final hasZapped = _interactionService.hasZapped(noteId) ||
          noteHasZapped ||
          (cached?.hasZapped ?? false);

      final effectiveReactions =
          cached != null && cached.reactions > reactionCount
              ? cached.reactions
              : reactionCount;
      final effectiveReposts = cached != null && cached.reposts > repostCount
          ? cached.reposts
          : repostCount;
      final effectiveReplies = cached != null && cached.replies > replyCount
          ? cached.replies
          : replyCount;
      final effectiveZaps = cached != null && cached.zapAmount > zapCount
          ? cached.zapAmount
          : zapCount;

      initialCounts = InteractionCounts(
        reactions: effectiveReactions,
        reposts: effectiveReposts,
        replies: effectiveReplies,
        zapAmount: effectiveZaps,
        hasReacted: hasReacted,
        hasReposted: hasReposted,
        hasZapped: hasZapped,
      );
      emit(InteractionLoaded(
        reactionCount: effectiveReactions,
        repostCount: effectiveReposts,
        replyCount: effectiveReplies,
        zapAmount: effectiveZaps,
        hasReacted: hasReacted,
        hasReposted: hasReposted,
        hasZapped: hasZapped,
      ));
    } else if (cached != null) {
      initialCounts = cached;
      emit(InteractionLoaded(
        reactionCount: cached.reactions,
        repostCount: cached.reposts,
        replyCount: cached.replies,
        zapAmount: cached.zapAmount,
        hasReacted: cached.hasReacted || _interactionService.hasReacted(noteId),
        hasReposted:
            cached.hasReposted || _interactionService.hasReposted(noteId),
        hasZapped: cached.hasZapped || _interactionService.hasZapped(noteId),
      ));
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
    final currentState =
        state is InteractionLoaded ? (state as InteractionLoaded) : null;

    final hasZapped = event.counts.hasZapped ||
        _interactionService.hasZapped(noteId) ||
        (currentState?.hasZapped ?? false);
    final hasReacted = event.counts.hasReacted ||
        _interactionService.hasReacted(noteId) ||
        (currentState?.hasReacted ?? false);
    final hasReposted = event.counts.hasReposted ||
        _interactionService.hasReposted(noteId) ||
        (currentState?.hasReposted ?? false);

    if (currentState != null && currentState.zapProcessing) {
      emit(currentState.copyWith(
        reactionCount: event.counts.reactions,
        repostCount: event.counts.reposts,
        replyCount: event.counts.replies,
        zapAmount: event.counts.zapAmount,
        hasReacted: hasReacted,
        hasReposted: hasReposted,
        hasZapped: hasZapped,
      ));
      return;
    }

    emit(InteractionLoaded(
      reactionCount: event.counts.reactions,
      repostCount: event.counts.reposts,
      replyCount: event.counts.replies,
      zapAmount: event.counts.zapAmount,
      hasReacted: hasReacted,
      hasReposted: hasReposted,
      hasZapped: hasZapped,
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
    if (_interactionService.hasReacted(noteId)) return;

    _interactionService.markReacted(noteId);

    emit(currentState.copyWith(
      hasReacted: true,
      reactionCount: currentState.reactionCount + 1,
    ));

    try {
      final noteAuthor =
          note?['pubkey'] as String? ?? '';
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
    if (_interactionService.hasReposted(noteId)) return;

    _interactionService.markReposted(noteId);

    emit(currentState.copyWith(
      hasReposted: true,
      repostCount: currentState.repostCount + 1,
    ));

    try {
      final noteAuthor =
          note?['pubkey'] as String? ?? '';
      String originalContent = '';
      final noteModel = await _feedRepository.getNote(noteId);
      if (noteModel != null) {
        originalContent = jsonEncode(noteModel.toMap());
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
      final repostEventId =
          await _interactionRepository.findRepostId(currentUserHex, noteId);
      if (repostEventId != null) {
        await _syncService.publishDeletion(eventIds: [repostEventId]);
      }
    } catch (_) {}
  }

  void _onZapStarted(
      InteractionZapStarted event, Emitter<InteractionState> emit) {
    final currentState =
        state is InteractionLoaded ? (state as InteractionLoaded) : null;
    if (currentState == null) return;

    emit(currentState.copyWith(
      zapProcessing: true,
      hasZapped: true,
      zapAmount: currentState.zapAmount + event.amount,
    ));
  }

  void _onZapCompleted(
      InteractionZapCompleted event, Emitter<InteractionState> emit) {
    final currentState =
        state is InteractionLoaded ? (state as InteractionLoaded) : null;
    if (currentState == null) return;

    _interactionService.markZapped(noteId, event.amount);

    emit(currentState.copyWith(
      zapProcessing: false,
      hasZapped: true,
    ));
  }

  void _onZapFailed(
      InteractionZapFailed event, Emitter<InteractionState> emit) {
    final currentState =
        state is InteractionLoaded ? (state as InteractionLoaded) : null;
    if (currentState == null) return;

    emit(currentState.copyWith(
      zapProcessing: false,
      hasZapped: false,
    ));

    _interactionService.refreshInteractions(noteId);
  }

  Future<void> _onNoteDeleted(
      InteractionNoteDeleted event, Emitter<InteractionState> emit) async {
    try {
      await _syncService.publishDeletion(eventIds: [noteId]);
      final currentState =
          state is InteractionLoaded ? (state as InteractionLoaded) : null;
      if (currentState != null) {
        emit(currentState.copyWith(noteDeleted: true));
      } else {
        emit(const InteractionLoaded(noteDeleted: true));
      }
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
