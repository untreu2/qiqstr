import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
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
  final EncryptedMuteService _muteService;
  final InteractionService _interactionService;

  String? _currentRootNoteId;
  StreamSubscription<Map<String, dynamic>?>? _repliesSubscription;
  int _loadRequestId = 0;
  int _repliesWatchGeneration = 0;
  final Set<int> _completedLocalLoads = <int>{};
  final Set<int> _failedNetworkLoads = <int>{};

  ThreadBloc({
    required FeedRepository feedRepository,
    required ProfileRepository profileRepository,
    required SyncService syncService,
    required AuthService authService,
    required EncryptedMuteService muteService,
    required InteractionService interactionService,
  })  : _feedRepository = feedRepository,
        _profileRepository = profileRepository,
        _syncService = syncService,
        _authService = authService,
        _muteService = muteService,
        _interactionService = interactionService,
        super(const ThreadInitial()) {
    on<ThreadLoadRequested>(_onThreadLoaded, transformer: restartable());
    on<ThreadRefreshed>(_onThreadRefreshed, transformer: droppable());
    on<ThreadProfilesUpdated>(_onThreadProfilesUpdated);
    on<ThreadRepliesUpdated>(_onThreadRepliesUpdated,
        transformer: restartable());
    on<ThreadCurrentUserLoaded>(_onThreadCurrentUserLoaded);
    on<ThreadNetworkDataLoaded>(_onThreadNetworkDataLoaded);
    on<ThreadNetworkFailed>(_onThreadNetworkFailed);
  }

  void _onThreadProfilesUpdated(
    ThreadProfilesUpdated event,
    Emitter<ThreadState> emit,
  ) {
    if (event.requestId != _loadRequestId) return;
    if (state is ThreadLoaded) {
      final currentState = state as ThreadLoaded;
      final merged = Map<String, Map<String, dynamic>>.from(
        currentState.userProfiles,
      )..addAll(event.profiles);
      emit(currentState.copyWith(userProfiles: merged));
    }
  }

  void _onThreadCurrentUserLoaded(
    ThreadCurrentUserLoaded event,
    Emitter<ThreadState> emit,
  ) {
    if (event.requestId != _loadRequestId) return;
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
    final requestId = ++_loadRequestId;
    _completedLocalLoads.removeWhere((id) => id < requestId);
    _failedNetworkLoads.removeWhere((id) => id < requestId);
    _repliesWatchGeneration++;
    await _repliesSubscription?.cancel();
    _repliesSubscription = null;

    try {
      final chain = event.chain;
      if (chain.isEmpty) {
        emit(const ThreadError('Invalid thread chain'));
        return;
      }

      final currentUserHex = _authService.currentUserPubkeyHex ?? '';
      final focusedNoteId = chain.last;

      if (event.initialNoteData == null) {
        emit(const ThreadLoading());
      } else {
        final noteData = _stripRepostMetadata(
          event.initialNoteData!,
          focusedNoteId,
        );
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
        _loadCurrentUserProfile(currentUserHex, requestId);
      }

      _fetchNetworkThread(focusedNoteId, chain, currentUserHex, requestId);

      final localThreadData = await _loadFromLocalDb(
        chain.first,
        currentUserHex: currentUserHex.isNotEmpty ? currentUserHex : null,
      );

      _completedLocalLoads.add(requestId);

      if (isClosed || requestId != _loadRequestId || emit.isDone) return;

      if (localThreadData != null) {
        final localState = _buildLoadedState(
          localThreadData,
          chain,
          currentUserHex,
          repliesSynced: false,
        );
        if (localState != null &&
            !(state is ThreadLoaded && (state as ThreadLoaded).repliesSynced)) {
          emit(localState);
          _currentRootNoteId = localState.rootNoteId;
          if (currentUserHex.isNotEmpty) {
            _interactionService.setCurrentUser(currentUserHex);
          }
          _watchReplies(localState.rootNoteId);
          _loadCurrentUserProfile(currentUserHex, requestId);
          _loadAndSyncProfilesForNotes(
            [...localState.chainNotes, ...localState.replies],
            requestId,
          );
          final localIds = <String>[localState.rootNoteId];
          for (final r in localState.replies) {
            final id = r['id'] as String? ?? '';
            if (id.isNotEmpty) localIds.add(id);
          }
          _loadInteractionCountsInBackground(localIds);
        }
      } else if (state is! ThreadLoaded) {
        if (_failedNetworkLoads.contains(requestId)) {
          emit(const ThreadError('Failed to load thread'));
        } else {
          emit(const ThreadLoading());
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
    final structure =
        await _feedRepository.getThreadStructure(noteId, limit: 500);
    if (structure != null) {
      return _convertStructureToThreadData(structure);
    }
    try {
      return await _syncService.fetchFullThreadLocal(
        noteId,
        currentUserPubkeyHex: currentUserHex,
        mutedPubkeys: _muteService.mutedPubkeys,
        mutedWords: _muteService.mutedWords,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _convertStructureToThreadData(
      Map<String, dynamic> data) {
    final allReplies =
        (data['allReplies'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
            [];
    final notesMap = (data['notesMap'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as Map<String, dynamic>),
        ) ??
        {};
    final childrenMap = (data['childrenMap'] as Map<String, dynamic>?)?.map(
          (k, v) =>
              MapEntry(k, (v as List<dynamic>).cast<Map<String, dynamic>>()),
        ) ??
        {};
    return {
      'rootNote': data['rootNote'],
      'chainNotes': data['chainNotes'],
      'childrenMap': childrenMap,
      'notesMap': notesMap,
      'allReplies': allReplies,
      'quoteCount': data['quoteCount'],
      'totalReplies': data['totalReplies'] ?? allReplies.length,
    };
  }

  void _fetchNetworkThread(
    String focusedNoteId,
    List<String> chain,
    String currentUserHex,
    int requestId,
  ) {
    _syncService
        .fetchFullThread(
      focusedNoteId,
      currentUserPubkeyHex: currentUserHex.isNotEmpty ? currentUserHex : null,
    )
        .then((threadData) {
      if (!isClosed) {
        add(ThreadNetworkDataLoaded(
          threadData,
          chain,
          currentUserHex,
          requestId,
        ));
      }
    }).catchError((e) {
      if (!isClosed) {
        add(ThreadNetworkFailed(requestId));
      }
    });
  }

  Future<void> _onThreadNetworkDataLoaded(
    ThreadNetworkDataLoaded event,
    Emitter<ThreadState> emit,
  ) async {
    if (event.requestId != _loadRequestId) return;

    final networkRoot = event.threadData['rootNote'] as Map<String, dynamic>?;
    final networkRootId = networkRoot?['id'] as String? ?? event.chain.first;
    final localThreadData = await _loadFromLocalDb(
      networkRootId,
      currentUserHex:
          event.currentUserHex.isNotEmpty ? event.currentUserHex : null,
    );
    if (isClosed || event.requestId != _loadRequestId || emit.isDone) return;

    final newState = _buildLoadedState(
      localThreadData ?? event.threadData,
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
    _loadCurrentUserProfile(event.currentUserHex, event.requestId);

    final allIds = <String>[newState.rootNoteId];
    for (final r in newState.replies) {
      final id = r['id'] as String? ?? '';
      if (id.isNotEmpty) allIds.add(id);
    }
    if (event.currentUserHex.isNotEmpty) {
      _interactionService.setCurrentUser(event.currentUserHex);
    }
    _loadInteractionCountsInBackground(allIds);
    _loadAndSyncProfilesForNotes(
      [...newState.chainNotes, ...newState.replies],
      event.requestId,
    );
  }

  ThreadLoaded? _buildLoadedState(
    Map<String, dynamic> threadData,
    List<String> chain,
    String currentUserHex, {
    bool repliesSynced = false,
  }) {
    final rootNote =
        threadData['rootNote'] as Map<String, dynamic>? ?? <String, dynamic>{};
    if (rootNote.isEmpty) return null;
    final rootNoteId = rootNote['id'] as String? ?? chain.first;

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
    final rawChainNotes = threadData['chainNotes'] as List<dynamic>? ?? [];
    var chainNotes = List<Map<String, dynamic>>.from(
      rawChainNotes.cast<Map<String, dynamic>>(),
    );
    final mappedChain = chain
        .map((id) => notesMap[id])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (mappedChain.isNotEmpty &&
        (chainNotes.length < chain.length ||
            (chainNotes.last['id'] as String? ?? '') != chain.last)) {
      chainNotes = mappedChain;
    }
    if (chainNotes.isEmpty) {
      chainNotes.add(rootNote);
    }

    final totalReplies = threadData['totalReplies'] as int? ?? 0;

    final preComputedReplies = (threadData['allReplies'] as List<dynamic>?)
        ?.cast<Map<String, dynamic>>();
    final preComputedQuoteCount = threadData['quoteCount'] as int?;

    final allReplies = <Map<String, dynamic>>[];
    int quoteCount = 0;
    if (preComputedReplies != null) {
      allReplies.addAll(preComputedReplies);
      quoteCount = preComputedQuoteCount ?? 0;
    } else {
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

  static Map<String, dynamic> _stripRepostMetadata(
    Map<String, dynamic> noteData,
    String focusedNoteId,
  ) {
    final stripped = Map<String, dynamic>.from(noteData);
    stripped['isRepost'] = false;
    stripped.remove('repostedBy');
    stripped.remove('repostCreatedAt');
    if ((stripped['id'] as String? ?? '') != focusedNoteId &&
        focusedNoteId.isNotEmpty) {
      stripped['id'] = focusedNoteId;
    }
    return stripped;
  }

  static bool _noteIsQuoteOf(Map<String, dynamic> note, String targetNoteId) {
    final tags = note['tags'] as List<dynamic>? ?? [];
    bool hasReplyMarkerToTarget = false;
    bool hasMentionMarkerToTarget = false;
    bool hasQToTarget = false;

    for (final tag in tags) {
      if (tag is! List || tag.length < 2) continue;
      final tagName = tag[0] as String? ?? '';
      final refId = tag[1] as String? ?? '';
      if (refId != targetNoteId) continue;
      if (tagName == 'q') {
        hasQToTarget = true;
      } else if (tagName == 'e') {
        final marker = tag.length >= 4 ? tag[3] as String? : null;
        if (marker == 'reply' || marker == 'root') {
          hasReplyMarkerToTarget = true;
        } else if (marker == 'mention') {
          hasMentionMarkerToTarget = true;
        }
      }
    }

    if (hasReplyMarkerToTarget) return false;
    return hasQToTarget || hasMentionMarkerToTarget;
  }

  void _loadCurrentUserProfile(String currentUserHex, int requestId) {
    if (currentUserHex.isEmpty) return;
    _profileRepository.getProfile(currentUserHex).then((profile) {
      if (isClosed || requestId != _loadRequestId || state is! ThreadLoaded) {
        return;
      }
      if (profile != null) {
        add(ThreadCurrentUserLoaded(profile.toMap(), requestId));
      }
    }).catchError((_) {});
  }

  void _watchReplies(String rootNoteId) {
    final generation = ++_repliesWatchGeneration;
    _repliesSubscription?.cancel();

    void subscribe() {
      if (isClosed || generation != _repliesWatchGeneration) return;
      _repliesSubscription =
          _feedRepository.watchThreadStructure(rootNoteId).listen(
        (threadData) {
          if (isClosed || generation != _repliesWatchGeneration) return;
          add(ThreadRepliesUpdated(threadData, rootNoteId));
        },
        onError: (_) => _scheduleRepliesWatchRetry(generation, subscribe),
        onDone: () => _scheduleRepliesWatchRetry(generation, subscribe),
      );
    }

    subscribe();
  }

  void _scheduleRepliesWatchRetry(
    int generation,
    void Function() subscribe,
  ) {
    Future.delayed(const Duration(seconds: 2), () {
      if (!isClosed && generation == _repliesWatchGeneration) subscribe();
    });
  }

  Future<void> _onThreadRepliesUpdated(
    ThreadRepliesUpdated event,
    Emitter<ThreadState> emit,
  ) async {
    if (state is! ThreadLoaded) return;
    final currentState = state as ThreadLoaded;
    final rootNoteId = currentState.rootNoteId;
    if (event.rootNoteId != rootNoteId) return;

    final existingIds = currentState.threadStructure.notesMap.keys.toSet();
    final localThreadData = event.threadData;
    if (isClosed ||
        state is! ThreadLoaded ||
        (state as ThreadLoaded).rootNoteId != rootNoteId ||
        localThreadData == null) {
      return;
    }
    final latestState = state as ThreadLoaded;

    final refreshed = _buildLoadedState(
      localThreadData,
      latestState.chain,
      latestState.currentUserHex,
      repliesSynced: latestState.repliesSynced,
    );
    if (refreshed == null) return;

    final mergedProfiles = Map<String, Map<String, dynamic>>.from(
      latestState.userProfiles,
    )..addAll(refreshed.userProfiles);
    emit(refreshed.copyWith(
      userProfiles: mergedProfiles,
      currentUser: latestState.currentUser,
      isRefreshing: latestState.isRefreshing,
    ));

    final newNotes = refreshed.threadStructure.notesMap.entries
        .where((entry) => !existingIds.contains(entry.key))
        .map((entry) => entry.value)
        .toList();
    if (newNotes.isNotEmpty) {
      _loadAndSyncProfilesForNotes(newNotes, _loadRequestId);
    }
    final refreshedReplies =
        refreshed.replies.map(FeedNote.fromMap).toList(growable: false);
    _interactionService.populateFromNotes(refreshedReplies);
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

    _interactionService.fetchCountsFromRelays(ids).catchError((_) {});
  }

  void _loadAndSyncProfilesForNotes(
    List<Map<String, dynamic>> notes,
    int requestId,
  ) async {
    if (isClosed || requestId != _loadRequestId || state is! ThreadLoaded) {
      return;
    }

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
      if (isClosed || requestId != _loadRequestId) return;

      final updatedProfiles = <String, Map<String, dynamic>>{};
      final missingPubkeys = <String>[];

      for (final pubkey in authorIds) {
        final profile = profiles[pubkey];
        if (profile != null) {
          updatedProfiles[pubkey] = profile.toMap();
          final npub = _authService.hexToNpub(pubkey);
          if (npub != null) updatedProfiles[npub] = profile.toMap();
          if ((profile.name ?? '').isEmpty || (profile.picture ?? '').isEmpty) {
            missingPubkeys.add(pubkey);
          }
        } else {
          missingPubkeys.add(pubkey);
        }
      }

      if (updatedProfiles.isNotEmpty && !isClosed) {
        add(ThreadProfilesUpdated(updatedProfiles, requestId));
      }

      await syncFuture;
      if (isClosed || requestId != _loadRequestId) return;

      if (missingPubkeys.isNotEmpty) {
        final synced = await _profileRepository.getProfiles(missingPubkeys);
        if (isClosed || requestId != _loadRequestId) return;

        final syncedProfiles = <String, Map<String, dynamic>>{};
        for (final entry in synced.entries) {
          syncedProfiles[entry.key] = entry.value.toMap();
          final npub = _authService.hexToNpub(entry.key);
          if (npub != null) syncedProfiles[npub] = entry.value.toMap();
        }

        if (syncedProfiles.isNotEmpty && !isClosed) {
          add(ThreadProfilesUpdated(syncedProfiles, requestId));
        }
      }
    } catch (_) {}
  }

  void _onThreadNetworkFailed(
    ThreadNetworkFailed event,
    Emitter<ThreadState> emit,
  ) {
    if (event.requestId != _loadRequestId) return;
    _failedNetworkLoads.add(event.requestId);
    if (_completedLocalLoads.contains(event.requestId) &&
        state is! ThreadLoaded) {
      emit(const ThreadError('Failed to load thread from network'));
    }
  }

  Future<void> _onThreadRefreshed(
    ThreadRefreshed event,
    Emitter<ThreadState> emit,
  ) async {
    if (state is! ThreadLoaded) return;
    final rootNoteId = _currentRootNoteId ?? (state as ThreadLoaded).rootNoteId;
    if (rootNoteId.isEmpty) return;
    _currentRootNoteId = rootNoteId;
    emit((state as ThreadLoaded).copyWith(isRefreshing: true));
    try {
      await _syncService
          .syncReplies(rootNoteId)
          .timeout(const Duration(seconds: 15));

      if (state is ThreadLoaded &&
          (state as ThreadLoaded).rootNoteId == rootNoteId) {
        final allIds = <String>[rootNoteId];
        for (final reply in (state as ThreadLoaded).replies) {
          final id = reply['id'] as String? ?? '';
          if (id.isNotEmpty) allIds.add(id);
        }

        await _interactionService
            .fetchCountsFromRelays(allIds)
            .timeout(const Duration(seconds: 15));
      }
    } catch (_) {
    } finally {
      if (!isClosed &&
          state is ThreadLoaded &&
          (state as ThreadLoaded).rootNoteId == rootNoteId) {
        emit((state as ThreadLoaded).copyWith(isRefreshing: false));
      }
    }
  }

  @override
  Future<void> close() {
    _loadRequestId++;
    _repliesWatchGeneration++;
    _repliesSubscription?.cancel();
    return super.close();
  }
}
