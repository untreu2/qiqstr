import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import 'thread_event.dart';
import 'thread_state.dart';

class ThreadBloc extends Bloc<ThreadEvent, ThreadState> {
  final NoteRepository _noteRepository;
  final UserRepository _userRepository;
  final AuthRepository _authRepository;

  final List<StreamSubscription> _subscriptions = [];

  ThreadBloc({
    required NoteRepository noteRepository,
    required UserRepository userRepository,
    required AuthRepository authRepository,
  })  : _noteRepository = noteRepository,
        _userRepository = userRepository,
        _authRepository = authRepository,
        super(const ThreadInitial()) {
    on<ThreadLoadRequested>(_onThreadLoaded);
    on<ThreadRefreshed>(_onThreadRefreshed);
    on<ThreadFocusedNoteChanged>(_onThreadFocusedNoteChanged);

    _subscribeToThreadUpdates();
  }

  void _subscribeToThreadUpdates() {
    _subscriptions.add(
      _noteRepository.notesStream.listen((allNotes) {
        if (state is ThreadLoaded) {
          final currentState = state as ThreadLoaded;
          final rootNoteId = currentState.rootNote['id'] as String? ?? '';
          final replyIds = currentState.replies
              .map((r) => r['id'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toSet();
          final threadNoteIds = {rootNoteId, ...replyIds};

          final updatedNotes = allNotes.where((n) {
            final noteId = n['id'] as String? ?? '';
            return noteId.isNotEmpty && threadNoteIds.contains(noteId);
          }).toList();

          if (updatedNotes.isNotEmpty) {
            final hasNewReplies = updatedNotes.any((note) {
              final noteId = note['id'] as String? ?? '';
              final noteParentId = note['parentId'] as String?;
              return noteId.isNotEmpty &&
                  noteParentId != null &&
                  noteParentId == rootNoteId &&
                  !replyIds.contains(noteId);
            });

            if (hasNewReplies) {
              add(const ThreadRefreshed());
            }
          }
        }
      }),
    );
  }

  Future<void> _onThreadLoaded(
    ThreadLoadRequested event,
    Emitter<ThreadState> emit,
  ) async {
    emit(const ThreadLoading());

    try {
      final cachedRootResult =
          await _noteRepository.getNoteById(event.rootNoteId);
      final cachedRepliesResult =
          await _noteRepository.getThreadReplies(event.rootNoteId);

      final rootNote = cachedRootResult.fold((n) => n, (_) => null);
      final replies =
          cachedRepliesResult.fold((r) => r, (_) => <Map<String, dynamic>>[]);

      if (rootNote == null) {
        emit(const ThreadError('Note not found'));
        return;
      }

      final structure = _buildThreadStructure(rootNote, replies);

      final currentUserResult = await _authRepository.getCurrentUserNpub();
      final currentUserNpub =
          currentUserResult.fold((n) => n, (_) => null) ?? '';

      Map<String, dynamic>? currentUser;
      if (currentUserNpub.isNotEmpty) {
        final userResult = await _userRepository.getCurrentUser();
        currentUser = userResult.fold((u) => u, (_) => null);
      }

      final userProfiles = <String, Map<String, dynamic>>{};

      Map<String, dynamic>? focusedNote;
      if (event.focusedNoteId != null) {
        final focusedResult =
            await _noteRepository.getNoteById(event.focusedNoteId!);
        focusedNote = focusedResult.fold((n) => n, (_) => null);
      }

      emit(ThreadLoaded(
        rootNote: rootNote,
        replies: replies,
        threadStructure: structure,
        focusedNote: focusedNote,
        userProfiles: userProfiles,
        rootNoteId: event.rootNoteId,
        focusedNoteId: event.focusedNoteId,
        currentUserNpub: currentUserNpub,
        currentUser: currentUser,
      ));

      _fetchInteractionsForThreadNotes(rootNote, replies);
      _loadUserProfiles([rootNote, ...replies], emit);

      final freshRepliesResult = await _noteRepository
          .getThreadReplies(event.rootNoteId, fetchFromRelays: true);
      freshRepliesResult.fold(
        (freshReplies) {
          if (freshReplies.length != replies.length) {
            final newStructure = _buildThreadStructure(rootNote, freshReplies);
            if (state is ThreadLoaded) {
              final currentState = state as ThreadLoaded;
              emit(currentState.copyWith(
                replies: freshReplies,
                threadStructure: newStructure,
              ));
              _loadUserProfiles([rootNote, ...freshReplies], emit);
            }
          }
        },
        (_) {},
      );
    } catch (e) {
      emit(ThreadError('Failed to load thread: ${e.toString()}'));
    }
  }

  Future<void> _onThreadRefreshed(
    ThreadRefreshed event,
    Emitter<ThreadState> emit,
  ) async {
    if (state is ThreadLoaded) {
      final currentState = state as ThreadLoaded;
      add(ThreadLoadRequested(
          rootNoteId: currentState.rootNoteId,
          focusedNoteId: currentState.focusedNoteId));
    }
  }

  void _onThreadFocusedNoteChanged(
    ThreadFocusedNoteChanged event,
    Emitter<ThreadState> emit,
  ) {
    if (state is ThreadLoaded) {
      final currentState = state as ThreadLoaded;
      if (event.noteId == null) {
        emit(currentState.copyWith(focusedNote: null, focusedNoteId: null));
        return;
      }

      final structure = currentState.threadStructure;
      final note = structure.getNote(event.noteId!);
      if (note != null) {
        emit(currentState.copyWith(
            focusedNote: note, focusedNoteId: event.noteId));
      } else {
        _loadFocusedNoteFromCache(event.noteId!, emit);
      }
    }
  }

  Future<void> _loadFocusedNoteFromCache(
      String noteId, Emitter<ThreadState> emit) async {
    final result = await _noteRepository.getNoteById(noteId);
    result.fold(
      (note) {
        if (state is ThreadLoaded) {
          final currentState = state as ThreadLoaded;
          emit(currentState.copyWith(focusedNote: note, focusedNoteId: noteId));
        }
      },
      (_) {},
    );
  }

  Future<void> _loadUserProfiles(
      List<Map<String, dynamic>> notes, Emitter<ThreadState> emit) async {
    if (state is! ThreadLoaded) return;

    final currentState = state as ThreadLoaded;
    final authorIds = notes
        .map((n) => n['author'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final missingAuthorIds = authorIds
        .where((id) => !currentState.userProfiles.containsKey(id))
        .toList();

    if (missingAuthorIds.isEmpty) return;

    final updatedProfiles =
        Map<String, Map<String, dynamic>>.from(currentState.userProfiles);
    var hasUpdates = false;

    for (final authorId in missingAuthorIds) {
      final userResult = await _userRepository.getUserProfile(authorId);
      userResult.fold(
        (user) {
          updatedProfiles[authorId] = user;
          hasUpdates = true;
        },
        (_) {
          // Silently handle error - user fetch failure is acceptable
        },
      );
    }

    if (hasUpdates && state is ThreadLoaded) {
      final updatedState = state as ThreadLoaded;
      emit(updatedState.copyWith(userProfiles: updatedProfiles));
    }
  }

  void _fetchInteractionsForThreadNotes(
      Map<String, dynamic> rootNote, List<Map<String, dynamic>> replies) {
    final noteIds = <String>[];
    final rootNoteId = rootNote['id'] as String? ?? '';
    if (rootNoteId.isNotEmpty) {
      noteIds.add(rootNoteId);
    }
    for (final reply in replies) {
      final replyId = reply['id'] as String? ?? '';
      if (replyId.isNotEmpty) {
        noteIds.add(replyId);
      }
    }
    if (noteIds.isNotEmpty) {
      _noteRepository.fetchInteractionsForNoteIds(noteIds);
    }
  }

  ThreadStructure _buildThreadStructure(
      Map<String, dynamic> rootNote, List<Map<String, dynamic>> replies) {
    final Map<String, List<Map<String, dynamic>>> childrenMap = {};
    final rootNoteId = rootNote['id'] as String? ?? '';
    final Map<String, Map<String, dynamic>> notesMap = {rootNoteId: rootNote};

    for (final reply in replies) {
      final replyId = reply['id'] as String? ?? '';
      if (replyId.isNotEmpty) {
        notesMap[replyId] = reply;
      }
    }

    for (final reply in replies) {
      final replyId = reply['id'] as String? ?? '';
      if (replyId.isEmpty) continue;

      final parentId = reply['parentId'] as String? ?? rootNoteId;
      childrenMap.putIfAbsent(parentId, () => []);
      childrenMap[parentId]!.add(reply);
    }

    for (final children in childrenMap.values) {
      children.sort((a, b) {
        final aTimestamp = a['timestamp'] as DateTime? ?? DateTime(2000);
        final bTimestamp = b['timestamp'] as DateTime? ?? DateTime(2000);
        return aTimestamp.compareTo(bTimestamp);
      });
    }

    return ThreadStructure(
      rootNote: rootNote,
      childrenMap: childrenMap,
      notesMap: notesMap,
      totalReplies: replies.length,
    );
  }

  @override
  Future<void> close() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    return super.close();
  }
}
