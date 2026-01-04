import 'dart:async';
import '../../core/base/base_view_model.dart';
import '../../data/repositories/note_repository.dart';
import '../../models/note_model.dart';

class InteractionState {
  final int reactionCount;
  final int repostCount;
  final int replyCount;
  final int zapAmount;
  final bool hasReacted;
  final bool hasReposted;
  final bool hasZapped;

  const InteractionState({
    this.reactionCount = 0,
    this.repostCount = 0,
    this.replyCount = 0,
    this.zapAmount = 0,
    this.hasReacted = false,
    this.hasReposted = false,
    this.hasZapped = false,
  });

  InteractionState copyWith({
    int? reactionCount,
    int? repostCount,
    int? replyCount,
    int? zapAmount,
    bool? hasReacted,
    bool? hasReposted,
    bool? hasZapped,
  }) {
    return InteractionState(
      reactionCount: reactionCount ?? this.reactionCount,
      repostCount: repostCount ?? this.repostCount,
      replyCount: replyCount ?? this.replyCount,
      zapAmount: zapAmount ?? this.zapAmount,
      hasReacted: hasReacted ?? this.hasReacted,
      hasReposted: hasReposted ?? this.hasReposted,
      hasZapped: hasZapped ?? this.hasZapped,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InteractionState &&
          reactionCount == other.reactionCount &&
          repostCount == other.repostCount &&
          replyCount == other.replyCount &&
          zapAmount == other.zapAmount &&
          hasReacted == other.hasReacted &&
          hasReposted == other.hasReposted &&
          hasZapped == other.hasZapped;

  @override
  int get hashCode => Object.hash(
        reactionCount,
        repostCount,
        replyCount,
        zapAmount,
        hasReacted,
        hasReposted,
        hasZapped,
      );
}

class InteractionBarViewModel extends BaseViewModel {
  final NoteRepository _noteRepository;
  final String noteId;
  final String currentUserNpub;
  NoteModel? note;

  InteractionBarViewModel({
    required NoteRepository noteRepository,
    required this.noteId,
    required this.currentUserNpub,
    this.note,
  }) : _noteRepository = noteRepository {
    _initializeState();
    _setupStreamListener();
  }

  InteractionState _state = const InteractionState();
  InteractionState get state => _state;

  DateTime? _lastUpdateTime;
  static const Duration _updateDebounce = Duration(milliseconds: 1000);
  static const Duration _updateDelay = Duration(milliseconds: 500);

  void _initializeState() {
    final computedState = _computeInitialState();
    if (_state != computedState) {
      _state = computedState;
      safeNotifyListeners();
    }
  }

  InteractionState _computeInitialState() {
    final note = _findNote();
    if (note == null) {
      return InteractionState(
        reactionCount: 0,
        repostCount: 0,
        replyCount: 0,
        zapAmount: 0,
        hasReacted: _noteRepository.hasUserReacted(noteId, currentUserNpub),
        hasReposted: _noteRepository.hasUserReposted(noteId, currentUserNpub),
        hasZapped: _noteRepository.hasUserZapped(noteId, currentUserNpub),
      );
    }

    return InteractionState(
      reactionCount: note.reactionCount,
      repostCount: note.repostCount,
      replyCount: note.replyCount,
      zapAmount: note.zapAmount,
      hasReacted: _noteRepository.hasUserReacted(noteId, currentUserNpub),
      hasReposted: _noteRepository.hasUserReposted(noteId, currentUserNpub),
      hasZapped: _noteRepository.hasUserZapped(noteId, currentUserNpub),
    );
  }

  NoteModel? _findNote() {
    if (note != null) {
      if (note!.id == noteId) {
        return note;
      }

      if (note!.isRepost && note!.rootId == noteId) {
        final allNotes = _noteRepository.currentNotes;
        for (final n in allNotes) {
          if (n.id == noteId) {
            return n;
          }
        }
        return note;
      }
    }

    final allNotes = _noteRepository.currentNotes;
    for (final n in allNotes) {
      if (n.id == noteId) {
        return n;
      }
    }

    return null;
  }

  void _setupStreamListener() {
    addSubscription(
      _noteRepository.notesStream.listen((notes) {
        if (isDisposed) return;

        final hasRelevantUpdate = notes.any((note) => note.id == noteId);
        if (!hasRelevantUpdate) return;

        final updateTime = DateTime.now();
        if (_lastUpdateTime != null &&
            updateTime.difference(_lastUpdateTime!) < _updateDebounce) {
          return;
        }

        _lastUpdateTime = updateTime;

        Future.delayed(_updateDelay, () {
          if (isDisposed || _lastUpdateTime != updateTime) return;
          _updateState();
        });
      }),
    );
  }

  void _updateState() {
    if (isDisposed) return;

    final currentState = _state;
    final newState = _computeInitialState();

    final safeNewState = InteractionState(
      reactionCount: newState.reactionCount >= currentState.reactionCount
          ? newState.reactionCount
          : currentState.reactionCount,
      repostCount: newState.repostCount >= currentState.repostCount
          ? newState.repostCount
          : currentState.repostCount,
      replyCount: newState.replyCount >= currentState.replyCount
          ? newState.replyCount
          : currentState.replyCount,
      zapAmount: newState.zapAmount >= currentState.zapAmount
          ? newState.zapAmount
          : currentState.zapAmount,
      hasReacted: newState.hasReacted || currentState.hasReacted,
      hasReposted: newState.hasReposted || currentState.hasReposted,
      hasZapped: newState.hasZapped || currentState.hasZapped,
    );

    if (currentState != safeNewState) {
      _state = safeNewState;
      safeNotifyListeners();
    }
  }

  void refreshState() {
    _updateState();
  }

  void updateNote(NoteModel? newNote) {
    if (note != newNote) {
      note = newNote;
      _updateState();
    }
  }

  Future<void> reactToNote() async {
    if (_state.hasReacted || isDisposed) return;

    final currentState = _state;
    _state = currentState.copyWith(hasReacted: true);
    safeNotifyListeners();

    try {
      final result = await _noteRepository.reactToNote(noteId, '+');
      if (isDisposed) return;

      result.fold(
        (_) {},
        (error) {
          if (!isDisposed) {
            _state = currentState;
            safeNotifyListeners();
          }
        },
      );
    } catch (e) {
      if (!isDisposed) {
        _state = currentState;
        safeNotifyListeners();
      }
    }
  }

  Future<void> repostNote() async {
    if (note == null || isDisposed) return;

    final noteToRepost = _findNote() ?? note!;
    final currentState = _state;

    _state = currentState.copyWith(hasReposted: true);
    safeNotifyListeners();

    try {
      final result = await _noteRepository.repostNote(noteToRepost.id);
      if (isDisposed) return;

      result.fold(
        (_) {},
        (error) {
          if (!isDisposed) {
            _state = currentState;
            safeNotifyListeners();
          }
        },
      );
    } catch (e) {
      if (!isDisposed) {
        _state = currentState;
        safeNotifyListeners();
      }
    }
  }

  Future<void> deleteRepost() async {
    if (isDisposed) return;

    final currentState = _state;

    try {
      final result = await _noteRepository.deleteRepost(noteId);
      if (isDisposed) return;

      result.fold(
        (_) {
          if (!isDisposed) {
            _state = currentState.copyWith(hasReposted: false);
            safeNotifyListeners();
          }
        },
        (error) {
          if (!isDisposed) {
            _state = currentState;
            safeNotifyListeners();
          }
        },
      );
    } catch (e) {
      if (!isDisposed) {
        _state = currentState;
        safeNotifyListeners();
      }
    }
  }

  Future<void> deleteNote() async {
    if (isDisposed) return;

    try {
      final result = await _noteRepository.deleteNote(noteId);
      if (isDisposed) return;

      result.fold(
        (_) {},
        (error) {
          if (!isDisposed) {
            safeNotifyListeners();
          }
        },
      );
    } catch (e) {
      if (!isDisposed) {
        safeNotifyListeners();
      }
    }
  }

  NoteModel? getNoteForActions() {
    return _findNote() ?? note;
  }
}
