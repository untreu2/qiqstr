import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/encrypted_mute_service.dart';
import '../../../data/services/interaction_service.dart';
import '../../../domain/entities/feed_note.dart';
import '../../../src/rust/api/database.dart' as rust_db;
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
  StreamSubscription<List<FeedNote>>? _repliesSubscription;

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
    on<ThreadLoadRequested>(_onThreadLoaded);
    on<ThreadRefreshed>(_onThreadRefreshed);
    on<ThreadProfilesUpdated>(_onThreadProfilesUpdated);
    on<ThreadRepliesUpdated>(_onThreadRepliesUpdated);
    on<ThreadCurrentUserLoaded>(_onThreadCurrentUserLoaded);
    on<ThreadNetworkDataLoaded>(_onThreadNetworkDataLoaded);
    on<ThreadNetworkFailed>(_onThreadNetworkFailed);
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
    ThreadCurrentUserLoaded event,
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
      } else if (state is! ThreadLoaded) {
        emit(const ThreadLoading());
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
      final json = await rust_db.dbGetHydratedThreadStructure(
        rootNoteId: noteId,
        currentUserPubkeyHex: currentUserHex,
        limit: 500,
      );
      final data = jsonDecode(json) as Map<String, dynamic>;
      if (data.containsKey('error')) {
        return await _syncService.fetchFullThreadLocal(
          noteId,
          currentUserPubkeyHex: currentUserHex,
          mutedPubkeys: _muteService.mutedPubkeys,
          mutedWords: _muteService.mutedWords,
        );
      }
      return _convertStructureToThreadData(data);
    } catch (_) {
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
  }

  Map<String, dynamic> _convertStructureToThreadData(
      Map<String, dynamic> data) {
    final allReplies =
        (data['allReplies'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
            [];
    final notesMap =
        (data['notesMap'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, v as Map<String, dynamic>),
            ) ??
            {};
    final childrenMap =
        (data['childrenMap'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(
                  k,
                  (v as List<dynamic>).cast<Map<String, dynamic>>()),
            ) ??
            {};
    return {
      'rootNote': data['rootNote'],
      'chainNotes': data['chainNotes'],
      'childrenMap': childrenMap,
      'notesMap': notesMap,
      'totalReplies': data['totalReplies'] ?? allReplies.length,
    };
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
        add(ThreadNetworkDataLoaded(threadData, chain, currentUserHex));
      }
    }).catchError((e) {
      if (!isClosed) {
        add(const ThreadNetworkFailed());
      }
    });
  }

  void _onThreadNetworkDataLoaded(
    ThreadNetworkDataLoaded event,
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
      _interactionService.setCurrentUser(event.currentUserHex);
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
        add(ThreadCurrentUserLoaded(profile.toMap()));
      }
    }).catchError((_) {});
  }

  void _watchReplies(String rootNoteId) {
    _repliesSubscription?.cancel();
    _repliesSubscription =
        _feedRepository.watchThreadReplies(rootNoteId).listen((replies) {
      if (isClosed) return;
      add(ThreadRepliesUpdated(replies));
    });
  }

  Future<void> _onThreadRepliesUpdated(
    ThreadRepliesUpdated event,
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

    // Re-query thread structure from Rust — avoids Dart-side tree rebuild
    Map<String, dynamic>? freshStructure;
    try {
      final json = await rust_db.dbGetHydratedThreadStructure(
        rootNoteId: currentState.rootNoteId,
        currentUserPubkeyHex: currentState.currentUserHex.isNotEmpty
            ? currentState.currentUserHex
            : null,
        limit: 500,
      );
      final data = jsonDecode(json) as Map<String, dynamic>;
      if (!data.containsKey('error')) {
        freshStructure = data;
      }
    } catch (_) {}

    if (isClosed) return;

    Map<String, List<Map<String, dynamic>>> childrenMap;
    Map<String, Map<String, dynamic>> notesMap;
    List<Map<String, dynamic>> repliesMap;
    int quoteCount;

    if (freshStructure != null) {
      repliesMap =
          (freshStructure['allReplies'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
              [];
      quoteCount = (freshStructure['quoteCount'] as int?) ?? 0;
      notesMap = (freshStructure['notesMap'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as Map<String, dynamic>),
          ) ??
          {};
      childrenMap =
          (freshStructure['childrenMap'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(
                    k,
                    (v as List<dynamic>).cast<Map<String, dynamic>>()),
              ) ??
              {};
    } else {
      // Fallback: merge existing + new replies in Dart
      repliesMap = event.replies.map((r) => r.toMap()).toList();
      final replyIds = incomingIds;
      for (final existing in currentState.replies) {
        final eid = existing['id'] as String? ?? '';
        if (eid.isNotEmpty && !replyIds.contains(eid)) {
          repliesMap.add(existing);
          replyIds.add(eid);
        }
      }
      quoteCount = 0;
      notesMap = {
        currentState.rootNoteId: currentState.rootNote,
        for (final r in repliesMap)
          if (r['id'] != null) r['id'] as String: r,
      };
      childrenMap = {};
    }

    final threadStructure = ThreadStructure(
      rootNote: currentState.rootNote,
      childrenMap: childrenMap,
      notesMap: notesMap,
      totalReplies: repliesMap.length,
    );

    emit(
      currentState.copyWith(
        replies: repliesMap,
        threadStructure: threadStructure,
        quoteCount: quoteCount,
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
      _interactionService.populateFromNotes(newFeedNotes);
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

    _interactionService.fetchCountsFromRelays(ids).catchError((_) {});
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
          if ((profile.name ?? '').isEmpty || (profile.picture ?? '').isEmpty) {
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
    ThreadNetworkFailed event,
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

        await _interactionService.fetchCountsFromRelays(allIds);
      }
    } catch (_) {}
  }

  @override
  Future<void> close() {
    _repliesSubscription?.cancel();
    return super.close();
  }
}
