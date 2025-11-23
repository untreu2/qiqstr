import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nostr_nip19/nostr_nip19.dart';

import '../../core/base/result.dart';
import '../../models/note_model.dart';
import '../../models/reaction_model.dart';
import '../../models/zap_model.dart';
import '../filters/feed_filters.dart';
import '../services/network_service.dart';
import '../services/nostr_data_service.dart';
import '../services/mute_cache_service.dart';
import '../services/user_batch_fetcher.dart';
import '../../services/lifecycle_manager.dart';
import 'user_repository.dart';

class NoteRepository {
  final NostrDataService _nostrDataService;
  final UserRepository? _userRepository;
  DateTime? _lastNotesUpdate;
  final Map<String, NoteModel> _notesCache = {};
  final List<NoteModel> _allNotes = [];

  NostrDataService get nostrDataService => _nostrDataService;

  final Map<String, List<ReactionModel>> _reactions = {};
  final Map<String, List<ZapModel>> _zaps = {};

  final StreamController<List<NoteModel>> _notesController = StreamController<List<NoteModel>>.broadcast();
  final StreamController<Map<String, List<ReactionModel>>> _reactionsController =
      StreamController<Map<String, List<ReactionModel>>>.broadcast();

  StreamSubscription<List<NoteModel>>? _dataServiceSubscription;
  StreamSubscription<String>? _deletionSubscription;
  bool _isPaused = false;

  NoteRepository({
    required NetworkService networkService,
    required NostrDataService nostrDataService,
    UserRepository? userRepository,
  })  : _nostrDataService = nostrDataService,
        _userRepository = userRepository {
    _setupNostrDataServiceForwarding();
    _setupLifecycleCallbacks();
  }

  void _setupLifecycleCallbacks() {
    LifecycleManager().addOnPauseCallback(_onAppPaused);
    LifecycleManager().addOnResumeCallback(_onAppResumed);
  }

  void _onAppPaused() {
    debugPrint('[NoteRepository] App paused - stopping updates');
    _isPaused = true;
  }

  void _onAppResumed() {
    debugPrint('[NoteRepository] App resumed - restarting updates');
    _isPaused = false;
    _notesController.add(List.unmodifiable(_allNotes));
  }

  Future<Result<List<NoteModel>>> getFilteredNotes(BaseFeedFilter filter) async {
    try {
      debugPrint('[NoteRepository] Applying filter: ${filter.filterKey}');

      final allCachedNotes = _getAllCachedNotes();
      final filtered = filter.apply(allCachedNotes);

      final seenIds = <String>{};
      final deduplicatedNotes = <NoteModel>[];
      for (final note in filtered) {
        if (!seenIds.contains(note.id)) {
          seenIds.add(note.id);
          deduplicatedNotes.add(note);
        }
      }

      debugPrint('[NoteRepository] Filter returned ${filtered.length} notes, after deduplication: ${deduplicatedNotes.length}');

      return Result.success(deduplicatedNotes);
    } catch (e) {
      debugPrint('[NoteRepository] Exception in getFilteredNotes: $e');
      return Result.error('Failed to apply filter: ${e.toString()}');
    }
  }

  Future<Result<void>> fetchNotesFromRelays({
    List<String>? authorNpubs,
    String? hashtag,
    int limit = 50,
    DateTime? until,
    DateTime? since,
    bool isProfileMode = false,
  }) async {
    try {
      if (authorNpubs != null && authorNpubs.isNotEmpty) {
        debugPrint('[NoteRepository] Fetching notes for ${authorNpubs.length} authors (profile mode: $isProfileMode)');

        if (isProfileMode && authorNpubs.length == 1) {
          final result = await _nostrDataService.fetchProfileNotes(
            userNpub: authorNpubs.first,
            limit: limit,
            until: until,
            since: since,
          );
          return result.isSuccess ? const Result.success(null) : Result.error(result.error!);
        }

        final result = await _nostrDataService.fetchFeedNotes(
          authorNpubs: authorNpubs,
          limit: limit,
          until: until,
          since: since,
        );
        return result.isSuccess ? const Result.success(null) : Result.error(result.error!);
      }

      if (hashtag != null && hashtag.isNotEmpty) {
        debugPrint('[NoteRepository] Fetching notes for hashtag: $hashtag');
        final result = await _nostrDataService.fetchHashtagNotes(
          hashtag: hashtag,
          limit: limit,
          until: until,
          since: since,
        );
        return result.isSuccess ? const Result.success(null) : Result.error(result.error!);
      }

      debugPrint('[NoteRepository] No authorNpubs or hashtag provided - skipping fetch');
      return const Result.success(null);
    } catch (e) {
      debugPrint('[NoteRepository] Exception in fetchNotesFromRelays: $e');
      return Result.error('Failed to fetch notes: ${e.toString()}');
    }
  }

  List<NoteModel> _getAllCachedNotes() {
    final allNotes = <NoteModel>[];
    allNotes.addAll(_allNotes);

    final serviceNotes = _nostrDataService.cachedNotes;
    if (serviceNotes.isEmpty) return allNotes;

    final existingIds = _notesCache.keys.toSet();
    final newNotes = <NoteModel>[];

    for (final note in serviceNotes) {
      if (_isNoteFromMutedUser(note)) {
        continue;
      }

      if (!existingIds.contains(note.id)) {
        newNotes.add(note);
        _notesCache[note.id] = note;
      }
    }

    if (newNotes.isNotEmpty) {
      _allNotes.addAll(newNotes);
      allNotes.addAll(newNotes);
    }

    return allNotes;
  }

  Future<Result<NoteModel?>> getNoteById(String noteId) async {
    try {
      debugPrint('[NoteRepository] Looking for note ID: $noteId');

      final localNote = _notesCache[noteId];
      if (localNote != null) {
        debugPrint('[NoteRepository] Found note in local cache: ${localNote.id}');
        return Result.success(localNote);
      }

      final cachedNotes = _nostrDataService.cachedNotes;
      NoteModel? cachedNote;
      for (final note in cachedNotes) {
        if (note.id == noteId) {
          cachedNote = note;
          break;
        }
      }
      if (cachedNote != null) {
        debugPrint('[NoteRepository] Found note in NostrDataService cache: ${cachedNote.id}');
        if (!_notesCache.containsKey(cachedNote.id)) {
          _notesCache[cachedNote.id] = cachedNote;
          _allNotes.add(cachedNote);
        }
        return Result.success(cachedNote);
      }

      debugPrint('[NoteRepository] Note not found in cache, fetching from relays...');

      final success = await _fetchNoteDirectly(noteId);
      if (success) {
        NoteModel? fetchedNote;
        for (final note in _nostrDataService.cachedNotes) {
          if (note.id == noteId) {
            fetchedNote = note;
            break;
          }
        }
        if (fetchedNote != null) {
          debugPrint('[NoteRepository] Successfully fetched note: ${fetchedNote.id}');
          _notesCache[fetchedNote.id] = fetchedNote;
          _allNotes.add(fetchedNote);
          return Result.success(fetchedNote);
        }
      }

      debugPrint('[NoteRepository] Note not found anywhere: $noteId');
      return const Result.success(null);
    } catch (e) {
      debugPrint('[NoteRepository] Error getting note by ID: $e');
      return Result.error('Failed to get note: ${e.toString()}');
    }
  }

  Future<bool> _fetchNoteDirectly(String noteId) async {
    try {
      debugPrint('[NoteRepository] Directly fetching note from relays: $noteId');

      final success = await _nostrDataService.fetchSpecificNote(noteId);

      if (success) {
        debugPrint('[NoteRepository] Successfully requested note from relays: $noteId');
        return true;
      } else {
        debugPrint('[NoteRepository] Failed to request note from relays: $noteId');
        return false;
      }
    } catch (e) {
      debugPrint('[NoteRepository] Error in direct note fetch: $e');
      return false;
    }
  }

  Future<Result<List<NoteModel>>> getThreadReplies(String rootNoteId, {bool fetchFromRelays = false}) async {
    try {
      if (fetchFromRelays) {
        await _nostrDataService.fetchThreadRepliesForNote(rootNoteId);
        await Future.delayed(const Duration(milliseconds: 500));
      }

      debugPrint('[NoteRepository] Getting thread replies for root: $rootNoteId');

      final allNotes = _getAllCachedNotes();

      debugPrint('[NoteRepository] Combined cache has ${allNotes.length} notes total');

      final threadReplies = allNotes.where((note) {
        final isReply = note.isReply;
        final hasCorrectRoot = note.rootId == rootNoteId;
        final hasCorrectParent = note.parentId == rootNoteId;
        final isThreadMember = hasCorrectRoot || hasCorrectParent;

        return isReply && isThreadMember;
      }).toList();

      debugPrint('[NoteRepository] Found ${threadReplies.length} thread replies');

      threadReplies.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      return Result.success(threadReplies);
    } catch (e) {
      debugPrint('[NoteRepository] Error getting thread replies: $e');
      return Result.error('Failed to get thread replies: ${e.toString()}');
    }
  }

  Future<Result<List<NoteModel>>> getDirectReplies(String noteId) async {
    try {
      final directReplies = <NoteModel>[];
      for (final note in _allNotes) {
        if (note.isReply && note.parentId == noteId) {
          directReplies.add(note);
        }
      }

      directReplies.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      return Result.success(directReplies);
    } catch (e) {
      return Result.error('Failed to get direct replies: ${e.toString()}');
    }
  }

  Future<Result<void>> addNote(NoteModel note) async {
    try {
      if (_isNoteFromMutedUser(note)) {
        debugPrint('[NoteRepository] Skipping note from muted user in addNote: ${note.author}');
        return const Result.success(null);
      }

      final existingNote = _notesCache[note.id];
      if (existingNote != null) {
        return const Result.success(null);
      }

      _notesCache[note.id] = note;
      _allNotes.add(note);
      _notesController.add(_allNotes);

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to add note: ${e.toString()}');
    }
  }

  Future<Result<void>> updateNote(NoteModel updatedNote) async {
    try {
      final index = _allNotes.indexWhere((n) => n.id == updatedNote.id);
      if (index != -1) {
        _allNotes[index] = updatedNote;
        _notesController.add(_allNotes);
      }

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to update note: ${e.toString()}');
    }
  }

  Future<Result<void>> removeNote(String noteId) async {
    try {
      _allNotes.removeWhere((n) => n.id == noteId);
      _notesController.add(_allNotes);

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to remove note: ${e.toString()}');
    }
  }

  Future<Result<List<ReactionModel>>> getReactions(String noteId) async {
    try {
      final reactions = _reactions[noteId] ?? [];
      return Result.success(reactions);
    } catch (e) {
      return Result.error('Failed to get reactions: ${e.toString()}');
    }
  }

  Future<Result<void>> addReaction(String noteId, ReactionModel reaction) async {
    try {
      _reactions.putIfAbsent(noteId, () => []);

      ReactionModel? existingReaction;
      for (final r in _reactions[noteId]!) {
        if (r.id == reaction.id) {
          existingReaction = r;
          break;
        }
      }

      if (existingReaction == null) {
        _reactions[noteId]!.add(reaction);

        final note = _notesCache[noteId];
        if (note != null) {
          note.reactionCount = _reactions[noteId]!.length;
        }

        _reactionsController.add(_reactions);
      }

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to add reaction: ${e.toString()}');
    }
  }

  Future<Result<void>> clearCache() async {
    try {
      _allNotes.clear();
      _notesCache.clear();
      _reactions.clear();
      _zaps.clear();

      _notesController.add(_allNotes);
      _reactionsController.add(_reactions);

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to clear cache: ${e.toString()}');
    }
  }

  Future<Result<int>> pruneOldNotes(Duration retentionPeriod) async {
    try {
      final cutoffTime = DateTime.now().subtract(retentionPeriod);
      int removedCount = 0;

      _allNotes.removeWhere((note) {
        if (note.timestamp.isBefore(cutoffTime)) {
          _notesCache.remove(note.id);
          _reactions.remove(note.id);
          _zaps.remove(note.id);
          removedCount++;
          return true;
        }
        return false;
      });

      if (removedCount > 0) {
        debugPrint('[NoteRepository] Pruned $removedCount old notes');
        _notesController.add(List.unmodifiable(_allNotes));
      }

      return Result.success(removedCount);
    } catch (e) {
      debugPrint('[NoteRepository] Error pruning old notes: $e');
      return Result.error('Failed to prune old notes: ${e.toString()}');
    }
  }

  Future<Result<int>> pruneCacheToLimit(int maxNotes) async {
    try {
      if (_allNotes.length <= maxNotes) {
        return Result.success(0);
      }

      _allNotes.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final notesToRemove = _allNotes.sublist(maxNotes);
      final removedCount = notesToRemove.length;

      for (final note in notesToRemove) {
        _notesCache.remove(note.id);
        _reactions.remove(note.id);
        _zaps.remove(note.id);
      }

      _allNotes.removeRange(maxNotes, _allNotes.length);

      debugPrint('[NoteRepository] Pruned $removedCount notes to keep cache under $maxNotes items');
      _notesController.add(List.unmodifiable(_allNotes));

      return Result.success(removedCount);
    } catch (e) {
      debugPrint('[NoteRepository] Error pruning cache to limit: $e');
      return Result.error('Failed to prune cache: ${e.toString()}');
    }
  }

  Stream<List<NoteModel>> get notesStream => _notesController.stream;

  Stream<Map<String, List<ReactionModel>>> get reactionsStream => _reactionsController.stream;

  List<NoteModel> get currentNotes => List.unmodifiable(_allNotes);

  Map<String, List<ReactionModel>> get currentReactions => Map.unmodifiable(_reactions);

  Map<String, List<NoteModel>> buildThreadHierarchy(String rootNoteId) {
    final Map<String, List<NoteModel>> hierarchy = {};
    final threadReplies = <NoteModel>[];
    for (final note in _allNotes) {
      if (note.isReply && (note.rootId == rootNoteId || note.parentId == rootNoteId)) {
        threadReplies.add(note);
      }
    }

    for (final reply in threadReplies) {
      final parentId = reply.parentId ?? rootNoteId;
      hierarchy.putIfAbsent(parentId, () => []);
      hierarchy[parentId]!.add(reply);
    }

    hierarchy.forEach((key, replies) {
      replies.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });

    return hierarchy;
  }

  NoteStats getNoteStats(String noteId) {
    return NoteStats(
      reactionCount: _reactions[noteId]?.length ?? 0,
      replyCount: 0,
      repostCount: 0,
      zapAmount: _zaps[noteId]?.fold<int>(0, (sum, zap) => sum + zap.amount) ?? 0,
    );
  }

  void updateNoteInteractionCounts(String noteId) {
    final note = _allNotes.where((n) => n.id == noteId).firstOrNull;
    if (note != null) {
      final stats = getNoteStats(noteId);
      note.reactionCount = stats.reactionCount;
      note.replyCount = stats.replyCount;
      note.repostCount = stats.repostCount;
      note.zapAmount = stats.zapAmount;
    }
  }

  Future<Result<void>> reactToNote(String noteId, String reaction) async {
    try {
      return await _nostrDataService.reactToNote(
        noteId: noteId,
        reaction: reaction,
      );
    } catch (e) {
      return Result.error('Failed to react to note: $e');
    }
  }

  Future<Result<void>> repostNote(String noteId) async {
    try {
      final note = _allNotes.where((n) => n.id == noteId).firstOrNull;
      if (note == null) {
        return const Result.error('Note not found');
      }

      return await _nostrDataService.repostNote(
        noteId: noteId,
        noteAuthor: note.author,
      );
    } catch (e) {
      return Result.error('Failed to repost note: $e');
    }
  }

  Future<Result<NoteModel>> postNote({
    required String content,
    List<List<String>>? tags,
  }) async {
    try {
      return await _nostrDataService.postNote(
        content: content,
        tags: tags,
      );
    } catch (e) {
      return Result.error('Failed to post note: $e');
    }
  }

  Future<Result<NoteModel>> postReply({
    required String content,
    required String rootId,
    String? replyId,
    required String parentAuthor,
    required List<String> relayUrls,
    List<List<String>>? additionalTags,
  }) async {
    try {
      return await _nostrDataService.postReply(
        content: content,
        rootId: rootId,
        replyId: replyId,
        parentAuthor: parentAuthor,
        relayUrls: relayUrls,
        additionalTags: additionalTags,
      );
    } catch (e) {
      return Result.error('Failed to post reply: $e');
    }
  }

  Future<Result<NoteModel>> postQuote({
    required String content,
    required String quotedEventId,
    String? quotedEventPubkey,
    String? relayUrl,
    List<List<String>>? additionalTags,
  }) async {
    try {
      return await _nostrDataService.postQuote(
        content: content,
        quotedEventId: quotedEventId,
        quotedEventPubkey: quotedEventPubkey,
        relayUrl: relayUrl,
        additionalTags: additionalTags,
      );
    } catch (e) {
      return Result.error('Failed to post quote: $e');
    }
  }

  Future<Result<void>> deleteNote(String noteId) async {
    try {
      final result = await _nostrDataService.deleteNote(noteId: noteId);
      result.fold(
        (_) {
          _allNotes.removeWhere((n) => n.id == noteId);
          _notesCache.remove(noteId);
          _notesController.add(List.unmodifiable(_allNotes));
        },
        (_) {},
      );
      return result;
    } catch (e) {
      return Result.error('Failed to delete note: $e');
    }
  }

  Stream<List<NoteModel>> get realTimeNotesStream => _nostrDataService.notesStream;

  void _insertSorted(NoteModel note) {
    int left = 0;
    int right = _allNotes.length;

    while (left < right) {
      final mid = (left + right) ~/ 2;
      if (_allNotes[mid].timestamp.isAfter(note.timestamp)) {
        left = mid + 1;
      } else {
        right = mid;
      }
    }

    _allNotes.insert(left, note);
  }

  Future<Result<void>> startRealTimeFeed(List<String> authorNpubs) async {
    try {
      if (authorNpubs.isEmpty) {
        debugPrint('[NoteRepository] Cannot start real-time feed: no authors provided');
        return const Result.error('No authors provided for real-time feed');
      }

      debugPrint('[NoteRepository] Starting real-time feed for ${authorNpubs.length} authors');

      final fetchResult = await fetchNotesFromRelays(authorNpubs: authorNpubs);
      if (fetchResult.isError) {
        debugPrint('[NoteRepository] Initial feed fetch failed: ${fetchResult.error}');
        return Result.error(fetchResult.error!);
      }

      debugPrint('[NoteRepository] Setting up stream subscription...');

      _nostrDataService.notesStream.listen((newNotes) {
        if (newNotes.isEmpty) return;

        bool hasChanges = false;
        final newNotesToAdd = <NoteModel>[];
        for (final note in newNotes) {
          if (_isNoteFromMutedUser(note)) {
            debugPrint('[NoteRepository] Skipping note from muted user: ${note.author}');
            continue;
          }

          if (!_notesCache.containsKey(note.id)) {
            _notesCache[note.id] = note;
            newNotesToAdd.add(note);
            hasChanges = true;
          }
        }

        if (!hasChanges) return;

        for (final note in newNotesToAdd) {
          _insertSorted(note);
        }

        final updateTime = DateTime.now();
        _lastNotesUpdate = updateTime;

        Future.delayed(const Duration(milliseconds: 2000), () {
          if (_lastNotesUpdate == updateTime && !_isPaused) {
            _notesController.add(List.unmodifiable(_allNotes));
          }
        });
      });

      return const Result.success(null);
    } catch (e) {
      debugPrint('[NoteRepository] Exception in startRealTimeFeed: $e');
      return Result.error('Failed to start real-time feed: $e');
    }
  }

  void _setupNostrDataServiceForwarding() {
    _deletionSubscription = _nostrDataService.noteDeletedStream.listen((deletedNoteId) {
      if (_isPaused) return;

      _allNotes.removeWhere((n) => n.id == deletedNoteId);
      _notesCache.remove(deletedNoteId);
    });

    _dataServiceSubscription = _nostrDataService.notesStream.listen((updatedNotes) {
      if (_isPaused) {
        debugPrint('[NoteRepository] Skipping update while paused');
        return;
      }

      final updatedNoteIds = updatedNotes.map((n) => n.id).toSet();
      final currentNoteIds = _allNotes.map((n) => n.id).toSet();

      final removedNoteIds = currentNoteIds.difference(updatedNoteIds);
      if (removedNoteIds.isNotEmpty) {
        _allNotes.removeWhere((n) => removedNoteIds.contains(n.id));
        for (final id in removedNoteIds) {
          _notesCache.remove(id);
        }
      }

      bool hasChanges = removedNoteIds.isNotEmpty;
      final List<NoteModel> newNotes = [];

      for (final updatedNote in updatedNotes) {
        if (_isNoteFromMutedUser(updatedNote)) {
          debugPrint('[NoteRepository] Skipping note from muted user: ${updatedNote.author}');
          continue;
        }

        final existingNote = _notesCache[updatedNote.id];
        if (existingNote != null) {
          if (existingNote.reactionCount != updatedNote.reactionCount ||
              existingNote.repostCount != updatedNote.repostCount ||
              existingNote.replyCount != updatedNote.replyCount ||
              existingNote.zapAmount != updatedNote.zapAmount) {
            _notesCache[updatedNote.id] = updatedNote;
            final index = _allNotes.indexWhere((n) => n.id == updatedNote.id);
            if (index != -1) {
              _allNotes[index] = updatedNote;
            }
            hasChanges = true;
          }
        } else {
          _notesCache[updatedNote.id] = updatedNote;
          _allNotes.add(updatedNote);
          newNotes.add(updatedNote);
          hasChanges = true;
        }
      }

      if (newNotes.isNotEmpty) {
        _preloadMentionsForNotes(newNotes);
      }

      if (!hasChanges) return;

      if (removedNoteIds.isNotEmpty) {
        _notesController.add(List.unmodifiable(_allNotes));
      } else {
        final updateTime = DateTime.now();
        _lastNotesUpdate = updateTime;

        Future.delayed(const Duration(milliseconds: 3000), () {
          if (_lastNotesUpdate == updateTime && !_isPaused) {
            _notesController.add(List.unmodifiable(_allNotes));
          }
        });
      }
    });
  }

  bool _isNoteFromMutedUser(NoteModel note) {
    try {
      final currentUserNpub = _nostrDataService.currentUserNpub;
      if (currentUserNpub.isEmpty) {
        debugPrint('[NoteRepository] Current user npub is empty, skipping mute check');
        return false;
      }

      final currentUserHex = _npubToHex(currentUserNpub);
      if (currentUserHex == null) {
        debugPrint('[NoteRepository] Failed to convert current user npub to hex: $currentUserNpub');
        return false;
      }

      final muteCacheService = MuteCacheService.instance;
      final mutedList = muteCacheService.getSync(currentUserHex);
      if (mutedList == null || mutedList.isEmpty) {
        debugPrint('[NoteRepository] No muted users found in cache for user: $currentUserHex');
        return false;
      }

      final mutedSet = mutedList.toSet();
      debugPrint('[NoteRepository] Checking note ${note.id.substring(0, 8)}... against ${mutedSet.length} muted users');

      if (note.isRepost && note.repostedBy != null) {
        final reposterHex = _npubToHex(note.repostedBy!);
        if (reposterHex != null && mutedSet.contains(reposterHex)) {
          debugPrint('[NoteRepository] ✓ Note is repost by muted user: ${note.repostedBy} (hex: $reposterHex)');
          return true;
        } else {
          debugPrint('[NoteRepository] Repost by ${note.repostedBy} (hex: $reposterHex) is NOT muted');
        }
      }

      final noteAuthorHex = _npubToHex(note.author);
      if (noteAuthorHex != null && mutedSet.contains(noteAuthorHex)) {
        debugPrint('[NoteRepository] ✓ Note is from muted user: ${note.author} (hex: $noteAuthorHex)');
        return true;
      } else {
        debugPrint('[NoteRepository] Note author ${note.author} (hex: $noteAuthorHex) is NOT muted');
      }

      return false;
    } catch (e) {
      debugPrint('[NoteRepository] Error checking if note is from muted user: $e');
      return false;
    }
  }

  String? _npubToHex(String npub) {
    try {
      if (npub.startsWith('npub1')) {
        return decodeBasicBech32(npub, 'npub');
      } else if (npub.length == 64) {
        return npub;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  void _preloadMentionsForNotes(List<NoteModel> notes) {
    if (_userRepository == null) return;

    final Set<String> authorIds = {};
    for (final note in notes) {
      authorIds.add(note.author);
      if (note.repostedBy != null) {
        authorIds.add(note.repostedBy!);
      }

      try {
        final parsedContent = note.parsedContentLazy;
        final textParts = (parsedContent['textParts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        for (final part in textParts) {
          if (part['type'] == 'mention') {
            final mentionId = part['id'] as String?;
            if (mentionId != null) {
              final pubkey = _extractPubkeyFromBech32(mentionId);
              if (pubkey != null) {
                authorIds.add(pubkey);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[NoteRepository] Error parsing mentions from note ${note.id}: $e');
      }
    }

    if (authorIds.isEmpty) return;

    _userRepository
        .getUserProfiles(
          authorIds.toList(),
          priority: FetchPriority.high,
        )
        .then((_) {})
        .catchError((e) {
      debugPrint('[NoteRepository] Error preloading mentions: $e');
    });
  }

  String? _extractPubkeyFromBech32(String bech32) {
    try {
      if (bech32.startsWith('npub1')) {
        return decodeBasicBech32(bech32, 'npub');
      } else if (bech32.startsWith('nprofile1')) {
        final result = decodeTlvBech32Full(bech32, 'nprofile');
        return result['type_0_main'];
      }
    } catch (e) {
      debugPrint('[NoteRepository] Bech32 decode error: $e');
    }
    return null;
  }

  Future<void> fetchInteractionsForNote(String noteId, {bool useCount = false}) async {
    try {
      await _nostrDataService.fetchInteractionsForNotes([noteId], forceLoad: false, useCount: useCount);

      if (!useCount) {
        _updateNoteReplyCount(noteId);
      }
    } catch (e) {
      debugPrint('[NoteRepository] Error fetching interactions for note $noteId: $e');
    }
  }

  Future<void> fetchInteractionsForNotes(List<String> noteIds, {bool useCount = false, bool forceLoad = false}) async {
    try {
      if (noteIds.isEmpty) return;

      await _nostrDataService.fetchInteractionsForNotes(noteIds, forceLoad: forceLoad, useCount: useCount);

      if (!useCount) {
        for (final noteId in noteIds) {
          _updateNoteReplyCount(noteId);
        }
      }
    } catch (e) {
      debugPrint('[NoteRepository] Error fetching interactions for notes: $e');
    }
  }

  void _updateNoteReplyCount(String noteId) {
    try {
      final note = _notesCache[noteId];
      if (note != null) {
        final cachedNotes = _nostrDataService.cachedNotes;
        int replyCount = 0;
        for (final reply in cachedNotes) {
          if (reply.isReply && (reply.parentId == noteId || reply.rootId == noteId)) {
            replyCount++;
          }
        }

        if (note.replyCount != replyCount) {
          note.replyCount = replyCount;

          _notesController.add(_allNotes);
        }
      }
    } catch (e) {
      debugPrint('[NoteRepository] Error updating note reply count: $e');
    }
  }

  bool hasUserReacted(String noteId, String userHex) {
    try {
      return _nostrDataService.hasUserReacted(noteId, userHex);
    } catch (e) {
      debugPrint('[NoteRepository] Error checking user reaction: $e');
      return false;
    }
  }

  bool hasUserReposted(String noteId, String userHex) {
    try {
      return _nostrDataService.hasUserReposted(noteId, userHex);
    } catch (e) {
      debugPrint('[NoteRepository] Error checking user repost: $e');
      return false;
    }
  }

  bool hasUserZapped(String noteId, String userHex) {
    try {
      return _nostrDataService.hasUserZapped(noteId, userHex);
    } catch (e) {
      debugPrint('[NoteRepository] Error checking user zap: $e');
      return false;
    }
  }

  void dispose() {
    LifecycleManager().removeOnPauseCallback(_onAppPaused);
    LifecycleManager().removeOnResumeCallback(_onAppResumed);
    _dataServiceSubscription?.cancel();
    _deletionSubscription?.cancel();
    _notesController.close();
    _reactionsController.close();
  }
}

class NoteStats {
  final int reactionCount;
  final int replyCount;
  final int repostCount;
  final int zapAmount;

  const NoteStats({
    required this.reactionCount,
    required this.replyCount,
    required this.repostCount,
    required this.zapAmount,
  });

  @override
  String toString() => 'NoteStats(reactions: $reactionCount, replies: $replyCount, reposts: $repostCount, zaps: $zapAmount)';
}
