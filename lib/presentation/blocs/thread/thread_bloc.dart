import 'dart:async';
import 'package:flutter/foundation.dart';
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
    on<_ThreadCurrentUserLoaded>(_onThreadCurrentUserLoaded);
  }

  void _onThreadProfilesUpdated(
    ThreadProfilesUpdated event,
    Emitter<ThreadState> emit,
  ) {
    if (state is ThreadLoaded) {
      final currentState = state as ThreadLoaded;
      final merged = Map<String, Map<String, dynamic>>.from(
        currentState.userProfiles,
      )..addAll(event.profiles);
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
        currentState.userProfiles,
      )..[currentState.currentUserHex] = event.profileMap;
      emit(
        currentState.copyWith(
          currentUser: event.profileMap,
          userProfiles: merged,
        ),
      );
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
      final focusedNoteId = chain.last;

      emit(const ThreadLoading());

      final threadData = await _syncService.fetchFullThread(
        focusedNoteId,
        currentUserPubkeyHex:
            currentUserHex.isNotEmpty ? currentUserHex : null,
      );

      if (isClosed) return;

      final rootNote =
          threadData['rootNote'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final rootNoteId = rootNote['id'] as String? ?? chain.first;
      _currentRootNoteId = rootNoteId;

      final rawChainNotes = threadData['chainNotes'] as List<dynamic>? ?? [];
      final chainNotes = rawChainNotes.cast<Map<String, dynamic>>();
      if (chainNotes.isEmpty) {
        chainNotes.add(rootNote);
      }

      final rawChildrenMap =
          threadData['childrenMap'] as Map<String, dynamic>? ?? {};
      final childrenMap = rawChildrenMap.map(
        (key, value) => MapEntry(
            key, (value as List<dynamic>).cast<Map<String, dynamic>>()),
      );

      final rawNotesMap =
          threadData['notesMap'] as Map<String, dynamic>? ?? {};
      final notesMap = rawNotesMap.map(
        (key, value) => MapEntry(key, value as Map<String, dynamic>),
      );

      final totalReplies = threadData['totalReplies'] as int? ?? 0;

      final allReplies = <Map<String, dynamic>>[];
      for (final entry in notesMap.entries) {
        if (entry.key != rootNoteId) {
          allReplies.add(entry.value);
        }
      }

      final structure = ThreadStructure(
        rootNote: rootNote,
        childrenMap: childrenMap,
        notesMap: notesMap,
        totalReplies: totalReplies,
      );

      final userProfiles = <String, Map<String, dynamic>>{};
      for (final note in notesMap.values) {
        final pubkey = note['pubkey'] as String? ?? '';
        final authorName = note['authorName'] as String?;
        if (pubkey.isNotEmpty && authorName != null) {
          userProfiles[pubkey] = {
            'pubkeyHex': pubkey,
            'name': authorName,
            'profileImage': note['authorImage'] as String? ?? '',
            'picture': note['authorImage'] as String? ?? '',
            'nip05': note['authorNip05'] as String? ?? '',
          };
        }
      }

      emit(
        ThreadLoaded(
          rootNote: rootNote,
          replies: allReplies,
          threadStructure: structure,
          chainNotes: chainNotes,
          chain: chain,
          userProfiles: userProfiles,
          currentUserHex: currentUserHex,
          currentUser: null,
          repliesSynced: true,
        ),
      );

      _watchReplies(rootNoteId);

      _loadCurrentUserProfile(currentUserHex);

      final allIds = <String>[rootNoteId];
      for (final r in allReplies) {
        final id = r['id'] as String? ?? '';
        if (id.isNotEmpty) allIds.add(id);
      }
      if (currentUserHex.isNotEmpty) {
        InteractionService.instance.setCurrentUser(currentUserHex);
      }
      _loadInteractionCountsInBackground(allIds);

      _loadAndSyncProfilesForNotes([...chainNotes, ...allReplies]);
    } catch (e) {
      emit(ThreadError('Failed to load thread: ${e.toString()}'));
    }
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
    _repliesSubscription = _feedRepository.watchReplies(rootNoteId).listen((
      replies,
    ) {
      if (isClosed) return;
      add(_ThreadRepliesUpdated(replies));
    });
  }

  Future<void> _onThreadRepliesUpdated(
    _ThreadRepliesUpdated event,
    Emitter<ThreadState> emit,
  ) async {
    if (state is! ThreadLoaded) return;
    final currentState = state as ThreadLoaded;

    final repliesMap = event.replies.map((r) => r.toMap()).toList();

    final replyIds = repliesMap.map((r) => r['id'] as String? ?? '').toSet();
    final rootNoteId = currentState.rootNoteId;

    for (final existing in currentState.replies) {
      final eid = existing['id'] as String? ?? '';
      if (eid.isNotEmpty && !replyIds.contains(eid)) {
        repliesMap.add(existing);
        replyIds.add(eid);
      }
    }

    for (final chainNote in currentState.chainNotes) {
      final cid = chainNote['id'] as String? ?? '';
      if (cid.isNotEmpty && cid != rootNoteId && !replyIds.contains(cid)) {
        repliesMap.add(chainNote);
        replyIds.add(cid);
      }
    }

    final existingIds =
        currentState.replies.map((r) => r['id'] as String? ?? '').toSet();

    final hasNewReplies = replyIds.length != existingIds.length ||
        replyIds.any((id) => !existingIds.contains(id));

    if (!hasNewReplies) return;

    final structure = await compute(_computeThreadStructure, {
      'rootNote': currentState.rootNote,
      'replies': repliesMap,
    });

    if (isClosed) return;

    final childrenMap =
        (structure['childrenMap'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(
          key, (value as List<dynamic>).cast<Map<String, dynamic>>()),
    );
    final notesMap =
        (structure['notesMap'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, value as Map<String, dynamic>),
    );

    final threadStructure = ThreadStructure(
      rootNote: currentState.rootNote,
      childrenMap: childrenMap,
      notesMap: notesMap,
      totalReplies: repliesMap.length,
    );

    emit(
      currentState.copyWith(
          replies: repliesMap, threadStructure: threadStructure),
    );

    final newNotes = repliesMap
        .where((r) => !existingIds.contains(r['id'] as String? ?? ''))
        .toList();
    if (newNotes.isNotEmpty) {
      _loadAndSyncProfilesForNotes(newNotes);
    }

    final newIds = newNotes
        .map((r) => r['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (newIds.isNotEmpty) {
      Future.microtask(() async {
        if (isClosed) return;
        await _preloadInteractionCounts(newIds);
      });
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

  void _loadInteractionCountsInBackground(List<String> initialNoteIds) {
    Future.microtask(() async {
      if (isClosed) return;

      if (state is ThreadLoaded) {
        final currentReplies = (state as ThreadLoaded).replies;
        final allIds = {
          ...initialNoteIds,
          ...currentReplies
              .map((r) => r['id'] as String? ?? '')
              .where((id) => id.isNotEmpty),
        }.toList();

        await _preloadInteractionCounts(allIds);
        if (isClosed) return;
        try {
          await InteractionService.instance.fetchCountsFromRelays(allIds);
        } catch (_) {}
      } else {
        await _preloadInteractionCounts(initialNoteIds);
        if (isClosed) return;
        try {
          await InteractionService.instance.fetchCountsFromRelays(
            initialNoteIds,
          );
        } catch (_) {}
      }
    });
  }

  void _loadAndSyncProfilesForNotes(List<Map<String, dynamic>> notes) {
    Future.microtask(() async {
      if (isClosed || state is! ThreadLoaded) return;

      final currentState = state as ThreadLoaded;
      final authorIds = notes
          .map((n) => n['author'] as String? ?? n['pubkey'] as String? ?? '')
          .where(
            (id) => id.isNotEmpty && !currentState.userProfiles.containsKey(id),
          )
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
          if (profile != null) {
            updatedProfiles[pubkey] = profile.toMap();
            final npub = _authService.hexToNpub(pubkey);
            if (npub != null) updatedProfiles[npub] = profile.toMap();
            if ((profile.name ?? '').isEmpty ||
                (profile.picture ?? '').isEmpty) {
              missingPubkeys.add(pubkey);
            }
          } else {
            missingPubkeys.add(pubkey);
          }
        }

        if (updatedProfiles.isNotEmpty && !isClosed) {
          add(ThreadProfilesUpdated(updatedProfiles));
        }

        if (missingPubkeys.isNotEmpty && !isClosed) {
          await _syncService.syncProfiles(missingPubkeys);
          if (isClosed) return;

          final synced = await _profileRepository.getProfiles(missingPubkeys);
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

class _ThreadCurrentUserLoaded extends ThreadEvent {
  final Map<String, dynamic> profileMap;
  const _ThreadCurrentUserLoaded(this.profileMap);

  @override
  List<Object?> get props => [profileMap];
}

Map<String, dynamic> _computeThreadStructure(Map<String, dynamic> args) {
  final rootNote = args['rootNote'] as Map<String, dynamic>;
  final replies =
      (args['replies'] as List<dynamic>).cast<Map<String, dynamic>>();

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

  return {'childrenMap': childrenMap, 'notesMap': notesMap};
}
