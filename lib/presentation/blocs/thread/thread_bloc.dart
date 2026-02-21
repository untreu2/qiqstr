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
      final chain = event.chain;
      if (chain.isEmpty) {
        emit(const ThreadError('Invalid thread chain'));
        return;
      }

      final currentUserHex = _authService.currentUserPubkeyHex ?? '';
      final rootNoteId = chain.first;

      final chainNotes = <Map<String, dynamic>>[];
      for (final noteId in chain) {
        var noteRaw = await _feedRepository.getNoteRaw(noteId);

        if (noteRaw == null && noteId == chain.first && event.initialNoteData != null) {
          noteRaw = _stripRepostData(event.initialNoteData!, noteId);
        }

        if (noteRaw == null) {
          await _syncService.syncNote(noteId);
          noteRaw = await _feedRepository.getNoteRaw(noteId);
        }

        if (noteRaw != null) {
          chainNotes.add(noteRaw);
        }
      }

      if (chainNotes.isEmpty) {
        emit(const ThreadLoading());

        final resolvedRootId = await _syncService.resolveThreadRoot(rootNoteId);
        final rootNote = await _feedRepository.getNoteRaw(resolvedRootId);
        if (rootNote == null) {
          emit(const ThreadError('Note not found'));
          return;
        }
        chainNotes.add(rootNote);
      }

      final rootNote = chainNotes.first;
      final actualRootNoteId = rootNote['id'] as String? ?? rootNoteId;
      _currentRootNoteId = actualRootNoteId;

      final dbReplies = await _feedRepository.getRepliesRaw(actualRootNoteId);
      final replyIds = dbReplies.map((r) => r['id'] as String? ?? '').toSet();
      final allReplies = [...dbReplies];

      for (final chainNote in chainNotes) {
        final cid = chainNote['id'] as String? ?? '';
        if (cid.isNotEmpty && cid != actualRootNoteId && !replyIds.contains(cid)) {
          allReplies.add(chainNote);
          replyIds.add(cid);
        }
      }

      final structure = _buildThreadStructure(rootNote, allReplies);

      emit(ThreadLoaded(
        rootNote: rootNote,
        replies: allReplies,
        threadStructure: structure,
        chainNotes: chainNotes,
        chain: chain,
        userProfiles: const {},
        currentUserHex: currentUserHex,
        currentUser: null,
      ));

      _watchReplies(actualRootNoteId);
      _syncRepliesOnly(actualRootNoteId);

      _loadAndSyncProfilesForNotes([...chainNotes, ...allReplies]);
      _loadCurrentUserProfile(currentUserHex);

      final allIds = <String>[actualRootNoteId];
      for (final r in allReplies) {
        final id = r['id'] as String? ?? '';
        if (id.isNotEmpty) allIds.add(id);
      }
      if (currentUserHex.isNotEmpty) {
        InteractionService.instance.setCurrentUser(currentUserHex);
      }
      _loadInteractionCountsInBackground(allIds);
    } catch (e) {
      emit(ThreadError('Failed to load thread: ${e.toString()}'));
    }
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

    final replyIds = repliesMap.map((r) => r['id'] as String? ?? '').toSet();
    final rootNoteId = currentState.rootNoteId;
    for (final chainNote in currentState.chainNotes) {
      final cid = chainNote['id'] as String? ?? '';
      if (cid.isNotEmpty && cid != rootNoteId && !replyIds.contains(cid)) {
        repliesMap.add(chainNote);
        replyIds.add(cid);
      }
    }

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

  void _syncRepliesOnly(String rootNoteId) {
    Future.microtask(() async {
      if (isClosed) return;
      try {
        await _syncService.syncReplies(rootNoteId);
        if (isClosed) return;
        add(const _ThreadRepliesSyncCompleted());
      } catch (_) {
        if (!isClosed) add(const _ThreadRepliesSyncCompleted());
      }
    });
  }

  void _loadInteractionCountsInBackground(List<String> initialNoteIds) {
    Future.microtask(() async {
      if (isClosed) return;
      await _preloadInteractionCounts(initialNoteIds);

      if (isClosed) return;
      try {
        await InteractionService.instance
            .fetchCountsFromRelays(initialNoteIds);
      } catch (_) {}

      if (isClosed || state is! ThreadLoaded) return;
      final currentReplies = (state as ThreadLoaded).replies;
      final newIds = <String>[];
      final initialSet = initialNoteIds.toSet();
      for (final reply in currentReplies) {
        final id = reply['id'] as String? ?? '';
        if (id.isNotEmpty && !initialSet.contains(id)) {
          newIds.add(id);
        }
      }
      if (newIds.isNotEmpty && !isClosed) {
        await _preloadInteractionCounts(newIds);
        if (!isClosed) {
          try {
            await InteractionService.instance.fetchCountsFromRelays(newIds);
          } catch (_) {}
        }
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
