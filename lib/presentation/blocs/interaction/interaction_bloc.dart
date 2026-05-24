import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/interaction_service.dart';
import '../../../data/services/encrypted_bookmark_service.dart';
import '../../../data/services/pinned_notes_service.dart';
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
  StreamSubscription<void>? _bookmarkSubscription;
  StreamSubscription<List<String>>? _pinSubscription;

  static const _optimisticTtl = Duration(seconds: 10);
  DateTime? _optimisticReactedAt;
  DateTime? _optimisticRepostedAt;
  DateTime? _optimisticZappedAt;

  bool get _isOptimisticReactActive =>
      _optimisticReactedAt != null &&
      DateTime.now().difference(_optimisticReactedAt!) < _optimisticTtl;

  bool get _isOptimisticRepostActive =>
      _optimisticRepostedAt != null &&
      DateTime.now().difference(_optimisticRepostedAt!) < _optimisticTtl;

  bool get _isOptimisticZapActive =>
      _optimisticZappedAt != null &&
      DateTime.now().difference(_optimisticZappedAt!) < _optimisticTtl;

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
    on<InteractionBookmarkChanged>(_onBookmarkChanged);
    on<InteractionBookmarkToggled>(_onBookmarkToggled);
    on<InteractionPinChanged>(_onPinChanged);
    on<InteractionPinToggled>(_onPinToggled);
  }

  Future<void> _onInitialized(
      InteractionInitialized event, Emitter<InteractionState> emit) async {
    note = event.note;
    _interactionService.setCurrentUser(currentUserHex);

    final cached = _interactionService.getCachedInteractions(noteId);
    final isBookmarked =
        EncryptedBookmarkService.instance.isBookmarked(noteId);
    final isPinned = PinnedNotesService.instance.isPinned(noteId);

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

      initialCounts = InteractionCounts(
        reactions: reactionCount,
        reposts: repostCount,
        replies: replyCount,
        zapAmount: zapCount,
        hasReacted: hasReacted,
        hasReposted: hasReposted,
        hasZapped: hasZapped,
      );
      emit(InteractionLoaded(
        reactionCount: reactionCount,
        repostCount: repostCount,
        replyCount: replyCount,
        zapAmount: zapCount,
        hasReacted: hasReacted,
        hasReposted: hasReposted,
        hasZapped: hasZapped,
        isBookmarked: isBookmarked,
        isPinned: isPinned,
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
        isBookmarked: isBookmarked,
        isPinned: isPinned,
      ));
    } else {
      emit(InteractionLoaded(
        isBookmarked: isBookmarked,
        isPinned: isPinned,
      ));
    }

    _subscription?.cancel();
    _subscription = _interactionService
        .streamInteractions(noteId, initialCounts: initialCounts)
        .listen(
          (counts) => add(InteractionCountsUpdated(counts)),
        );

    _bookmarkSubscription?.cancel();
    _bookmarkSubscription = EncryptedBookmarkService.instance.changes.listen(
      (_) {
        if (isClosed) return;
        final next = EncryptedBookmarkService.instance.isBookmarked(noteId);
        final cur = state is InteractionLoaded
            ? (state as InteractionLoaded).isBookmarked
            : false;
        if (cur != next) add(InteractionBookmarkChanged(next));
      },
    );

    _pinSubscription?.cancel();
    _pinSubscription =
        PinnedNotesService.instance.pinnedNoteIdsStream.listen((_) {
      if (isClosed) return;
      final next = PinnedNotesService.instance.isPinned(noteId);
      final cur = state is InteractionLoaded
          ? (state as InteractionLoaded).isPinned
          : false;
      if (cur != next) add(InteractionPinChanged(next));
    });
  }

  void _onCountsUpdated(
      InteractionCountsUpdated event, Emitter<InteractionState> emit) {
    final currentState =
        state is InteractionLoaded ? (state as InteractionLoaded) : null;

    final hasReacted = _isOptimisticReactActive ||
        event.counts.hasReacted ||
        _interactionService.hasReacted(noteId);
    final hasReposted = _isOptimisticRepostActive ||
        event.counts.hasReposted ||
        _interactionService.hasReposted(noteId);
    final hasZapped = _isOptimisticZapActive ||
        event.counts.hasZapped ||
        _interactionService.hasZapped(noteId);

    final isBookmarked = currentState?.isBookmarked ??
        EncryptedBookmarkService.instance.isBookmarked(noteId);
    final isPinned = currentState?.isPinned ??
        PinnedNotesService.instance.isPinned(noteId);

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
      isBookmarked: isBookmarked,
      isPinned: isPinned,
    ));
  }

  void _onBookmarkChanged(
      InteractionBookmarkChanged event, Emitter<InteractionState> emit) {
    final current =
        state is InteractionLoaded ? (state as InteractionLoaded) : null;
    if (current == null) return;
    if (current.isBookmarked == event.isBookmarked) return;
    emit(current.copyWith(isBookmarked: event.isBookmarked));
  }

  Future<void> _onBookmarkToggled(
      InteractionBookmarkToggled event, Emitter<InteractionState> emit) async {
    final current =
        state is InteractionLoaded ? (state as InteractionLoaded) : null;
    if (current == null) return;
    final svc = EncryptedBookmarkService.instance;
    if (current.isBookmarked) {
      svc.removeBookmark(noteId);
    } else {
      svc.addBookmark(noteId);
    }
    emit(current.copyWith(isBookmarked: !current.isBookmarked));
    try {
      await _syncService.publishBookmark(
        bookmarkedEventIds: svc.bookmarkedEventIds,
      );
    } catch (_) {}
  }

  void _onPinChanged(
      InteractionPinChanged event, Emitter<InteractionState> emit) {
    final current =
        state is InteractionLoaded ? (state as InteractionLoaded) : null;
    if (current == null) return;
    if (current.isPinned == event.isPinned) return;
    emit(current.copyWith(isPinned: event.isPinned));
  }

  Future<void> _onPinToggled(
      InteractionPinToggled event, Emitter<InteractionState> emit) async {
    final current =
        state is InteractionLoaded ? (state as InteractionLoaded) : null;
    if (current == null) return;
    final svc = PinnedNotesService.instance;
    final wasPinned = current.isPinned;
    if (wasPinned) {
      svc.unpinNote(noteId);
    } else {
      svc.pinNote(noteId);
    }
    emit(current.copyWith(isPinned: !wasPinned));
    try {
      await _syncService.publishPinnedNotes(
        pinnedNoteIds: svc.pinnedNoteIds,
      );
    } catch (_) {
      if (wasPinned) {
        svc.pinNote(noteId);
      } else {
        svc.unpinNote(noteId);
      }
      if (!isClosed && state is InteractionLoaded) {
        emit((state as InteractionLoaded).copyWith(isPinned: wasPinned));
      }
    }
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

    _optimisticReactedAt = DateTime.now();
    _interactionService.markReacted(noteId);

    emit(currentState.copyWith(
      hasReacted: true,
      reactionCount: currentState.reactionCount + 1,
    ));

    try {
      final noteAuthor = note?['pubkey'] as String? ?? '';
      await _syncService.publishReaction(
        targetEventId: noteId,
        targetAuthor: noteAuthor,
        content: '+',
      );
    } catch (e) {
      debugPrint('[InteractionBloc] Reaction failed: $e');
      _interactionService.markUnreacted(noteId);
      if (!isClosed && state is InteractionLoaded) {
        final s = state as InteractionLoaded;
        emit(s.copyWith(
          hasReacted: false,
          reactionCount: (s.reactionCount - 1).clamp(0, double.maxFinite.toInt()),
        ));
      }
      await _interactionService.refreshInteractions(noteId);
    }
  }

  Future<void> _onRepost(
      InteractionRepostRequested event, Emitter<InteractionState> emit) async {
    final currentState =
        state is InteractionLoaded ? (state as InteractionLoaded) : null;
    if (currentState == null || currentState.hasReposted) return;
    if (_interactionService.hasReposted(noteId)) return;

    _optimisticRepostedAt = DateTime.now();
    _interactionService.markReposted(noteId);

    emit(currentState.copyWith(
      hasReposted: true,
      repostCount: currentState.repostCount + 1,
    ));

    try {
      final noteAuthor = note?['pubkey'] as String? ?? '';
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
    } catch (e) {
      debugPrint('[InteractionBloc] Undo repost failed: $e');
      _interactionService.markReposted(noteId);
      await _interactionService.refreshInteractions(noteId);
    }
  }

  void _onZapStarted(
      InteractionZapStarted event, Emitter<InteractionState> emit) {
    final currentState =
        state is InteractionLoaded ? (state as InteractionLoaded) : null;
    if (currentState == null) return;

    _optimisticZappedAt = DateTime.now();

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

    _optimisticZappedAt = DateTime.now();
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

    _optimisticZappedAt = null;

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
      if (isClosed) return;
      final currentState =
          state is InteractionLoaded ? (state as InteractionLoaded) : null;
      if (currentState != null) {
        emit(currentState.copyWith(noteDeleted: true));
      } else {
        emit(const InteractionLoaded(noteDeleted: true));
      }
    } catch (e) {
      debugPrint('[InteractionBloc] Note deletion failed: $e');
    }
  }

  Map<String, dynamic>? getNoteForActions() => note;

  @override
  Future<void> close() {
    _subscription?.cancel();
    _bookmarkSubscription?.cancel();
    _pinSubscription?.cancel();
    _interactionService.disposeStream(noteId);
    return super.close();
  }
}
