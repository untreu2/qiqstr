import 'dart:async';
import 'package:nostr_nip19/nostr_nip19.dart';

import '../../core/base/result.dart';
import '../services/logging_service.dart';
import '../../models/note_model.dart';
import '../../models/reaction_model.dart';
import '../../models/zap_model.dart';
import '../filters/feed_filters.dart';
import '../services/network_service.dart';
import '../services/data_service.dart';
import '../services/mute_cache_service.dart';
import '../services/user_batch_fetcher.dart';
import '../services/follow_cache_service.dart';
import 'user_repository.dart';

class NoteRepository {
  final DataService _nostrDataService;
  final UserRepository? _userRepository;
  final LoggingService _logger;
  
  LoggingService get logger => _logger;
  
  final Map<String, NoteModel> _notesCache = {};
  final Set<String> _noteIds = {};
  final List<NoteModel> _allNotes = [];
  
  static const int _maxCacheSize = 5000;
  static const int _pruneThreshold = 6000;
  static const Duration _updateThrottle = Duration(milliseconds: 500);
  
  Timer? _updateThrottleTimer;
  bool _hasPendingUpdate = false;

  DataService get nostrDataService => _nostrDataService;

  final Map<String, List<ReactionModel>> _reactions = {};
  final Map<String, List<ZapModel>> _zaps = {};

  final StreamController<List<NoteModel>> _notesController = StreamController<List<NoteModel>>.broadcast();

  StreamSubscription<List<NoteModel>>? _dataServiceSubscription;
  StreamSubscription<String>? _deletionSubscription;
  bool _isPaused = false;

  NoteRepository({
    required NetworkService networkService,
    required DataService nostrDataService,
    UserRepository? userRepository,
    LoggingService? logger,
  })  : _nostrDataService = nostrDataService,
        _userRepository = userRepository,
        _logger = logger ?? LoggingService.instance {
    _setupNostrDataServiceForwarding();
  }

  void setPaused(bool paused) {
    _isPaused = paused;
    if (!paused) {
      _throttledUpdate();
    }
  }

  Future<Result<List<NoteModel>>> getFilteredNotes(BaseFeedFilter filter) async {
    try {
      final allCachedNotes = _getAllCachedNotes();
      final filtered = filter.apply(allCachedNotes);

      final seenIds = <String>{};
      final deduplicatedNotes = <NoteModel>[];
      
      for (final note in filtered) {
        if (seenIds.add(note.id)) {
          deduplicatedNotes.add(note);
        }
      }

      return Result.success(deduplicatedNotes);
    } catch (e) {
      _logger.error('Failed to apply filter', 'NoteRepository', e);
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
        final result = await _nostrDataService.fetchHashtagNotes(
          hashtag: hashtag,
          limit: limit,
          until: until,
          since: since,
        );
        return result.isSuccess ? const Result.success(null) : Result.error(result.error!);
      }

      return const Result.success(null);
    } catch (e) {
      _logger.error('Failed to fetch notes', 'NoteRepository', e);
      return Result.error('Failed to fetch notes: ${e.toString()}');
    }
  }

  List<NoteModel> _getAllCachedNotes() {
    if (_allNotes.length >= _pruneThreshold) {
      _pruneCacheIfNeeded();
    }

    final serviceNotes = _nostrDataService.cachedNotes;
    if (serviceNotes.isEmpty) return _allNotes;

    final newNotes = <NoteModel>[];
    for (final note in serviceNotes) {
      if (_isNoteFromMutedUser(note)) {
        continue;
      }

      if (_noteIds.add(note.id)) {
        _notesCache[note.id] = note;
        newNotes.add(note);
      }
    }

    if (newNotes.isNotEmpty) {
      _batchInsertNotes(newNotes);
    }

    return _allNotes;
  }

  void _batchInsertNotes(List<NoteModel> notes) {
    if (notes.isEmpty) return;

    notes.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    int insertIndex = 0;
    for (final note in notes) {
      while (insertIndex < _allNotes.length && 
             _allNotes[insertIndex].timestamp.isAfter(note.timestamp)) {
        insertIndex++;
      }
      _allNotes.insert(insertIndex, note);
    }

    _throttledUpdate();
  }

  void _pruneCacheIfNeeded() {
    if (_allNotes.length <= _maxCacheSize) return;

    _allNotes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    final notesToKeep = _allNotes.take(_maxCacheSize).toList();
    final notesToRemove = _allNotes.skip(_maxCacheSize).toList();
    
    final removedIds = notesToRemove.map((n) => n.id).toSet();
    
    _allNotes.clear();
    _allNotes.addAll(notesToKeep);
    
    for (final noteId in removedIds) {
      _notesCache.remove(noteId);
      _noteIds.remove(noteId);
      _reactions.remove(noteId);
      _zaps.remove(noteId);
    }
  }

  void _throttledUpdate() {
    if (_isPaused) return;
    
    _hasPendingUpdate = true;
    
    _updateThrottleTimer?.cancel();
    _updateThrottleTimer = Timer(_updateThrottle, () {
      if (_hasPendingUpdate && !_isPaused) {
        _notesController.add(List.unmodifiable(_allNotes));
        _hasPendingUpdate = false;
      }
    });
  }

  Future<Result<NoteModel?>> getNoteById(String noteId) async {
    try {
      final localNote = _notesCache[noteId];
      if (localNote != null) {
        return Result.success(localNote);
      }

      final cachedNotes = _nostrDataService.cachedNotes;
      for (final note in cachedNotes) {
        if (note.id == noteId) {
          if (_noteIds.add(note.id)) {
            _notesCache[note.id] = note;
            _insertSorted(note);
          }
          return Result.success(note);
        }
      }

      final success = await _fetchNoteDirectly(noteId);
      if (success) {
        for (final note in _nostrDataService.cachedNotes) {
          if (note.id == noteId) {
            if (_noteIds.add(note.id)) {
              _notesCache[note.id] = note;
              _insertSorted(note);
            }
            return Result.success(note);
          }
        }
      }

      return const Result.success(null);
    } catch (e) {
      _logger.error('Error getting note by ID', 'NoteRepository', e);
      return Result.error('Failed to get note: ${e.toString()}');
    }
  }

  Future<bool> _fetchNoteDirectly(String noteId) async {
    try {
      return await _nostrDataService.fetchSpecificNote(noteId);
    } catch (e) {
      _logger.error('Error in direct note fetch', 'NoteRepository', e);
      return false;
    }
  }

  Future<Result<List<NoteModel>>> getThreadReplies(String rootNoteId, {bool fetchFromRelays = false}) async {
    try {
      if (fetchFromRelays) {
        await _nostrDataService.fetchThreadRepliesForNote(rootNoteId);
        await Future.delayed(const Duration(milliseconds: 300));
      }

      final allNotes = _getAllCachedNotes();
      final threadReplies = <NoteModel>[];

      for (final note in allNotes) {
        if (note.isReply && 
            (note.rootId == rootNoteId || note.parentId == rootNoteId)) {
          threadReplies.add(note);
        }
      }

      threadReplies.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      return Result.success(threadReplies);
    } catch (e) {
      _logger.error('Error getting thread replies', 'NoteRepository', e);
      return Result.error('Failed to get thread replies: ${e.toString()}');
    }
  }


  Future<Result<void>> addNote(NoteModel note) async {
    try {
      if (_isNoteFromMutedUser(note)) {
        return const Result.success(null);
      }

      if (!_noteIds.add(note.id)) {
        return const Result.success(null);
      }

      _notesCache[note.id] = note;
      _insertSorted(note);
      _throttledUpdate();

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to add note: ${e.toString()}');
    }
  }

  Future<Result<void>> updateNote(NoteModel updatedNote) async {
    try {
      if (!_noteIds.contains(updatedNote.id)) {
        return await addNote(updatedNote);
      }

      final index = _allNotes.indexWhere((n) => n.id == updatedNote.id);
      if (index != -1) {
        _allNotes[index] = updatedNote;
        _notesCache[updatedNote.id] = updatedNote;
        _throttledUpdate();
      }

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to update note: ${e.toString()}');
    }
  }

  Future<Result<void>> removeNote(String noteId) async {
    try {
      if (_noteIds.remove(noteId)) {
        _allNotes.removeWhere((n) => n.id == noteId);
        _notesCache.remove(noteId);
        _throttledUpdate();
      }

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to remove note: ${e.toString()}');
    }
  }


  Future<Result<void>> clearCache() async {
    try {
      _allNotes.clear();
      _notesCache.clear();
      _noteIds.clear();
      _reactions.clear();
      _zaps.clear();

      _notesController.add(_allNotes);

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to clear cache: ${e.toString()}');
    }
  }

  Future<Result<int>> pruneOldNotes(Duration retentionPeriod) async {
    try {
      final cutoffTime = DateTime.now().subtract(retentionPeriod);
      int removedCount = 0;

      final notesToKeep = <NoteModel>[];
      for (final note in _allNotes) {
        if (note.timestamp.isBefore(cutoffTime)) {
          _notesCache.remove(note.id);
          _noteIds.remove(note.id);
          _reactions.remove(note.id);
          _zaps.remove(note.id);
          removedCount++;
        } else {
          notesToKeep.add(note);
        }
      }

      if (removedCount > 0) {
        _allNotes.clear();
        _allNotes.addAll(notesToKeep);
        _throttledUpdate();
      }

      return Result.success(removedCount);
    } catch (e) {
      _logger.error('Error pruning old notes', 'NoteRepository', e);
      return Result.error('Failed to prune old notes: ${e.toString()}');
    }
  }

  Future<Result<int>> pruneCacheToLimit(int maxNotes) async {
    try {
      if (_allNotes.length <= maxNotes) {
        return Result.success(0);
      }

      _allNotes.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final notesToKeep = _allNotes.take(maxNotes).toList();
      final notesToRemove = _allNotes.skip(maxNotes).toList();
      final removedCount = notesToRemove.length;

      final removedIds = notesToRemove.map((n) => n.id).toSet();
      for (final noteId in removedIds) {
        _notesCache.remove(noteId);
        _noteIds.remove(noteId);
        _reactions.remove(noteId);
        _zaps.remove(noteId);
      }

      _allNotes.clear();
      _allNotes.addAll(notesToKeep);

      _throttledUpdate();

      return Result.success(removedCount);
    } catch (e) {
      _logger.error('Error pruning cache to limit', 'NoteRepository', e);
      return Result.error('Failed to prune cache: ${e.toString()}');
    }
  }

  Stream<List<NoteModel>> get notesStream => _notesController.stream;


  List<NoteModel> get currentNotes => List.unmodifiable(_allNotes);



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

  Future<Result<void>> deleteRepost(String noteId) async {
    try {
      return await _nostrDataService.deleteRepost(
        noteId: noteId,
      );
    } catch (e) {
      return Result.error('Failed to delete repost: $e');
    }
  }

  Future<Result<void>> repostNote(String noteId) async {
    try {
      final note = _notesCache[noteId];
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
          if (_noteIds.remove(noteId)) {
            _allNotes.removeWhere((n) => n.id == noteId);
            _notesCache.remove(noteId);
            _throttledUpdate();
          }
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
        return const Result.error('No authors provided for real-time feed');
      }

      final fetchResult = await fetchNotesFromRelays(authorNpubs: authorNpubs);
      if (fetchResult.isError) {
        return Result.error(fetchResult.error!);
      }

      _nostrDataService.notesStream.listen((newNotes) {
        if (newNotes.isEmpty || _isPaused) return;

        final newNotesToAdd = <NoteModel>[];
        for (final note in newNotes) {
          if (_isNoteFromMutedUser(note)) {
            continue;
          }

          if (_noteIds.add(note.id)) {
            _notesCache[note.id] = note;
            newNotesToAdd.add(note);
          }
        }

        if (newNotesToAdd.isNotEmpty) {
          _batchInsertNotes(newNotesToAdd);
        }
      });

      return const Result.success(null);
    } catch (e) {
      _logger.error('Exception in startRealTimeFeed', 'NoteRepository', e);
      return Result.error('Failed to start real-time feed: $e');
    }
  }

  void _setupNostrDataServiceForwarding() {
    _deletionSubscription = _nostrDataService.noteDeletedStream.listen((deletedNoteId) {
      if (_isPaused) return;

      if (_noteIds.remove(deletedNoteId)) {
        _allNotes.removeWhere((n) => n.id == deletedNoteId);
        _notesCache.remove(deletedNoteId);
        _throttledUpdate();
      }
    });

    _dataServiceSubscription = _nostrDataService.notesStream.listen((updatedNotes) {
      if (_isPaused) return;

      final updatedNoteIds = updatedNotes.map((n) => n.id).toSet();
      final removedNoteIds = _noteIds.difference(updatedNoteIds);
      
      if (removedNoteIds.isNotEmpty) {
        for (final id in removedNoteIds) {
          _noteIds.remove(id);
          _notesCache.remove(id);
        }
        _allNotes.removeWhere((n) => removedNoteIds.contains(n.id));
      }

      final newNotes = <NoteModel>[];
      bool hasUpdates = removedNoteIds.isNotEmpty;

      for (final updatedNote in updatedNotes) {
        if (_isNoteFromMutedUser(updatedNote)) {
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
            hasUpdates = true;
          }
        } else if (_noteIds.add(updatedNote.id)) {
          _notesCache[updatedNote.id] = updatedNote;
          newNotes.add(updatedNote);
          hasUpdates = true;
        }
      }

      if (newNotes.isNotEmpty) {
        _preloadMentionsForNotes(newNotes);
        _batchInsertNotes(newNotes);
      } else if (hasUpdates) {
        _throttledUpdate();
      }
    });
  }

  bool _isNoteFromMutedUser(NoteModel note) {
    try {
      final currentUserNpub = _nostrDataService.currentUserNpub;
      if (currentUserNpub.isEmpty) {
        return false;
      }

      final currentUserHex = _npubToHex(currentUserNpub);
      if (currentUserHex == null) {
        return false;
      }

      final muteCacheService = MuteCacheService.instance;
      final mutedList = muteCacheService.getSync(currentUserHex);
      if (mutedList == null || mutedList.isEmpty) {
        return false;
      }

      final mutedSet = mutedList.toSet();

      if (note.isRepost && note.repostedBy != null) {
        final reposterHex = _npubToHex(note.repostedBy!);
        if (reposterHex != null && mutedSet.contains(reposterHex)) {
          return true;
        }
      }

      final noteAuthorHex = _npubToHex(note.author);
      if (noteAuthorHex != null && mutedSet.contains(noteAuthorHex)) {
        return true;
      }

      return false;
    } catch (e) {
      _logger.error('Error checking if note is from muted user', 'NoteRepository', e);
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
    if (_userRepository == null || notes.isEmpty) return;

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
        _logger.error('Error parsing mentions from note', 'NoteRepository', e);
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
      _logger.error('Error preloading mentions', 'NoteRepository', e);
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
      _logger.error('Bech32 decode error', 'NoteRepository', e);
    }
    return null;
  }



  bool hasUserReacted(String noteId, String userHex) {
    try {
      return _nostrDataService.hasUserReacted(noteId, userHex);
    } catch (e) {
      _logger.error('Error checking user reaction', 'NoteRepository', e);
      return false;
    }
  }

  bool hasUserReposted(String noteId, String userHex) {
    try {
      return _nostrDataService.hasUserReposted(noteId, userHex);
    } catch (e) {
      _logger.error('Error checking user repost', 'NoteRepository', e);
      return false;
    }
  }

  bool hasUserZapped(String noteId, String userHex) {
    try {
      return _nostrDataService.hasUserZapped(noteId, userHex);
    } catch (e) {
      _logger.error('Error checking user zap', 'NoteRepository', e);
      return false;
    }
  }

  Future<Result<List<NoteModel>>> getHashtagNotes({
    required String hashtag,
    int limit = 20,
    DateTime? until,
    DateTime? since,
  }) async {
    try {
      final result = await _nostrDataService.fetchHashtagNotes(
        hashtag: hashtag,
        limit: limit,
        until: until,
        since: since,
      );

      if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
        _fetchInteractionsForNotes(result.data!);
      }

      return result;
    } catch (e) {
      _logger.error('Exception in getHashtagNotes', 'NoteRepository', e);
      return Result.error('Failed to get hashtag notes: ${e.toString()}');
    }
  }

  Future<Result<List<NoteModel>>> _getFeedNotesForAuthors({
    required BaseFeedFilter filter,
    required List<String> authorNpubs,
    int limit = 50,
    DateTime? until,
    DateTime? since,
    bool isProfileMode = false,
    bool skipCache = false,
  }) async {
    try {
      if (!skipCache) {
        final cachedResult = await getFilteredNotes(filter);
        List<NoteModel>? cachedNotes;
        
        if (cachedResult.isSuccess && cachedResult.data!.isNotEmpty) {
          cachedNotes = cachedResult.data!;
          
          if (until != null) {
            cachedNotes = cachedNotes.where((note) {
              final noteTime = note.isRepost ? (note.repostTimestamp ?? note.timestamp) : note.timestamp;
              return noteTime.isBefore(until);
            }).toList();
          }
        }
        
        if (cachedNotes != null && cachedNotes.isNotEmpty) {
          fetchNotesFromRelays(
            authorNpubs: authorNpubs,
            limit: limit,
            until: until,
            since: since,
            isProfileMode: isProfileMode,
          ).then((_) {}).catchError((e) {
            _logger.error('Error fetching notes in background', 'NoteRepository', e);
          });

          _fetchInteractionsForNotes(cachedNotes);

          return Result.success(cachedNotes);
        }
      }

      await fetchNotesFromRelays(
        authorNpubs: authorNpubs,
        limit: limit,
        until: until,
        since: since,
        isProfileMode: isProfileMode,
      );

      final result = await getFilteredNotes(filter);

      if (result.isSuccess && until != null && result.data!.isNotEmpty) {
        final filteredNotes = result.data!.where((note) {
          final noteTime = note.isRepost ? (note.repostTimestamp ?? note.timestamp) : note.timestamp;
          return noteTime.isBefore(until);
        }).toList();

        _fetchInteractionsForNotes(filteredNotes);

        return Result.success(filteredNotes);
      }

      if (result.isSuccess && result.data!.isNotEmpty) {
        _fetchInteractionsForNotes(result.data!);
      }

      return result;
    } catch (e) {
      _logger.error('Exception in _getFeedNotesForAuthors', 'NoteRepository', e);
      return Result.error('Failed to get feed notes: ${e.toString()}');
    }
  }

  Future<Result<List<NoteModel>>> getFeedNotesFromFollowList({
    required String currentUserNpub,
    int limit = 50,
    DateTime? until,
    DateTime? since,
    bool skipCache = false,
  }) async {
    try {
      final nostrService = _nostrDataService;
      final currentUserHex = nostrService.authService.npubToHex(currentUserNpub) ?? currentUserNpub;
      
      final followCacheService = FollowCacheService.instance;
      final cachedFollowList = followCacheService.getSync(currentUserHex);
      
      Set<String> followedNpubs;
      
      if (cachedFollowList == null || cachedFollowList.isEmpty) {
        await fetchNotesFromRelays(
          authorNpubs: [currentUserNpub],
          limit: limit,
          until: until,
          since: since,
        );
        
        final followingResult = await nostrService.getFollowingList(currentUserNpub);
        
        if (followingResult.isError || followingResult.data == null || followingResult.data!.isEmpty) {
          return Result.success([]);
        }
        
        final followedHexKeys = followingResult.data!;
        followedNpubs = followedHexKeys
            .map((hex) => nostrService.authService.hexToNpub(hex))
            .where((npub) => npub != null)
            .cast<String>()
            .toSet();
      } else {
        fetchNotesFromRelays(
          authorNpubs: [currentUserNpub],
          limit: limit,
          until: until,
          since: since,
        ).then((_) {}).catchError((e) {
          _logger.error('Error fetching notes in background', 'NoteRepository', e);
        });
        
        final followedHexKeys = cachedFollowList;
        followedNpubs = followedHexKeys
            .map((hex) => nostrService.authService.hexToNpub(hex))
            .where((npub) => npub != null)
            .cast<String>()
            .toSet();
      }
      
      final filter = HomeFeedFilter(
        currentUserNpub: currentUserNpub,
        followedUsers: followedNpubs,
        showReplies: false,
      );
      
      return await _getFeedNotesForAuthors(
        filter: filter,
        authorNpubs: followedNpubs.toList(),
        limit: limit,
        until: until,
        since: since,
        skipCache: skipCache,
      );
    } catch (e) {
      _logger.error('Exception in getFeedNotesFromFollowList', 'NoteRepository', e);
      return Result.error('Failed to get feed notes: ${e.toString()}');
    }
  }
  
  Future<Result<List<NoteModel>>> getProfileNotes({
    required String authorNpub,
    int limit = 50,
    DateTime? until,
    DateTime? since,
    bool skipCache = false,
  }) async {
    final filter = ProfileFeedFilter(
      targetUserNpub: authorNpub,
      currentUserNpub: authorNpub,
      showReplies: false,
    );
    
    return await _getFeedNotesForAuthors(
      filter: filter,
      authorNpubs: [authorNpub],
      limit: limit,
      until: until,
      since: since,
      isProfileMode: true,
      skipCache: skipCache,
    );
  }

  void _fetchInteractionsForNotes(List<NoteModel> notes) {
    try {
      final noteIds = notes.map((note) {
        if (note.isRepost && note.rootId != null && note.rootId!.isNotEmpty) {
          return note.rootId!;
        }
        return note.id;
      }).toSet().toList();

      if (noteIds.isEmpty) return;

      _nostrDataService.fetchInteractionsForNotesBatchWithEOSE(noteIds);
    } catch (e) {
      _logger.error('Error fetching interactions for notes', 'NoteRepository', e);
    }
  }

  void dispose() {
    _updateThrottleTimer?.cancel();
    _dataServiceSubscription?.cancel();
    _deletionSubscription?.cancel();
    _notesController.close();
  }
}
