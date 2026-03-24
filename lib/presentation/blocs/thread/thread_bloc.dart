import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/encrypted_mute_service.dart';
import '../../../data/services/interaction_service.dart';
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
    on<_ThreadNetworkDataLoaded>(_onThreadNetworkDataLoaded);
    on<_ThreadNetworkFailed>(_onThreadNetworkFailed);
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

      if (event.initialNoteData != null) {
        final noteData = event.initialNoteData!;
        final noteId = noteData['id'] as String? ?? focusedNoteId;
        final structure = ThreadStructure(
          rootNote: noteData,
          childrenMap: const {},
          notesMap: {noteId: noteData},
          totalReplies: 0,
        );
        final userProfiles = <String, Map<String, dynamic>>{};
        final pubkey = noteData['pubkey'] as String? ?? '';
        final authorName = noteData['authorName'] as String?;
        if (pubkey.isNotEmpty && authorName != null) {
          userProfiles[pubkey] = {
            'pubkey': pubkey,
            'name': authorName,
            'picture': noteData['authorImage'] as String? ?? '',
            'nip05': noteData['authorNip05'] as String? ?? '',
          };
        }
        emit(
          ThreadLoaded(
            rootNote: noteData,
            replies: const [],
            threadStructure: structure,
            chainNotes: [noteData],
            chain: chain,
            userProfiles: userProfiles,
            currentUserHex: currentUserHex,
            currentUser: null,
            repliesSynced: false,
          ),
        );

        _loadCurrentUserProfile(currentUserHex);
      } else {
        emit(const ThreadLoading());
      }

      _fetchNetworkThread(focusedNoteId, chain, currentUserHex);

      final localThreadData = await _loadFromLocalDb(
        focusedNoteId,
        currentUserHex: currentUserHex.isNotEmpty ? currentUserHex : null,
      );

      if (isClosed) return;

      if (localThreadData != null) {
        final localState = _buildLoadedState(
          localThreadData,
          chain,
          currentUserHex,
          repliesSynced: false,
        );
        if (localState != null) {
          emit(localState);
          _currentRootNoteId = localState.rootNoteId;
          _watchReplies(localState.rootNoteId);
          _loadCurrentUserProfile(currentUserHex);
          _loadAndSyncProfilesForNotes(
            [...localState.chainNotes, ...localState.replies],
          );
        }
      }
    } catch (e) {
      if (!isClosed && state is! ThreadLoaded) {
        emit(ThreadError('Failed to load thread: ${e.toString()}'));
      }
    }
  }

  Future<Map<String, dynamic>?> _loadFromLocalDb(
    String noteId, {
    String? currentUserHex,
  }) async {
    try {
      final mute = EncryptedMuteService.instance;
      return await _syncService.fetchFullThreadLocal(
        noteId,
        currentUserPubkeyHex: currentUserHex,
        mutedPubkeys: mute.mutedPubkeys,
        mutedWords: mute.mutedWords,
      );
    } catch (_) {
      return null;
    }
  }

  void _fetchNetworkThread(
    String focusedNoteId,
    List<String> chain,
    String currentUserHex,
  ) {
    _syncService
        .fetchFullThread(
      focusedNoteId,
      currentUserPubkeyHex: currentUserHex.isNotEmpty ? currentUserHex : null,
    )
        .then((threadData) {
      if (!isClosed) {
        add(_ThreadNetworkDataLoaded(threadData, chain, currentUserHex));
      }
    }).catchError((e) {
      if (!isClosed) {
        add(const _ThreadNetworkFailed());
      }
    });
  }

  void _onThreadNetworkDataLoaded(
    _ThreadNetworkDataLoaded event,
    Emitter<ThreadState> emit,
  ) {
    final newState = _buildLoadedState(
      event.threadData,
      event.chain,
      event.currentUserHex,
      repliesSynced: true,
    );
    if (newState == null) return;

    _currentRootNoteId = newState.rootNoteId;

    final mergedProfiles = <String, Map<String, dynamic>>{};
    if (state is ThreadLoaded) {
      mergedProfiles.addAll((state as ThreadLoaded).userProfiles);
    }
    mergedProfiles.addAll(newState.userProfiles);

    emit(newState.copyWith(userProfiles: mergedProfiles));

    _watchReplies(newState.rootNoteId);
    _loadCurrentUserProfile(event.currentUserHex);

    final allIds = <String>[newState.rootNoteId];
    for (final r in newState.replies) {
      final id = r['id'] as String? ?? '';
      if (id.isNotEmpty) allIds.add(id);
    }
    if (event.currentUserHex.isNotEmpty) {
      InteractionService.instance.setCurrentUser(event.currentUserHex);
    }
    _loadInteractionCountsInBackground(allIds);
    _loadAndSyncProfilesForNotes([...newState.chainNotes, ...newState.replies]);
  }

  ThreadLoaded? _buildLoadedState(
    Map<String, dynamic> threadData,
    List<String> chain,
    String currentUserHex, {
    bool repliesSynced = false,
  }) {
    final rootNote =
        threadData['rootNote'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final rootNoteId = rootNote['id'] as String? ?? chain.first;

    final rawChainNotes = threadData['chainNotes'] as List<dynamic>? ?? [];
    final chainNotes = rawChainNotes.cast<Map<String, dynamic>>();
    if (chainNotes.isEmpty) {
      chainNotes.add(rootNote);
    }

    final rawChildrenMap =
        threadData['childrenMap'] as Map<String, dynamic>? ?? {};
    final childrenMap = rawChildrenMap.map(
      (key, value) =>
          MapEntry(key, (value as List<dynamic>).cast<Map<String, dynamic>>()),
    );

    final rawNotesMap = threadData['notesMap'] as Map<String, dynamic>? ?? {};
    final notesMap = rawNotesMap.map(
      (key, value) => MapEntry(key, value as Map<String, dynamic>),
    );

    final totalReplies = threadData['totalReplies'] as int? ?? 0;

    final allReplies = <Map<String, dynamic>>[];
    int quoteCount = 0;
    for (final entry in notesMap.entries) {
      if (entry.key != rootNoteId) {
        final note = entry.value;
        if (_noteIsQuoteOf(note, rootNoteId)) {
          quoteCount++;
        } else {
          allReplies.add(note);
        }
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
          'pubkey': pubkey,
          'name': authorName,
          'picture': note['authorImage'] as String? ?? '',
          'nip05': note['authorNip05'] as String? ?? '',
        };
      }
    }

    return ThreadLoaded(
      rootNote: rootNote,
      replies: allReplies,
      threadStructure: structure,
      chainNotes: chainNotes,
      chain: chain,
      userProfiles: userProfiles,
      currentUserHex: currentUserHex,
      currentUser: null,
      repliesSynced: repliesSynced,
      quoteCount: quoteCount,
    );
  }

  static bool _noteIsQuoteOf(Map<String, dynamic> note, String targetNoteId) {
    final tags = note['tags'] as List<dynamic>? ?? [];
    for (final tag in tags) {
      if (tag is! List || tag.length < 2 || tag[0] != 'e') continue;
      final refId = tag[1] as String? ?? '';
      if (refId != targetNoteId) continue;
      final marker = tag.length >= 4 ? tag[3] as String? : null;
      if (marker == 'mention') return true;
    }
    return false;
  }

  void _loadCurrentUserProfile(String currentUserHex) {
    if (currentUserHex.isEmpty) return;
    _profileRepository.getProfile(currentUserHex).then((profile) {
      if (isClosed || state is! ThreadLoaded) return;
      if (profile != null) {
        add(_ThreadCurrentUserLoaded(profile.toMap()));
      }
    }).catchError((_) {});
  }

  void _watchReplies(String rootNoteId) {
    _repliesSubscription?.cancel();
    _repliesSubscription =
        _feedRepository.watchThreadReplies(rootNoteId).listen((replies) {
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

    final incomingIds = event.replies.map((r) => r.id).toSet();
    final existingIds =
        currentState.replies.map((r) => r['id'] as String? ?? '').toSet();

    final hasNewReplies = incomingIds.length != existingIds.length ||
        incomingIds.any((id) => !existingIds.contains(id));
    if (!hasNewReplies) return;

    final repliesMap = event.replies.map((r) => r.toMap()).toList();
    final replyIds = incomingIds;
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

    final structureArgs = {
      'rootNote': currentState.rootNote,
      'replies': repliesMap,
    };
    final structure = repliesMap.length > 50
        ? await compute(_computeThreadStructure, structureArgs)
        : _computeThreadStructure(structureArgs);

    if (isClosed) return;

    final childrenMap = (structure['childrenMap'] as Map<String, dynamic>).map(
      (key, value) =>
          MapEntry(key, (value as List<dynamic>).cast<Map<String, dynamic>>()),
    );
    final notesMap = (structure['notesMap'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, value as Map<String, dynamic>),
    );

    final threadStructure = ThreadStructure(
      rootNote: currentState.rootNote,
      childrenMap: childrenMap,
      notesMap: notesMap,
      totalReplies: repliesMap.length,
    );

    final targetId = currentState.rootNoteId;
    final filteredReplies =
        repliesMap.where((r) => !_noteIsQuoteOf(r, targetId)).toList();
    final newQuoteCount =
        repliesMap.where((r) => _noteIsQuoteOf(r, targetId)).length;

    emit(
      currentState.copyWith(
        replies: filteredReplies,
        threadStructure: threadStructure,
        quoteCount: newQuoteCount,
      ),
    );

    final newNotes = repliesMap
        .where((r) => !existingIds.contains(r['id'] as String? ?? ''))
        .toList();
    if (newNotes.isNotEmpty) {
      _loadAndSyncProfilesForNotes(newNotes);
    }

    if (newNotes.isNotEmpty) {
      final newFeedNotes = event.replies
          .where((n) => newNotes.any((m) => m['id'] == n.id))
          .toList();
      InteractionService.instance.populateFromNotes(newFeedNotes);
    }
  }

  void _loadInteractionCountsInBackground(List<String> initialIds) {
    final ids = (state is ThreadLoaded)
        ? {
            ...initialIds,
            ...(state as ThreadLoaded)
                .replies
                .map((r) => r['id'] as String? ?? '')
                .where((id) => id.isNotEmpty),
          }.toList()
        : initialIds;

    InteractionService.instance.fetchCountsFromRelays(ids).catchError((_) {});
  }

  void _loadAndSyncProfilesForNotes(List<Map<String, dynamic>> notes) async {
    if (isClosed || state is! ThreadLoaded) return;

    final currentState = state as ThreadLoaded;
    final authorIds = notes
        .map((n) => n['pubkey'] as String? ?? '')
        .where(
          (id) => id.isNotEmpty && !currentState.userProfiles.containsKey(id),
        )
        .toSet()
        .toList();

    if (authorIds.isEmpty) return;

    try {
      final profilesFuture = _profileRepository.getProfiles(authorIds);
      final syncFuture = _syncService.syncProfiles(authorIds);

      final profiles = await profilesFuture;
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

      await syncFuture;
      if (isClosed) return;

      if (missingPubkeys.isNotEmpty) {
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
  }

  void _onThreadNetworkFailed(
    _ThreadNetworkFailed event,
    Emitter<ThreadState> emit,
  ) {
    if (state is! ThreadLoaded) {
      emit(const ThreadError('Failed to load thread from network'));
    }
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

class _ThreadNetworkDataLoaded extends ThreadEvent {
  final Map<String, dynamic> threadData;
  final List<String> chain;
  final String currentUserHex;

  const _ThreadNetworkDataLoaded(
      this.threadData, this.chain, this.currentUserHex);

  @override
  List<Object?> get props => [threadData, chain, currentUserHex];
}

class _ThreadNetworkFailed extends ThreadEvent {
  const _ThreadNetworkFailed();

  @override
  List<Object?> get props => [];
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
