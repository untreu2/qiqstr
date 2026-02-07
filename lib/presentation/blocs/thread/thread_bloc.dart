import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../domain/entities/feed_note.dart';
import 'thread_event.dart';
import 'thread_state.dart';

class ThreadBloc extends Bloc<ThreadEvent, ThreadState> {
  final FeedRepository _feedRepository;
  final ProfileRepository _profileRepository;
  final SyncService _syncService;
  final AuthService _authService;

  String? _currentRootNoteId;
  StreamSubscription<List<FeedNote>>? _repliesSubscription;

  ThreadBloc({
    required FeedRepository feedRepository,
    required ProfileRepository profileRepository,
    required SyncService syncService,
    required AuthService authService,
  })  : _feedRepository = feedRepository,
        _profileRepository = profileRepository,
        _syncService = syncService,
        _authService = authService,
        super(const ThreadInitial()) {
    on<ThreadLoadRequested>(_onThreadLoaded);
    on<ThreadRefreshed>(_onThreadRefreshed);
    on<ThreadFocusedNoteChanged>(_onThreadFocusedNoteChanged);
    on<ThreadProfilesUpdated>(_onThreadProfilesUpdated);
    on<_ThreadRepliesUpdated>(_onThreadRepliesUpdated);
  }

  void _onThreadProfilesUpdated(
    ThreadProfilesUpdated event,
    Emitter<ThreadState> emit,
  ) {
    if (state is ThreadLoaded) {
      emit((state as ThreadLoaded).copyWith(userProfiles: event.profiles));
    }
  }

  Future<void> _onThreadLoaded(
    ThreadLoadRequested event,
    Emitter<ThreadState> emit,
  ) async {
    _currentRootNoteId = event.rootNoteId;

    try {
      String currentUserHex = _authService.currentUserPubkeyHex ?? '';
      Map<String, dynamic>? currentUser;

      if (currentUserHex.isNotEmpty) {
        final profile = await _profileRepository.getProfile(currentUserHex);
        currentUser = profile?.toMap();
      }

      final cachedRootNote = await _feedRepository.getNote(event.rootNoteId);

      if (cachedRootNote != null) {
        final rootNoteMap = cachedRootNote.toMap();

        final cachedReplies =
            await _feedRepository.getReplies(event.rootNoteId);
        final cachedRepliesMaps = cachedReplies.map((r) => r.toMap()).toList();
        final initialStructure =
            _buildThreadStructure(rootNoteMap, cachedRepliesMaps);

        Map<String, dynamic>? focusedNote;
        if (event.focusedNoteId != null) {
          focusedNote = initialStructure.getNote(event.focusedNoteId!);
          focusedNote ??= rootNoteMap;
        }

        emit(ThreadLoaded(
          rootNote: rootNoteMap,
          replies: cachedRepliesMaps,
          threadStructure: initialStructure,
          focusedNote: focusedNote,
          userProfiles: const {},
          rootNoteId: event.rootNoteId,
          focusedNoteId: event.focusedNoteId,
          currentUserHex: currentUserHex,
          currentUser: currentUser,
        ));

        _watchReplies(event.rootNoteId);
        _syncInBackground(event.rootNoteId);
        _loadUserProfilesInBackground([rootNoteMap, ...cachedRepliesMaps]);
      } else {
        emit(const ThreadLoading());
        await _syncService.syncNote(event.rootNoteId);

        final freshRootNote = await _feedRepository.getNote(event.rootNoteId);
        if (freshRootNote == null) {
          emit(const ThreadError('Note not found'));
          return;
        }

        final freshRootNoteMap = freshRootNote.toMap();

        final cachedReplies =
            await _feedRepository.getReplies(event.rootNoteId);
        final cachedRepliesMaps = cachedReplies.map((r) => r.toMap()).toList();
        final initialStructure =
            _buildThreadStructure(freshRootNoteMap, cachedRepliesMaps);

        Map<String, dynamic>? focusedNote;
        if (event.focusedNoteId != null) {
          focusedNote = initialStructure.getNote(event.focusedNoteId!);
          focusedNote ??= freshRootNoteMap;
        }

        emit(ThreadLoaded(
          rootNote: freshRootNoteMap,
          replies: cachedRepliesMaps,
          threadStructure: initialStructure,
          focusedNote: focusedNote,
          userProfiles: const {},
          rootNoteId: event.rootNoteId,
          focusedNoteId: event.focusedNoteId,
          currentUserHex: currentUserHex,
          currentUser: currentUser,
        ));

        _watchReplies(event.rootNoteId);
        _syncInBackground(event.rootNoteId);
        _loadUserProfilesInBackground([freshRootNoteMap, ...cachedRepliesMaps]);
      }
    } catch (e) {
      emit(ThreadError('Failed to load thread: ${e.toString()}'));
    }
  }

  void _watchReplies(String rootNoteId) {
    _repliesSubscription?.cancel();
    _repliesSubscription =
        _feedRepository.watchReplies(rootNoteId).listen((replies) {
      if (isClosed) return;
      add(_ThreadRepliesUpdated(replies));
    });
  }

  void _onThreadRepliesUpdated(
    _ThreadRepliesUpdated event,
    Emitter<ThreadState> emit,
  ) {
    if (state is! ThreadLoaded) return;
    final currentState = state as ThreadLoaded;

    final repliesMap = event.replies.map((r) => r.toMap()).toList();
    final structure = _buildThreadStructure(currentState.rootNote, repliesMap);

    emit(currentState.copyWith(
      replies: repliesMap,
      threadStructure: structure,
    ));

    _loadUserProfilesInBackground(repliesMap);
  }

  void _syncInBackground(String rootNoteId) {
    Future.microtask(() async {
      if (isClosed) return;
      try {
        await _syncService.syncReplies(rootNoteId);
      } catch (_) {}
    });
  }

  void _loadUserProfilesInBackground(List<Map<String, dynamic>> notes) {
    Future.microtask(() async {
      if (isClosed || state is! ThreadLoaded) return;

      final currentState = state as ThreadLoaded;
      final authorIds = notes
          .map((n) => n['author'] as String? ?? n['pubkey'] as String? ?? '')
          .where((id) =>
              id.isNotEmpty && !currentState.userProfiles.containsKey(id))
          .toSet()
          .toList();

      if (authorIds.isEmpty) return;

      try {
        final profiles = await _profileRepository.getProfiles(authorIds);
        if (isClosed) return;

        final updatedProfiles = <String, Map<String, dynamic>>{};
        for (final entry in profiles.entries) {
          updatedProfiles[entry.key] = entry.value.toMap();
          final npub = _authService.hexToNpub(entry.key);
          if (npub != null) {
            updatedProfiles[npub] = entry.value.toMap();
          }
        }

        if (updatedProfiles.isNotEmpty) {
          add(ThreadProfilesUpdated(updatedProfiles));
        }
      } catch (_) {}
    });
  }

  Future<void> _onThreadRefreshed(
    ThreadRefreshed event,
    Emitter<ThreadState> emit,
  ) async {
    if (_currentRootNoteId == null) return;
    try {
      await _syncService.syncReplies(_currentRootNoteId!);
    } catch (_) {}
  }

  void _onThreadFocusedNoteChanged(
    ThreadFocusedNoteChanged event,
    Emitter<ThreadState> emit,
  ) async {
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
        final fetchedNote = await _feedRepository.getNote(event.noteId!);
        if (fetchedNote != null && state is ThreadLoaded) {
          emit((state as ThreadLoaded).copyWith(
            focusedNote: fetchedNote.toMap(),
            focusedNoteId: event.noteId,
          ));
        }
      }
    }
  }

  ThreadStructure _buildThreadStructure(
      Map<String, dynamic> rootNote, List<Map<String, dynamic>> replies) {
    final Map<String, List<Map<String, dynamic>>> childrenMap = {};
    final rootNoteId = rootNote['id'] as String? ?? '';
    final Map<String, Map<String, dynamic>> notesMap = {rootNoteId: rootNote};
    final replyIds = <String>{};

    for (final reply in replies) {
      final replyId = reply['id'] as String? ?? '';
      if (replyId.isNotEmpty) {
        notesMap[replyId] = reply;
        replyIds.add(replyId);
      }
    }

    for (final reply in replies) {
      final replyId = reply['id'] as String? ?? '';
      if (replyId.isEmpty) continue;

      String parentId = reply['parentId'] as String? ?? '';
      final replyRootId = reply['rootId'] as String? ?? '';

      if (parentId.isEmpty && replyRootId.isNotEmpty) {
        parentId = replyRootId;
      }

      if (parentId.isEmpty) {
        parentId = rootNoteId;
      }

      if (parentId != rootNoteId &&
          !replyIds.contains(parentId) &&
          !notesMap.containsKey(parentId)) {
        parentId = rootNoteId;
      }

      childrenMap.putIfAbsent(parentId, () => []);
      childrenMap[parentId]!.add(reply);
    }

    for (final children in childrenMap.values) {
      children.sort((a, b) {
        final aTimestamp = a['created_at'] as int? ?? 0;
        final bTimestamp = b['created_at'] as int? ?? 0;
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
    _repliesSubscription?.cancel();
    return super.close();
  }
}

class _ThreadRepliesUpdated extends ThreadEvent {
  final List<FeedNote> replies;
  const _ThreadRepliesUpdated(this.replies);

  @override
  List<Object?> get props => [replies];
}
