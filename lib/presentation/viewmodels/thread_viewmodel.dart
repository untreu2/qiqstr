import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../core/base/app_error.dart';
import '../../core/base/result.dart';
import '../../data/repositories/note_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/nostr_data_service.dart';
import '../../data/services/user_batch_fetcher.dart';
import '../../models/note_model.dart';
import '../../models/user_model.dart';

class ThreadViewModel extends BaseViewModel with CommandMixin {
  final NoteRepository _noteRepository;
  final UserRepository _userRepository;
  final NostrDataService _nostrDataService;

  ThreadViewModel({
    required NoteRepository noteRepository,
    required UserRepository userRepository,
    required NostrDataService nostrDataService,
  })  : _noteRepository = noteRepository,
        _userRepository = userRepository,
        _nostrDataService = nostrDataService;

  UIState<NoteModel> _rootNoteState = const InitialState();
  UIState<NoteModel> get rootNoteState => _rootNoteState;

  UIState<List<NoteModel>> _repliesState = const InitialState();
  UIState<List<NoteModel>> get repliesState => _repliesState;

  UIState<ThreadStructure> _threadStructureState = const InitialState();
  UIState<ThreadStructure> get threadStructureState => _threadStructureState;

  final Map<String, UserModel> _userProfiles = {};
  Map<String, UserModel> get userProfiles => Map.unmodifiable(_userProfiles);

  String _rootNoteId = '';
  String get rootNoteId => _rootNoteId;

  String? _focusedNoteId;
  String? get focusedNoteId => _focusedNoteId;

  LoadThreadCommand? _loadThreadCommand;
  AddReplyCommand? _addReplyCommand;
  RefreshThreadCommand? _refreshThreadCommand;

  LoadThreadCommand get loadThreadCommand => _loadThreadCommand ??= LoadThreadCommand(this);
  AddReplyCommand get addReplyCommand => _addReplyCommand ??= AddReplyCommand(this);
  RefreshThreadCommand get refreshThreadCommand => _refreshThreadCommand ??= RefreshThreadCommand(this);

  @override
  void initialize() {
    super.initialize();

    registerCommand('loadThread', loadThreadCommand);
    registerCommand('addReply', addReplyCommand);
    registerCommand('refreshThread', refreshThreadCommand);
  }

  void initializeWithThread({
    required String rootNoteId,
    String? focusedNoteId,
  }) {
    debugPrint('[ThreadViewModel] Initializing thread: $rootNoteId, focused: $focusedNoteId');
    _rootNoteId = rootNoteId;
    _focusedNoteId = focusedNoteId;
    loadThread();
    _subscribeToThreadUpdates();

    debugPrint(' [ThreadViewModel] INSTANT thread loading started');
    _loadThreadInstantly();
  }

  Future<void> loadThread() async {
    await executeOperation('loadThread', () async {
      _rootNoteState = const LoadingState();
      _repliesState = const LoadingState();
      safeNotifyListeners();

      debugPrint(' [ThreadViewModel] INSTANT thread loading for: $_rootNoteId');

      try {
        final results = await Future.wait([
          _noteRepository.getNoteById(_rootNoteId),
          _noteRepository.getThreadReplies(_rootNoteId),
        ]);

        final rootResult = results[0] as Result<NoteModel?>;
        if (rootResult.isError) {
          _rootNoteState = ErrorState(rootResult.error!);
          _repliesState = ErrorState(rootResult.error!);
          safeNotifyListeners();
          return;
        }

        final rootNote = rootResult.data;
        if (rootNote == null) {
          _rootNoteState = const ErrorState('Note not found');
          _repliesState = const ErrorState('Note not found');
          safeNotifyListeners();
          return;
        }

        _rootNoteState = LoadedState(rootNote);

        final repliesResult = results[1] as Result<List<NoteModel>>;
        if (repliesResult.isSuccess) {
          final replies = repliesResult.data!;

          final allThreadNotes = [rootNote, ...replies];
          final allNoteIds = allThreadNotes.map((n) => n.id).toList();

          final updatedNotes = await _calculateInitialInteractionCounts(allThreadNotes);
          final updatedRootNote = updatedNotes.firstWhere((n) => n.id == rootNote.id);
          final updatedReplies = updatedNotes.where((n) => n.id != rootNote.id).toList();

          _rootNoteState = LoadedState(updatedRootNote);
          _repliesState = LoadedState(updatedReplies);

          final structure = _buildThreadStructure(updatedRootNote, updatedReplies);
          _threadStructureState = LoadedState(structure);

          debugPrint(' [ThreadViewModel] Initial counts calculated for ${allNoteIds.length} notes');

          Future.delayed(const Duration(seconds: 3), () {
            if (!isDisposed) {
              debugPrint(' [ThreadViewModel] Starting delayed interaction fetch...');
              _fetchInteractionsAndUpdateNotes(allNoteIds);
            }
          });

          _loadUserProfiles(allThreadNotes);
        } else {
          _repliesState = ErrorState(repliesResult.error!);
        }

        safeNotifyListeners();
        debugPrint(' [ThreadViewModel] INSTANT thread loading completed');
      } catch (e) {
        debugPrint(' [ThreadViewModel] Error in instant thread loading: $e');
        _rootNoteState = ErrorState('Failed to load thread: $e');
        _repliesState = ErrorState('Failed to load thread: $e');
        safeNotifyListeners();
      }
    });
  }

  Future<void> _loadThreadInstantly() async {
    loadThread();

    if (_rootNoteId.isNotEmpty) {
      debugPrint(' [ThreadViewModel] Pre-loading interactions for root: $_rootNoteId');
      _fetchInteractionsAndUpdateNotes([_rootNoteId]);
    }

    _setupPeriodicInteractionRefresh();
  }

  Future<List<NoteModel>> _calculateInitialInteractionCounts(List<NoteModel> threadNotes) async {
    try {
      final updatedNotes = <NoteModel>[];

      for (final note in threadNotes) {
        final replyCount =
            threadNotes.where((n) => n.isReply && (n.parentId == note.id || (n.rootId == note.id && n.parentId != note.id))).length;

        final cachedNotes = _nostrDataService.cachedNotes;
        final repostCount = cachedNotes.where((n) => n.isRepost && n.rootId == note.id).length;

        final updatedNote = NoteModel(
          id: note.id,
          content: note.content,
          author: note.author,
          timestamp: note.timestamp,
          isRepost: note.isRepost,
          repostedBy: note.repostedBy,
          repostTimestamp: note.repostTimestamp,
          repostCount: repostCount,
          rawWs: note.rawWs,
          reactionCount: note.reactionCount,
          replyCount: replyCount,
          hasMedia: note.hasMedia,
          estimatedHeight: note.estimatedHeight,
          isVideo: note.isVideo,
          videoUrl: note.videoUrl,
          zapAmount: note.zapAmount,
          isReply: note.isReply,
          parentId: note.parentId,
          rootId: note.rootId,
          replyIds: note.replyIds,
          eTags: note.eTags,
          pTags: note.pTags,
          replyMarker: note.replyMarker,
        );

        _persistentReplyCounts[note.id] = replyCount;
        _persistentRepostCounts[note.id] = repostCount;

        updatedNotes.add(updatedNote);
        debugPrint(' [ThreadViewModel] Initial counts persisted for ${note.id}: replies=$replyCount, reposts=$repostCount');
      }

      return updatedNotes;
    } catch (e) {
      debugPrint(' [ThreadViewModel] Error calculating initial counts: $e');
      return threadNotes; // Return original notes if calculation fails
    }
  }

  Future<void> _fetchInteractionsAndUpdateNotes(List<String> noteIds) async {
    try {
      debugPrint(' [ThreadViewModel] Enhanced interaction fetch for: $noteIds');

      final allInteractionIds = <String>[];
      allInteractionIds.addAll(noteIds);

      await _addOriginalNoteIdsForReposts(allInteractionIds);

      debugPrint('[ThreadViewModel] Total interaction IDs to fetch: ${allInteractionIds.length}');

      await _nostrDataService.fetchInteractionsForNotes(allInteractionIds, forceLoad: true);

      await Future.delayed(const Duration(milliseconds: 500));

      await _performEnhancedNoteUpdates(allInteractionIds);

      _triggerThreadUIUpdates();

      debugPrint(' [ThreadViewModel] Enhanced interaction fetch completed for ${allInteractionIds.length} notes');
    } catch (e) {
      debugPrint(' [ThreadViewModel] Error in enhanced interaction fetch: $e');
    }
  }

  Future<void> _performEnhancedNoteUpdates(List<String> noteIds) async {
    try {
      final latestNotes = _nostrDataService.cachedNotes;

      await _calculateAndUpdateInteractionCounts(noteIds, latestNotes);

      if (_rootNoteState.isLoaded) {
        final rootNote = _rootNoteState.data!;
        final updatedRootNote = await _getUpdatedNoteWithCounts(rootNote, latestNotes);

        await _noteRepository.updateNote(updatedRootNote);
        _rootNoteState = LoadedState(updatedRootNote);
        debugPrint(
            ' [ThreadViewModel] Root note updated in repository: reactions=${updatedRootNote.reactionCount}, replies=${updatedRootNote.replyCount}, reposts=${updatedRootNote.repostCount}');
      }

      if (_repliesState.isLoaded) {
        final replies = _repliesState.data!;
        final updatedReplies = <NoteModel>[];

        for (final reply in replies) {
          final updatedReply = await _getUpdatedNoteWithCounts(reply, latestNotes);

          await _noteRepository.updateNote(updatedReply);
          updatedReplies.add(updatedReply);
          debugPrint(
              ' [ThreadViewModel] Reply ${reply.id} updated in repository: reactions=${updatedReply.reactionCount}, replies=${updatedReply.replyCount}, reposts=${updatedReply.repostCount}');
        }

        _repliesState = LoadedState(updatedReplies);

        if (_rootNoteState.isLoaded) {
          final structure = _buildThreadStructure(_rootNoteState.data!, updatedReplies);
          _threadStructureState = LoadedState(structure);
        }
      }

      debugPrint(' [ThreadViewModel] Enhanced note updates with proper counts completed and persisted to repository');
    } catch (e) {
      debugPrint(' [ThreadViewModel] Error in enhanced note updates: $e');
    }
  }

  Future<void> _calculateAndUpdateInteractionCounts(List<String> noteIds, List<NoteModel> cachedNotes) async {
    try {
      final replyCounts = <String, int>{};
      final repostCounts = <String, int>{};

      for (final noteId in noteIds) {
        final directReplies = cachedNotes.where((note) => note.isReply && (note.parentId == noteId || note.rootId == noteId)).length;
        replyCounts[noteId] = directReplies;

        final reposts = cachedNotes.where((note) => note.isRepost && note.rootId == noteId).length;
        repostCounts[noteId] = reposts;

        debugPrint('[ThreadViewModel] Note $noteId: $directReplies replies, $reposts reposts');
      }

      _tempReplyCounts = replyCounts;
      _tempRepostCounts = repostCounts;
    } catch (e) {
      debugPrint(' [ThreadViewModel] Error calculating interaction counts: $e');
    }
  }

  final Map<String, int> _persistentReplyCounts = {};
  final Map<String, int> _persistentRepostCounts = {};

  Map<String, int> _tempReplyCounts = {};
  Map<String, int> _tempRepostCounts = {};

  Future<NoteModel> _getUpdatedNoteWithCounts(NoteModel originalNote, List<NoteModel> cachedNotes) async {
    final latestNote = cachedNotes.where((n) => n.id == originalNote.id).firstOrNull ?? originalNote;

    final replyCount = _persistentReplyCounts[originalNote.id] ?? _tempReplyCounts[originalNote.id] ?? originalNote.replyCount;
    final repostCount = _persistentRepostCounts[originalNote.id] ?? _tempRepostCounts[originalNote.id] ?? originalNote.repostCount;

    if (replyCount > 0 || originalNote.replyCount > 0) {
      _persistentReplyCounts[originalNote.id] = math.max(replyCount, originalNote.replyCount);
    }
    if (repostCount > 0 || originalNote.repostCount > 0) {
      _persistentRepostCounts[originalNote.id] = math.max(repostCount, originalNote.repostCount);
    }

    final finalReplyCount = _persistentReplyCounts[originalNote.id] ?? replyCount;
    final finalRepostCount = _persistentRepostCounts[originalNote.id] ?? repostCount;

    debugPrint(' [ThreadViewModel] Preserving counts for ${originalNote.id}: replies=$finalReplyCount, reposts=$finalRepostCount');

    return NoteModel(
      id: latestNote.id,
      content: latestNote.content,
      author: latestNote.author,
      timestamp: latestNote.timestamp,
      isRepost: latestNote.isRepost,
      repostedBy: latestNote.repostedBy,
      repostTimestamp: latestNote.repostTimestamp,
      repostCount: finalRepostCount,
      rawWs: latestNote.rawWs,
      reactionCount: latestNote.reactionCount, // This comes from NostrDataService
      replyCount: finalReplyCount,
      hasMedia: latestNote.hasMedia,
      estimatedHeight: latestNote.estimatedHeight,
      isVideo: latestNote.isVideo,
      videoUrl: latestNote.videoUrl,
      zapAmount: latestNote.zapAmount, // This comes from NostrDataService
      isReply: latestNote.isReply,
      parentId: latestNote.parentId,
      rootId: latestNote.rootId,
      replyIds: latestNote.replyIds,
      eTags: latestNote.eTags,
      pTags: latestNote.pTags,
      replyMarker: latestNote.replyMarker,
    );
  }

  void _triggerThreadUIUpdates() {
    safeNotifyListeners();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (!isDisposed) {
        safeNotifyListeners();
      }
    });

    debugPrint(' [ThreadViewModel] Thread UI updates triggered');
  }

  Future<void> _addOriginalNoteIdsForReposts(List<String> interactionIds) async {
    try {
      final currentNotes = <NoteModel>[];

      if (_rootNoteState.isLoaded && _rootNoteState.data != null) {
        currentNotes.add(_rootNoteState.data!);
      }
      if (_repliesState.isLoaded && _repliesState.data != null) {
        currentNotes.addAll(_repliesState.data!);
      }

      for (final note in currentNotes) {
        if (note.isRepost && note.rootId != null && note.rootId!.isNotEmpty) {
          if (!interactionIds.contains(note.rootId!)) {
            interactionIds.add(note.rootId!);
            debugPrint(' [ThreadViewModel] Added original note ID for repost: ${note.rootId}');
          }
        }
      }
    } catch (e) {
      debugPrint(' [ThreadViewModel] Error adding original note IDs: $e');
    }
  }

  void _setupPeriodicInteractionRefresh() {
    addSubscription(Stream.periodic(const Duration(seconds: 2)).listen((_) async {
      if (!isDisposed && (_rootNoteState.isLoaded || _repliesState.isLoaded)) {
        final allNoteIds = <String>[];

        if (_rootNoteState.isLoaded && _rootNoteState.data != null) {
          allNoteIds.add(_rootNoteState.data!.id);
        }

        if (_repliesState.isLoaded && _repliesState.data != null) {
          allNoteIds.addAll(_repliesState.data!.map((r) => r.id));
        }

        if (allNoteIds.isNotEmpty) {
          debugPrint(' [ThreadViewModel] Enhanced periodic refresh for ${allNoteIds.length} notes');
          await _fetchInteractionsAndUpdateNotes(allNoteIds);
        }
      }
    }));

    addSubscription(_noteRepository.notesStream.listen((updatedNotes) {
      if (!isDisposed && updatedNotes.isNotEmpty) {
        _handleRealTimeNoteUpdates(updatedNotes);
      }
    }));
  }

  void _handleRealTimeNoteUpdates(List<NoteModel> updatedNotes) {
    try {
      bool hasRelevantUpdates = false;

      final threadNoteIds = <String>[];

      if (_rootNoteState.isLoaded && _rootNoteState.data != null) {
        threadNoteIds.add(_rootNoteState.data!.id);
      }

      if (_repliesState.isLoaded && _repliesState.data != null) {
        threadNoteIds.addAll(_repliesState.data!.map((r) => r.id));
      }

      final relevantUpdates = updatedNotes.where((note) => threadNoteIds.contains(note.id)).toList();

      if (relevantUpdates.isNotEmpty) {
        debugPrint(' [ThreadViewModel] Real-time updates for ${relevantUpdates.length} thread notes');

        for (final updatedNote in relevantUpdates) {
          if (_rootNoteState.isLoaded && _rootNoteState.data!.id == updatedNote.id) {
            _rootNoteState = LoadedState(updatedNote);
            hasRelevantUpdates = true;
          }

          if (_repliesState.isLoaded && _repliesState.data != null) {
            final replies = _repliesState.data!;
            final index = replies.indexWhere((r) => r.id == updatedNote.id);
            if (index != -1) {
              replies[index] = updatedNote;
              _repliesState = LoadedState(List.from(replies));
              hasRelevantUpdates = true;
            }
          }
        }

        if (hasRelevantUpdates) {
          _triggerThreadUIUpdates();
        }
      }
    } catch (e) {
      debugPrint(' [ThreadViewModel] Error handling real-time updates: $e');
    }
  }

  Future<void> refreshThread() async {
    debugPrint(' [ThreadViewModel] INSTANT thread refresh');
    await loadThread();
  }

  Future<void> addReply({
    required String content,
    required String parentNoteId,
    String? rootId,
  }) async {
    await executeOperation('addReply', () async {
      final parentNote =
          _rootNoteId == parentNoteId ? _rootNoteState.data : _repliesState.data?.where((n) => n.id == parentNoteId).firstOrNull;

      if (parentNote == null) {
        throw Exception('Parent note not found');
      }

      final result = await _noteRepository.postReply(
        content: content,
        rootId: rootId ?? _rootNoteId,
        replyId: parentNoteId,
        parentAuthor: parentNote.author,
        relayUrls: ['wss://relay.damus.io'], // Default relay
      );

      if (result.isError) {
        throw Exception(result.error);
      }

      await loadThread();
    });
  }

  Future<void> _loadUserProfiles(List<NoteModel> notes) async {
    try {
      debugPrint('[ThreadViewModel] Loading user profiles for ${notes.length} notes');

      final Set<String> authorIds = {};
      for (final note in notes) {
        authorIds.add(note.author);
        if (note.repostedBy != null) {
          authorIds.add(note.repostedBy!);
        }
      }

      debugPrint('[ThreadViewModel] Found ${authorIds.length} unique authors to load');

      final missingAuthorIds = authorIds.where((id) {
        final cachedProfile = _userProfiles[id];
        return cachedProfile == null || cachedProfile.profileImage.isEmpty;
      }).toList();

      if (missingAuthorIds.isEmpty) {
        debugPrint('[ThreadViewModel] All profiles already cached with images');
        return;
      }

      debugPrint('[ThreadViewModel] Batch fetching ${missingAuthorIds.length} profiles (including those with missing images)');

      final results = await _userRepository.getUserProfiles(
        missingAuthorIds,
        priority: FetchPriority.high,
      );

      for (final entry in results.entries) {
        entry.value.fold(
          (user) {
            _userProfiles[entry.key] = user;
            debugPrint('[ThreadViewModel]  Loaded profile: ${user.name} (image: ${user.profileImage.isNotEmpty ? "✓" : "✗"})');
          },
          (error) {
            if (!_userProfiles.containsKey(entry.key)) {
              _userProfiles[entry.key] = UserModel(
                pubkeyHex: entry.key,
                name: entry.key.length > 8 ? entry.key.substring(0, 8) : entry.key,
                about: '',
                profileImage: '',
                banner: '',
                website: '',
                nip05: '',
                lud16: '',
                updatedAt: DateTime.now(),
                nip05Verified: false,
              );
            }
          },
        );
      }

      debugPrint('[ThreadViewModel]  Profile batch loading complete, total cached: ${_userProfiles.length}');
      safeNotifyListeners(); // Notify UI about profile updates
    } catch (e) {
      debugPrint('[ThreadViewModel]  Error loading user profiles: $e');
    }
  }

  ThreadStructure _buildThreadStructure(NoteModel root, List<NoteModel> replies) {
    debugPrint(' [ThreadViewModel] Building thread structure for root: ${root.id}');
    debugPrint(' [ThreadViewModel] Processing ${replies.length} replies');

    final Map<String, List<NoteModel>> childrenMap = {};
    final Map<String, NoteModel> notesMap = {root.id: root};

    for (final reply in replies) {
      notesMap[reply.id] = reply;
      debugPrint('[ThreadViewModel] Reply ${reply.id}: parentId=${reply.parentId}, rootId=${reply.rootId}, isReply=${reply.isReply}');
    }

    for (final reply in replies) {
      final parentId = reply.parentId ?? root.id;
      debugPrint('[ThreadViewModel] Linking reply ${reply.id} to parent $parentId');

      childrenMap.putIfAbsent(parentId, () => []);
      childrenMap[parentId]!.add(reply);
    }

    for (final children in childrenMap.values) {
      children.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    debugPrint(' [ThreadViewModel] Thread structure complete:');
    debugPrint('   Root note: ${root.id}');
    debugPrint('   Total replies: ${replies.length}');
    debugPrint('   Children map keys: ${childrenMap.keys.toList()}');
    for (final entry in childrenMap.entries) {
      debugPrint('   Parent ${entry.key} has ${entry.value.length} children: ${entry.value.map((n) => n.id).toList()}');
    }

    return ThreadStructure(
      rootNote: root,
      childrenMap: childrenMap,
      notesMap: notesMap,
      totalReplies: replies.length,
    );
  }

  void _subscribeToThreadUpdates() {
    addSubscription(
      _noteRepository.realTimeNotesStream.listen((notes) {
        if (!isDisposed && _rootNoteState.isLoaded) {
          final rootNote = _rootNoteState.data!;
          final newThreadNotes = notes
              .where((note) =>
                  note.id == _rootNoteId ||
                  note.rootId == _rootNoteId ||
                  note.parentId == _rootNoteId ||
                  (note.isReply && (note.rootId == rootNote.rootId || note.parentId == rootNote.id)))
              .toList();

          if (newThreadNotes.isNotEmpty) {
            debugPrint('[ThreadViewModel] Received ${newThreadNotes.length} thread updates from stream');
            loadThread();
          }
        }
      }),
    );
  }

  Future<void> reactToNote(String noteId, String reaction) async {
    try {
      debugPrint('[ThreadViewModel] Reacting to note: $noteId with $reaction');

      final result = await _noteRepository.reactToNote(noteId, reaction);
      result.fold(
        (_) {
          debugPrint('[ThreadViewModel] Reaction sent successfully');
          loadThread();
        },
        (error) {
          debugPrint('[ThreadViewModel] Reaction failed: $error');
          setError(NetworkError(message: 'Failed to react: $error'));
        },
      );
    } catch (e) {
      debugPrint('[ThreadViewModel] Exception in reactToNote: $e');
      setError(NetworkError(message: 'Failed to react: $e'));
    }
  }

  Future<void> repostNote(String noteId) async {
    try {
      debugPrint('[ThreadViewModel] Reposting note: $noteId');

      final result = await _noteRepository.repostNote(noteId);
      result.fold(
        (_) {
          debugPrint('[ThreadViewModel] Repost sent successfully');
          loadThread();
        },
        (error) {
          debugPrint('[ThreadViewModel] Repost failed: $error');
          setError(NetworkError(message: 'Failed to repost: $error'));
        },
      );
    } catch (e) {
      debugPrint('[ThreadViewModel] Exception in repostNote: $e');
      setError(NetworkError(message: 'Failed to repost: $e'));
    }
  }

  List<NoteModel> getReplies(String noteId) {
    if (_threadStructureState.isLoaded) {
      final structure = _threadStructureState.data!;
      return structure.getChildren(noteId);
    }
    return [];
  }

  int getThreadDepth(String noteId) {
    if (_threadStructureState.isLoaded) {
      final structure = _threadStructureState.data!;
      return structure.getDepth(noteId);
    }
    return 0;
  }

  NoteModel? get currentRootNote => _rootNoteState.data;

  List<NoteModel> get currentReplies => _repliesState.data ?? [];

  bool get isThreadLoading => _rootNoteState.isLoading || _repliesState.isLoading;

  String? get threadErrorMessage => _rootNoteState.error ?? _repliesState.error;

  @override
  void dispose() {
    _persistCalculatedCountsOnDispose();
    super.dispose();
  }

  Future<void> _persistCalculatedCountsOnDispose() async {
    try {
      debugPrint(' [ThreadViewModel] Persisting calculated counts on dispose...');

      if (_rootNoteState.isLoaded && _rootNoteState.data != null) {
        final rootNote = _rootNoteState.data!;
        final persistedRootNote = await _createNoteWithPersistedCounts(rootNote);
        await _noteRepository.updateNote(persistedRootNote);
        debugPrint(' [ThreadViewModel] Root note counts persisted: ${rootNote.id}');
      }

      if (_repliesState.isLoaded && _repliesState.data != null) {
        for (final reply in _repliesState.data!) {
          final persistedReply = await _createNoteWithPersistedCounts(reply);
          await _noteRepository.updateNote(persistedReply);
          debugPrint(' [ThreadViewModel] Reply counts persisted: ${reply.id}');
        }
      }

      debugPrint(' [ThreadViewModel] All calculated counts persisted to repository');
    } catch (e) {
      debugPrint(' [ThreadViewModel] Error persisting counts on dispose: $e');
    }
  }

  Future<NoteModel> _createNoteWithPersistedCounts(NoteModel note) async {
    final persistedReplyCount = _persistentReplyCounts[note.id] ?? note.replyCount;
    final persistedRepostCount = _persistentRepostCounts[note.id] ?? note.repostCount;

    return NoteModel(
      id: note.id,
      content: note.content,
      author: note.author,
      timestamp: note.timestamp,
      isRepost: note.isRepost,
      repostedBy: note.repostedBy,
      repostTimestamp: note.repostTimestamp,
      repostCount: persistedRepostCount,
      rawWs: note.rawWs,
      reactionCount: note.reactionCount,
      replyCount: persistedReplyCount,
      hasMedia: note.hasMedia,
      estimatedHeight: note.estimatedHeight,
      isVideo: note.isVideo,
      videoUrl: note.videoUrl,
      zapAmount: note.zapAmount,
      isReply: note.isReply,
      parentId: note.parentId,
      rootId: note.rootId,
      replyIds: note.replyIds,
      eTags: note.eTags,
      pTags: note.pTags,
      replyMarker: note.replyMarker,
    );
  }

  @override
  void onRetry() {
    if (_rootNoteId.isNotEmpty) {
      loadThread();
    }
  }
}

class ThreadStructure {
  final NoteModel rootNote;
  final Map<String, List<NoteModel>> childrenMap;
  final Map<String, NoteModel> notesMap;
  final int totalReplies;

  ThreadStructure({
    required this.rootNote,
    required this.childrenMap,
    required this.notesMap,
    required this.totalReplies,
  });

  List<NoteModel> getChildren(String noteId) {
    return childrenMap[noteId] ?? [];
  }

  NoteModel? getNote(String noteId) {
    return notesMap[noteId];
  }

  int getDepth(String noteId) {
    int depth = 0;
    NoteModel? current = notesMap[noteId];

    while (current != null && current.parentId != null) {
      depth++;
      current = notesMap[current.parentId!];
    }

    return depth;
  }

  bool hasChildren(String noteId) {
    return childrenMap.containsKey(noteId) && childrenMap[noteId]!.isNotEmpty;
  }

  List<NoteModel> getAllNotes() {
    return notesMap.values.toList();
  }
}

class LoadThreadCommand extends ParameterlessCommand {
  final ThreadViewModel _viewModel;

  LoadThreadCommand(this._viewModel);

  @override
  Future<void> executeImpl() => _viewModel.loadThread();
}

class RefreshThreadCommand extends ParameterlessCommand {
  final ThreadViewModel _viewModel;

  RefreshThreadCommand(this._viewModel);

  @override
  Future<void> executeImpl() => _viewModel.refreshThread();
}

class AddReplyCommand extends ParameterizedCommand<ReplyParams> {
  final ThreadViewModel _viewModel;

  AddReplyCommand(this._viewModel);

  @override
  Future<void> executeImpl(ReplyParams params) async {
    await _viewModel.addReply(
      content: params.content,
      parentNoteId: params.parentNoteId,
      rootId: params.rootId,
    );
  }
}

class ReplyParams {
  final String content;
  final String parentNoteId;
  final String? rootId;

  ReplyParams({
    required this.content,
    required this.parentNoteId,
    this.rootId,
  });
}
