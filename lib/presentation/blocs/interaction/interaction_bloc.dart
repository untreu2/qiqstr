import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/note_repository.dart';
import 'interaction_event.dart';
import 'interaction_state.dart';

class InteractionBloc extends Bloc<InteractionEvent, InteractionState> {
  final NoteRepository _noteRepository;
  final String noteId;
  final String currentUserNpub;
  Map<String, dynamic>? note;

  StreamSubscription<List<Map<String, dynamic>>>? _notesSubscription;
  DateTime? _lastUpdateTime;
  static const Duration _updateDebounce = Duration(milliseconds: 1000);
  static const Duration _updateDelay = Duration(milliseconds: 500);

  InteractionBloc({
    required NoteRepository noteRepository,
    required this.noteId,
    required this.currentUserNpub,
    this.note,
  })  : _noteRepository = noteRepository,
        super(const InteractionInitial()) {
    on<InteractionInitialized>(_onInteractionInitialized);
    on<InteractionNoteUpdated>(_onInteractionNoteUpdated);
    on<InteractionStateRefreshed>(_onInteractionStateRefreshed);
    on<InteractionReactRequested>(_onInteractionReactRequested);
    on<InteractionRepostRequested>(_onInteractionRepostRequested);
    on<InteractionRepostDeleted>(_onInteractionRepostDeleted);
    on<InteractionNoteDeleted>(_onInteractionNoteDeleted);
  }

  Future<void> _onInteractionInitialized(
    InteractionInitialized event,
    Emitter<InteractionState> emit,
  ) async {
    note = event.note;
    final initialState = _computeState();
    emit(initialState);

    _notesSubscription?.cancel();
    _notesSubscription = _noteRepository.notesStream.listen((notes) {
      final hasRelevantUpdate = notes.any((n) {
        final id = n['id'] as String? ?? '';
        return id.isNotEmpty && id == noteId;
      });
      if (!hasRelevantUpdate) return;

      final updateTime = DateTime.now();
      if (_lastUpdateTime != null && updateTime.difference(_lastUpdateTime!) < _updateDebounce) {
        return;
      }

      _lastUpdateTime = updateTime;

      Future.delayed(_updateDelay, () {
        if (_lastUpdateTime != updateTime) return;
        add(const InteractionStateRefreshed());
      });
    });
  }

  void _onInteractionNoteUpdated(
    InteractionNoteUpdated event,
    Emitter<InteractionState> emit,
  ) {
    if (note != event.note) {
      note = event.note;
      final newState = _computeState();
      if (state != newState) {
        emit(newState);
      }
    }
  }

  void _onInteractionStateRefreshed(
    InteractionStateRefreshed event,
    Emitter<InteractionState> emit,
  ) {
    final currentState = state is InteractionLoaded ? (state as InteractionLoaded) : null;
    final newState = _computeState();

    if (currentState != null) {
      final safeNewState = InteractionLoaded(
        reactionCount: newState.reactionCount >= currentState.reactionCount ? newState.reactionCount : currentState.reactionCount,
        repostCount: newState.repostCount >= currentState.repostCount ? newState.repostCount : currentState.repostCount,
        replyCount: newState.replyCount >= currentState.replyCount ? newState.replyCount : currentState.replyCount,
        zapAmount: newState.zapAmount >= currentState.zapAmount ? newState.zapAmount : currentState.zapAmount,
        hasReacted: newState.hasReacted || currentState.hasReacted,
        hasReposted: newState.hasReposted || currentState.hasReposted,
        hasZapped: newState.hasZapped || currentState.hasZapped,
      );

      if (currentState != safeNewState) {
        emit(safeNewState);
      }
    } else {
      emit(newState);
    }
  }

  Future<void> _onInteractionReactRequested(
    InteractionReactRequested event,
    Emitter<InteractionState> emit,
  ) async {
    final currentState = state is InteractionLoaded ? (state as InteractionLoaded) : null;
    if (currentState == null || currentState.hasReacted) return;

    emit(currentState.copyWith(hasReacted: true));

    final result = await _noteRepository.reactToNote(noteId, '+');
    result.fold(
      (_) {},
      (error) {
        emit(currentState);
      },
    );
  }

  Future<void> _onInteractionRepostRequested(
    InteractionRepostRequested event,
    Emitter<InteractionState> emit,
  ) async {
    final noteToRepost = _findNote() ?? note;
    if (noteToRepost == null) return;

    final currentState = state is InteractionLoaded ? (state as InteractionLoaded) : null;
    if (currentState == null) return;

    emit(currentState.copyWith(hasReposted: true));

    final noteIdToRepost = noteToRepost['id'] as String? ?? '';
    if (noteIdToRepost.isEmpty) return;
    final result = await _noteRepository.repostNote(noteIdToRepost);
    result.fold(
      (_) {},
      (error) {
        emit(currentState);
      },
    );
  }

  Future<void> _onInteractionRepostDeleted(
    InteractionRepostDeleted event,
    Emitter<InteractionState> emit,
  ) async {
    final currentState = state is InteractionLoaded ? (state as InteractionLoaded) : null;
    if (currentState == null) return;

    final previousState = currentState;

    final result = await _noteRepository.deleteRepost(noteId);
    result.fold(
      (_) {
        emit(currentState.copyWith(hasReposted: false));
      },
      (error) {
        emit(previousState);
      },
    );
  }

  Future<void> _onInteractionNoteDeleted(
    InteractionNoteDeleted event,
    Emitter<InteractionState> emit,
  ) async {
    final result = await _noteRepository.deleteNote(noteId);
    result.fold(
      (_) {},
      (error) {},
    );
  }

  Map<String, dynamic>? _findNote() {
    if (note != null) {
      final noteIdValue = note!['id'] as String? ?? '';
      if (noteIdValue.isNotEmpty && noteIdValue == noteId) {
        return note;
      }

      final isRepost = note!['isRepost'] as bool? ?? false;
      final rootId = note!['rootId'] as String?;
      if (isRepost && rootId != null && rootId == noteId) {
        final allNotes = _noteRepository.currentNotes;
        for (final n in allNotes) {
          final nId = n['id'] as String? ?? '';
          if (nId.isNotEmpty && nId == noteId) {
            return n;
          }
        }
        return note;
      }
    }

    final allNotes = _noteRepository.currentNotes;
    for (final n in allNotes) {
      final nId = n['id'] as String? ?? '';
      if (nId.isNotEmpty && nId == noteId) {
        return n;
      }
    }

    return null;
  }

  InteractionLoaded _computeState() {
    final foundNote = _findNote();

    String targetNoteId = noteId;
    if (foundNote != null) {
      final isRepost = foundNote['isRepost'] as bool? ?? false;
      if (isRepost) {
        final rootId = foundNote['rootId'] as String?;
        if (rootId != null && rootId.isNotEmpty) {
          targetNoteId = rootId;
        }
      }
    }

    return InteractionLoaded(
      reactionCount: _noteRepository.getReactionCount(targetNoteId),
      repostCount: _noteRepository.getRepostCount(targetNoteId),
      replyCount: _noteRepository.getReplyCount(targetNoteId),
      zapAmount: _noteRepository.getZapAmount(targetNoteId),
      hasReacted: _noteRepository.hasUserReacted(targetNoteId, currentUserNpub),
      hasReposted: _noteRepository.hasUserReposted(targetNoteId, currentUserNpub),
      hasZapped: _noteRepository.hasUserZapped(targetNoteId, currentUserNpub),
    );
  }

  Map<String, dynamic>? getNoteForActions() {
    return _findNote() ?? note;
  }

  @override
  Future<void> close() {
    _notesSubscription?.cancel();
    return super.close();
  }
}
