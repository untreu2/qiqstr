import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/interaction_service.dart';
import '../../../data/services/rust_database_service.dart';
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
    on<_ThreadRepliesSyncCompleted>(_onThreadRepliesSyncCompleted);
    on<_ThreadCurrentUserLoaded>(_onThreadCurrentUserLoaded);
  }

  void _onThreadProfilesUpdated(
    ThreadProfilesUpdated event,
    Emitter<ThreadState> emit,
  ) {
    if (state is ThreadLoaded) {
      final currentState = state as ThreadLoaded;
      final merged = Map<String, Map<String, dynamic>>.from(
          currentState.userProfiles)
        ..addAll(event.profiles);
      emit(currentState.copyWith(userProfiles: merged));
    }
  }

  void _onThreadCurrentUserLoaded(
    _ThreadCurrentUserLoaded event,
    Emitter<ThreadState> emit,
  ) {
    if (state is ThreadLoaded) {
      final currentState = state as ThreadLoaded;
      final merged = Map<String, Map<String, dynamic>>.from(
          currentState.userProfiles)
        ..[currentState.currentUserHex] = event.profileMap;
      emit(currentState.copyWith(
        currentUser: event.profileMap,
        userProfiles: merged,
      ));
    }
  }

  Future<void> _onThreadLoaded(
    ThreadLoadRequested event,
    Emitter<ThreadState> emit,
  ) async {
    try {
      final currentUserHex = _authService.currentUserPubkeyHex ?? '';
      var rootNoteId = event.rootNoteId;

      var rootNoteRaw = await _feedRepository.getNoteRaw(rootNoteId);

      if (rootNoteRaw == null && event.initialNoteData != null) {
        rootNoteRaw =
            _stripRepostData(event.initialNoteData!, rootNoteId);
      }

      if (rootNoteRaw == null) {
        emit(const ThreadLoading());

        final resolvedRootId =
            await _syncService.resolveThreadRoot(rootNoteId);
        rootNoteId = resolvedRootId;
        rootNoteRaw = await _feedRepository.getNoteRaw(rootNoteId);

        if (rootNoteRaw == null) {
          emit(const ThreadError('Note not found'));
          return;
        }
      }

      _currentRootNoteId = rootNoteId;

      var ancestorChain = <Map<String, dynamic>>[];
      if (event.focusedNoteId != null &&
          event.focusedNoteId != rootNoteId) {
        ancestorChain =
            await _ensureAncestorChain(event.focusedNoteId!, rootNoteId);
      }

      final dbReplies =
          await _feedRepository.getRepliesRaw(rootNoteId);
      final replyIds =
          dbReplies.map((r) => r['id'] as String? ?? '').toSet();
      final allReplies = [...dbReplies];
      for (final ancestor in ancestorChain) {
        final aid = ancestor['id'] as String? ?? '';
        if (aid.isNotEmpty && aid != rootNoteId && !replyIds.contains(aid)) {
          allReplies.add(ancestor);
          replyIds.add(aid);
        }
      }
      final initialStructure =
          _buildThreadStructure(rootNoteRaw, allReplies);

      Map<String, dynamic>? focusedNote;
      if (event.focusedNoteId != null) {
        focusedNote = initialStructure.getNote(event.focusedNoteId!);
        focusedNote ??= rootNoteRaw;
      }

      emit(ThreadLoaded(
        rootNote: rootNoteRaw,
        replies: allReplies,
        threadStructure: initialStructure,
        focusedNote: focusedNote,
        userProfiles: const {},
        rootNoteId: rootNoteId,
        focusedNoteId: event.focusedNoteId,
        currentUserHex: currentUserHex,
        currentUser: null,
      ));

      final allIds = <String>[rootNoteId];
      for (final r in allReplies) {
        final id = r['id'] as String? ?? '';
        if (id.isNotEmpty) allIds.add(id);
      }
      if (currentUserHex.isNotEmpty) {
        InteractionService.instance.setCurrentUser(currentUserHex);
      }
      await _preloadInteractionCounts(allIds);

      _watchReplies(rootNoteId);
      _syncInBackground(rootNoteId);
      _loadAndSyncProfilesForNotes([rootNoteRaw, ...allReplies]);
      _loadCurrentUserProfile(currentUserHex);
    } catch (e) {
      emit(ThreadError('Failed to load thread: ${e.toString()}'));
    }
  }

  Future<List<Map<String, dynamic>>> _ensureAncestorChain(
      String focusedNoteId, String rootNoteId) async {
    final chainNotes = <Map<String, dynamic>>[];
    var currentId = focusedNoteId;
    final visited = <String>{rootNoteId};

    for (var depth = 0; depth < 15; depth++) {
      if (visited.contains(currentId)) break;
      visited.add(currentId);

      var noteMap = await _feedRepository.getNoteRaw(currentId);
      if (noteMap == null) {
        await _syncService.syncNote(currentId);
        noteMap = await _feedRepository.getNoteRaw(currentId);
        if (noteMap == null) break;
      }

      chainNotes.add(noteMap);

      final parentId = noteMap['parentId'] as String?;
      if (parentId == null ||
          parentId.isEmpty ||
          parentId == rootNoteId) {
        break;
      }

      currentId = parentId;
    }

    return chainNotes;
  }

  Map<String, dynamic> _stripRepostData(
      Map<String, dynamic> noteData, String rootNoteId) {
    final stripped = Map<String, dynamic>.from(noteData);
    stripped['isRepost'] = false;
    stripped.remove('repostedBy');
    stripped.remove('repostCreatedAt');
    if ((stripped['id'] as String? ?? '') != rootNoteId) {
      stripped['id'] = rootNoteId;
    }
    return stripped;
  }


  void _loadCurrentUserProfile(String currentUserHex) {
    if (currentUserHex.isEmpty) return;
    Future.microtask(() async {
      if (isClosed) return;
      try {
        final profile = await _profileRepository.getProfile(currentUserHex);
        if (isClosed || state is! ThreadLoaded) return;
        if (profile != null) {
          final profileMap = profile.toMap();
          add(_ThreadCurrentUserLoaded(profileMap));
        }
      } catch (_) {}
    });
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

    _loadAndSyncProfilesForNotes(repliesMap);

    final newReplyIds = repliesMap
        .map((r) => r['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (newReplyIds.isNotEmpty) {
      Future.microtask(() async {
        if (isClosed) return;
        await _preloadInteractionCounts(newReplyIds);
      });
    }
  }

  void _onThreadRepliesSyncCompleted(
    _ThreadRepliesSyncCompleted event,
    Emitter<ThreadState> emit,
  ) {
    if (state is ThreadLoaded) {
      emit((state as ThreadLoaded).copyWith(repliesSynced: true));
    }
  }

  Future<void> _preloadInteractionCounts(List<String> noteIds) async {
    if (noteIds.isEmpty) return;
    final userHex = _authService.currentUserPubkeyHex ?? '';
    if (userHex.isEmpty) return;

    try {
      final db = RustDatabaseService.instance;
      final data = await db.getBatchInteractionData(noteIds, userHex);
      if (isClosed) return;

      final service = InteractionService.instance;
      for (final noteId in noteIds) {
        final d = data[noteId];
        if (d == null) continue;
        final counts = InteractionCounts(
          reactions: (d['reactions'] as num?)?.toInt() ?? 0,
          reposts: (d['reposts'] as num?)?.toInt() ?? 0,
          replies: (d['replies'] as num?)?.toInt() ?? 0,
          zapAmount: (d['zaps'] as num?)?.toInt() ?? 0,
          hasReacted: d['hasReacted'] == true,
          hasReposted: d['hasReposted'] == true,
          hasZapped: d['hasZapped'] == true,
        );
        service.prePopulateCache(noteId, counts);
      }
      service.refreshAllActive();
    } catch (_) {}
  }

  Future<void> _syncInBackground(String rootNoteId) async {
    final allNoteIds = <String>[rootNoteId];
    if (state is ThreadLoaded) {
      for (final reply in (state as ThreadLoaded).replies) {
        final id = reply['id'] as String? ?? '';
        if (id.isNotEmpty) allNoteIds.add(id);
      }
    }

    try {
      if (!isClosed) {
        await InteractionService.instance.fetchCountsFromRelays(allNoteIds);
      }
    } catch (_) {}

    Future.microtask(() async {
      if (isClosed) return;
      try {
        await _syncService.syncReplies(rootNoteId);
        if (isClosed) return;

        add(const _ThreadRepliesSyncCompleted());
        
        final newNoteIds = <String>[];
        if (state is ThreadLoaded) {
          for (final reply in (state as ThreadLoaded).replies) {
            final id = reply['id'] as String? ?? '';
            if (id.isNotEmpty && !allNoteIds.contains(id)) {
              newNoteIds.add(id);
            }
          }
        }

        if (newNoteIds.isNotEmpty && !isClosed) {
          await InteractionService.instance.fetchCountsFromRelays(newNoteIds);
        }
      } catch (_) {
        if (!isClosed) add(const _ThreadRepliesSyncCompleted());
      }
    });
  }

  void _loadAndSyncProfilesForNotes(List<Map<String, dynamic>> notes) {
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
        final missingPubkeys = <String>[];

        for (final pubkey in authorIds) {
          final profile = profiles[pubkey];
          if (profile != null &&
              (profile.name ?? '').isNotEmpty &&
              (profile.picture ?? '').isNotEmpty) {
            updatedProfiles[pubkey] = profile.toMap();
            final npub = _authService.hexToNpub(pubkey);
            if (npub != null) updatedProfiles[npub] = profile.toMap();
          } else {
            if (profile != null) {
              updatedProfiles[pubkey] = profile.toMap();
              final npub = _authService.hexToNpub(pubkey);
              if (npub != null) updatedProfiles[npub] = profile.toMap();
            }
            missingPubkeys.add(pubkey);
          }
        }

        if (updatedProfiles.isNotEmpty && !isClosed) {
          add(ThreadProfilesUpdated(updatedProfiles));
        }

        if (missingPubkeys.isNotEmpty && !isClosed) {
          await _syncService.syncProfiles(missingPubkeys);
          if (isClosed) return;

          final synced =
              await _profileRepository.getProfiles(missingPubkeys);
          if (isClosed) return;

          final syncedProfiles = <String, Map<String, dynamic>>{};
          for (final entry in synced.entries) {
            syncedProfiles[entry.key] = entry.value.toMap();
            final npub = _authService.hexToNpub(entry.key);
            if (npub != null) syncedProfiles[npub] = entry.value.toMap();
          }

          if (syncedProfiles.isNotEmpty && !isClosed) {
            add(ThreadProfilesUpdated(syncedProfiles));
          }
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
      
      if (state is ThreadLoaded) {
        final allIds = <String>[_currentRootNoteId!];
        for (final reply in (state as ThreadLoaded).replies) {
          final id = reply['id'] as String? ?? '';
          if (id.isNotEmpty) allIds.add(id);
        }
        
        await InteractionService.instance.fetchCountsFromRelays(allIds);
      }
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

      String? parentId = reply['parentId'] as String?;
      final replyRootId = reply['rootId'] as String?;

      if (parentId != null && parentId.isEmpty) parentId = null;

      if (parentId == null && replyRootId != null && replyRootId.isNotEmpty) {
        if (replyRootId == rootNoteId ||
            replyIds.contains(replyRootId) ||
            notesMap.containsKey(replyRootId)) {
          parentId = replyRootId;
        } else {
          parentId = rootNoteId;
        }
      }

      parentId ??= rootNoteId;

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

class _ThreadRepliesSyncCompleted extends ThreadEvent {
  const _ThreadRepliesSyncCompleted();
}

class _ThreadCurrentUserLoaded extends ThreadEvent {
  final Map<String, dynamic> profileMap;
  const _ThreadCurrentUserLoaded(this.profileMap);

  @override
  List<Object?> get props => [profileMap];
}
