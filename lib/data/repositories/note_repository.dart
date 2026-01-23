import 'dart:async';
import 'package:nostr_nip19/nostr_nip19.dart';

import '../../core/base/result.dart';
import '../services/logging_service.dart';
import '../filters/feed_filters.dart';
import '../services/network_service.dart';
import '../services/data_service.dart';
import '../services/mute_cache_service.dart';
import '../services/user_batch_fetcher.dart';
import '../services/follow_cache_service.dart';
import '../services/event_cache_service.dart';
import '../services/event_converter_service.dart';
import '../../models/event_model.dart';
import 'user_repository.dart';

class NoteRepository {
  final DataService _nostrDataService;
  final UserRepository? _userRepository;
  final LoggingService _logger;
  final EventCacheService _eventCacheService = EventCacheService.instance;
  final EventConverterService _eventConverter = EventConverterService.instance;

  LoggingService get logger => _logger;

  final Map<String, Map<String, dynamic>> _notesCache = {};
  final Set<String> _noteIds = {};
  final List<Map<String, dynamic>> _allNotes = [];

  static const int _maxCacheSize = 5000;
  static const int _pruneThreshold = 6000;
  static const Duration _updateThrottle = Duration(milliseconds: 500);

  Timer? _updateThrottleTimer;
  bool _hasPendingUpdate = false;

  DataService get nostrDataService => _nostrDataService;

  final Map<String, List<Map<String, dynamic>>> _reactions = {};
  final Map<String, List<Map<String, dynamic>>> _zaps = {};

  final StreamController<List<Map<String, dynamic>>> _notesController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  StreamSubscription<List<Map<String, dynamic>>>? _dataServiceSubscription;
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

  Future<Result<List<Map<String, dynamic>>>> getFilteredNotes(
      BaseFeedFilter filter) async {
    try {
      final cachedNotes = _nostrDataService.cachedNotes;
      if (cachedNotes.isEmpty) {
        return Result.success([]);
      }

      final authService = _nostrDataService.authService;
      final eventMaps = <Map<String, dynamic>>[];
      final noteMap = <String, Map<String, dynamic>>{};

      for (final note in cachedNotes) {
        final noteId = note['id'] as String? ?? '';
        if (noteId.isEmpty) continue;

        final isRepost = note['isRepost'] as bool? ?? false;
        final timestamp = note['timestamp'] as DateTime?;
        final createdAt =
            timestamp != null ? timestamp.millisecondsSinceEpoch ~/ 1000 : 0;

        final author = note['author'] as String? ?? '';
        final pubkey = authService.npubToHex(author) ?? author;

        final repostedBy = note['repostedBy'] as String?;
        final repostedByPubkey = repostedBy != null
            ? (authService.npubToHex(repostedBy) ?? repostedBy)
            : null;

        final isReply = note['isReply'] as bool? ?? false;
        final rootId = note['rootId'] as String?;
        final parentId = note['parentId'] as String?;
        final hasReplyTags = rootId != null || parentId != null;

        final eventMap = <String, dynamic>{
          'id': noteId,
          'pubkey': isRepost ? (repostedByPubkey ?? pubkey) : pubkey,
          'author': isRepost ? (repostedBy ?? author) : author,
          'kind': isRepost ? 6 : 1,
          'created_at': createdAt,
          'content': note['content'] as String? ?? '',
          'tags': _convertNoteTagsToEventTags(note),
          'isReply': isReply || hasReplyTags,
        };

        eventMaps.add(eventMap);
        noteMap[noteId] = note;
      }

      final filtered = filter.apply(eventMaps);

      final seenIds = <String>{};
      final processedNotes = <Map<String, dynamic>>[];

      for (final event in filtered) {
        final eventId = event['id'] as String? ?? '';
        if (eventId.isEmpty || !seenIds.add(eventId)) continue;

        final cachedNote = noteMap[eventId];
        if (cachedNote != null) {
          processedNotes.add(cachedNote);
        }
      }

      return Result.success(processedNotes);
    } catch (e) {
      _logger.error('Failed to apply filter', 'NoteRepository', e);
      return Result.error('Failed to apply filter: ${e.toString()}');
    }
  }

  List<dynamic> _convertNoteTagsToEventTags(Map<String, dynamic> note) {
    final tags = <List<String>>[];

    final eTags = note['eTags'] as List<dynamic>? ?? [];
    final pTags = note['pTags'] as List<dynamic>? ?? [];
    final tTags = note['tTags'] as List<dynamic>? ?? [];
    final rootId = note['rootId'] as String?;
    final parentId = note['parentId'] as String?;

    if (rootId != null && rootId.isNotEmpty) {
      tags.add(['e', rootId, '', 'root']);
    }

    if (parentId != null && parentId.isNotEmpty && parentId != rootId) {
      tags.add(['e', parentId, '', 'reply']);
    }

    for (final eTag in eTags) {
      if (eTag is String && eTag.isNotEmpty) {
        if (eTag != rootId && eTag != parentId) {
          tags.add(['e', eTag]);
        }
      }
    }

    for (final pTag in pTags) {
      if (pTag is String && pTag.isNotEmpty) {
        tags.add(['p', pTag]);
      }
    }

    for (final tTag in tTags) {
      if (tTag is String && tTag.isNotEmpty) {
        tags.add(['t', tTag]);
      }
    }

    return tags;
  }

  Future<Result<void>> fetchNotesFromRelays({
    List<String>? authorNpubs,
    String? hashtag,
    int limit = 50,
    DateTime? until,
    DateTime? since,
    bool isProfileMode = false,
    bool checkCacheFirst = true,
  }) async {
    try {
      if (checkCacheFirst) {
        List<EventModel> cachedEvents = [];

        if (authorNpubs != null && authorNpubs.isNotEmpty) {
          final events = await _getCachedEventsForAuthors(authorNpubs,
              limit: limit, until: until, since: since);
          if (events.isNotEmpty) {
            cachedEvents = events;
          }
        }

        if (hashtag != null && hashtag.isNotEmpty && cachedEvents.isEmpty) {
          final events = await _getCachedEventsForHashtag(hashtag,
              limit: limit, until: until, since: since);
          if (events.isNotEmpty) {
            cachedEvents = events;
          }
        }

        if (cachedEvents.isNotEmpty) {
          final eventDataList =
              _eventConverter.modelsToEventDataList(cachedEvents);
          for (final eventData in eventDataList) {
            try {
              await _nostrDataService.processEventFromCache(eventData);
            } catch (e) {
              _logger.error(
                  'Error processing cached event', 'NoteRepository', e);
            }
          }

          await _ensureUserProfilesFromCache(cachedEvents);
        }
      }

      if (authorNpubs != null && authorNpubs.isNotEmpty) {
        final result = await _nostrDataService.fetchFeedNotes(
          authorNpubs: authorNpubs,
          limit: limit,
          until: until,
          since: since,
          isProfileMode: isProfileMode,
        );
        return result.isSuccess
            ? const Result.success(null)
            : Result.error(result.error!);
      }

      if (hashtag != null && hashtag.isNotEmpty) {
        final result = await _nostrDataService.fetchHashtagNotes(
          hashtag: hashtag,
          limit: limit,
          until: until,
          since: since,
        );
        return result.isSuccess
            ? const Result.success(null)
            : Result.error(result.error!);
      }

      return const Result.success(null);
    } catch (e) {
      _logger.error('Failed to fetch notes', 'NoteRepository', e);
      return Result.error('Failed to fetch notes: ${e.toString()}');
    }
  }

  Future<List<EventModel>> _getCachedEventsForAuthors(
    List<String> authorNpubs, {
    int limit = 50,
    DateTime? until,
    DateTime? since,
  }) async {
    try {
      final allEvents = <EventModel>[];
      final authService = _nostrDataService.authService;

      for (final npub in authorNpubs) {
        final pubkey = authService.npubToHex(npub) ?? npub;
        final events = await _eventCacheService.getEventsByAuthor(
          pubkey,
          kind: 1,
          since: since,
          until: until,
          limit: limit,
        );
        allEvents.addAll(events);
      }

      allEvents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return allEvents.take(limit).toList();
    } catch (e) {
      _logger.error(
          'Error getting cached events for authors', 'NoteRepository', e);
      return [];
    }
  }

  Future<List<EventModel>> _getCachedEventsForHashtag(
    String hashtag, {
    int limit = 50,
    DateTime? until,
    DateTime? since,
  }) async {
    try {
      final events = await _eventCacheService.getEventsByTag(
        't',
        hashtag.toLowerCase(),
        kind: 1,
        since: since,
        until: until,
        limit: limit,
      );
      return events;
    } catch (e) {
      _logger.error(
          'Error getting cached events for hashtag', 'NoteRepository', e);
      return [];
    }
  }

  Future<void> _ensureUserProfilesFromCache(List<EventModel> events) async {
    if (_userRepository == null) return;

    try {
      final uniquePubkeys = <String>{};
      for (final event in events) {
        if (event.pubkey.isNotEmpty) {
          uniquePubkeys.add(event.pubkey);
        }
      }

      if (uniquePubkeys.isEmpty) return;

      final authService = _nostrDataService.authService;
      final profileEvents = await _eventCacheService
          .getProfileEventsByPubkeys(uniquePubkeys.toList());

      for (final profileEvent in profileEvents) {
        try {
          final eventData = _eventConverter.modelToEventData(profileEvent);
          await _nostrDataService.processEventFromCache(eventData);
        } catch (e) {
          _logger.error(
              'Error processing cached profile event', 'NoteRepository', e);
        }
      }

      final processedPubkeys = profileEvents.map((e) => e.pubkey).toSet();
      final missingPubkeys =
          uniquePubkeys.where((p) => !processedPubkeys.contains(p)).toList();

      if (missingPubkeys.isNotEmpty) {
        final missingNpubs = <String>[];
        for (final pubkey in missingPubkeys) {
          final npub = authService.hexToNpub(pubkey) ?? pubkey;
          final cachedUser = await _userRepository.getCachedUser(npub);
          if (cachedUser == null) {
            missingNpubs.add(npub);
          }
        }

        if (missingNpubs.isNotEmpty) {
          await _userRepository.getUserProfiles(missingNpubs,
              priority: FetchPriority.normal);
        }
      }
    } catch (e) {
      _logger.error(
          'Error ensuring user profiles from cache', 'NoteRepository', e);
    }
  }

  List<Map<String, dynamic>> _getAllCachedNotes() {
    if (_allNotes.length >= _pruneThreshold) {
      _pruneCacheIfNeeded();
    }

    final serviceNotes = _nostrDataService.cachedNotes;
    if (serviceNotes.isEmpty) return _allNotes;

    final newNotes = <Map<String, dynamic>>[];
    for (final note in serviceNotes) {
      final noteMap = _noteToMap(note);
      if (noteMap == null || _isNoteFromMutedUser(noteMap)) {
        continue;
      }

      final noteId = noteMap['id'] as String? ?? '';
      if (noteId.isNotEmpty && _noteIds.add(noteId)) {
        _notesCache[noteId] = noteMap;
        newNotes.add(noteMap);
      }
    }

    if (newNotes.isNotEmpty) {
      _batchInsertNotes(newNotes);
    }

    return _allNotes;
  }

  Map<String, dynamic>? _noteToMap(dynamic note) {
    if (note == null) return null;
    if (note is Map<String, dynamic>) return note;

    try {
      return {
        'id': (note as dynamic).id as String? ?? '',
        'pubkey': (note as dynamic).author as String? ?? '',
        'kind': (note as dynamic).isRepost == true ? 6 : 1,
        'created_at': () {
          final timestamp = (note as dynamic).timestamp;
          if (timestamp is DateTime) {
            return timestamp.millisecondsSinceEpoch ~/ 1000;
          }
          return 0;
        }(),
        'content': (note as dynamic).content as String? ?? '',
        'tags': [],
        'sig': '',
      };
    } catch (e) {
      return null;
    }
  }

  void _batchInsertNotes(List<Map<String, dynamic>> notes) {
    if (notes.isEmpty) return;

    notes.sort((a, b) {
      final aTime = _getTimestamp(a);
      final bTime = _getTimestamp(b);
      return bTime.compareTo(aTime);
    });

    int insertIndex = 0;
    for (final note in notes) {
      final noteTime = _getTimestamp(note);
      while (insertIndex < _allNotes.length &&
          _getTimestamp(_allNotes[insertIndex]).isAfter(noteTime)) {
        insertIndex++;
      }
      _allNotes.insert(insertIndex, note);
    }

    _throttledUpdate();
  }

  DateTime _getTimestamp(Map<String, dynamic> event) {
    final timestamp = event['timestamp'];
    if (timestamp is DateTime) {
      return timestamp;
    }

    final createdAt = event['created_at'];
    if (createdAt != null) {
      if (createdAt is int) {
        return DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
      }
      if (createdAt is DateTime) {
        return createdAt;
      }
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _pruneCacheIfNeeded() {
    if (_allNotes.length <= _maxCacheSize) return;

    _allNotes.sort((a, b) {
      final aTime = _getTimestamp(a);
      final bTime = _getTimestamp(b);
      return bTime.compareTo(aTime);
    });

    final notesToKeep = _allNotes.take(_maxCacheSize).toList();
    final notesToRemove = _allNotes.skip(_maxCacheSize).toList();

    final removedIds = notesToRemove
        .map((n) => n['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

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

  Future<Result<Map<String, dynamic>?>> getNoteById(String noteId) async {
    try {
      final localNote = _notesCache[noteId];
      if (localNote != null) {
        return Result.success(localNote);
      }

      final cachedNotes = _nostrDataService.cachedNotes;
      for (final note in cachedNotes) {
        final noteMap = _noteToMap(note);
        if (noteMap != null) {
          final noteIdFromMap = noteMap['id'] as String? ?? '';
          if (noteIdFromMap == noteId) {
            if (_noteIds.add(noteIdFromMap)) {
              _notesCache[noteIdFromMap] = noteMap;
              _insertSorted(noteMap);
            }
            return Result.success(noteMap);
          }
        }
      }

      final success = await _fetchNoteDirectly(noteId);
      if (success) {
        for (final note in _nostrDataService.cachedNotes) {
          final noteMap = _noteToMap(note);
          if (noteMap != null) {
            final noteIdFromMap = noteMap['id'] as String? ?? '';
            if (noteIdFromMap == noteId) {
              if (_noteIds.add(noteIdFromMap)) {
                _notesCache[noteIdFromMap] = noteMap;
                _insertSorted(noteMap);
              }
              return Result.success(noteMap);
            }
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

  Future<Result<List<Map<String, dynamic>>>> getThreadReplies(String rootNoteId,
      {bool fetchFromRelays = false}) async {
    try {
      if (fetchFromRelays) {
        await _nostrDataService.fetchThreadRepliesForNote(rootNoteId);
        await Future.delayed(const Duration(milliseconds: 300));
      }

      final allNotes = _getAllCachedNotes();
      final threadReplies = <Map<String, dynamic>>[];

      for (final note in allNotes) {
        final isReply = note['isReply'] as bool? ?? false;
        if (!isReply) continue;

        final rootId = note['rootId'] as String?;
        final parentId = note['parentId'] as String?;

        if (rootId == rootNoteId || parentId == rootNoteId) {
          threadReplies.add(note);
        }
      }

      threadReplies.sort((a, b) {
        final aTime = _getTimestamp(a);
        final bTime = _getTimestamp(b);
        return aTime.compareTo(bTime);
      });

      return Result.success(threadReplies);
    } catch (e) {
      _logger.error('Error getting thread replies', 'NoteRepository', e);
      return Result.error('Failed to get thread replies: ${e.toString()}');
    }
  }

  String? _getRootId(Map<String, dynamic> event) {
    final rootId = event['rootId'] as String?;
    if (rootId != null && rootId.isNotEmpty) {
      return rootId;
    }

    final tags = event['tags'] as List<dynamic>? ?? [];
    for (final tag in tags) {
      if (tag is List &&
          tag.length > 1 &&
          tag[0] == 'e' &&
          tag.length > 3 &&
          tag[3] == 'root') {
        return tag[1] as String?;
      }
    }
    return null;
  }

  Future<Result<void>> addNote(Map<String, dynamic> note) async {
    try {
      if (_isNoteFromMutedUser(note)) {
        return const Result.success(null);
      }

      final noteId = note['id'] as String? ?? '';
      if (noteId.isEmpty || !_noteIds.add(noteId)) {
        return const Result.success(null);
      }

      _notesCache[noteId] = note;
      _insertSorted(note);
      _throttledUpdate();

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to add note: ${e.toString()}');
    }
  }

  Future<Result<void>> updateNote(Map<String, dynamic> updatedNote) async {
    try {
      final noteId = updatedNote['id'] as String? ?? '';
      if (noteId.isEmpty || !_noteIds.contains(noteId)) {
        return await addNote(updatedNote);
      }

      final index =
          _allNotes.indexWhere((n) => (n['id'] as String? ?? '') == noteId);
      if (index != -1) {
        _allNotes[index] = updatedNote;
        _notesCache[noteId] = updatedNote;
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
        _allNotes.removeWhere((n) => (n['id'] as String? ?? '') == noteId);
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

      final notesToKeep = <Map<String, dynamic>>[];
      for (final note in _allNotes) {
        final noteTime = _getTimestamp(note);
        if (noteTime.isBefore(cutoffTime)) {
          final noteId = note['id'] as String? ?? '';
          _notesCache.remove(noteId);
          _noteIds.remove(noteId);
          _reactions.remove(noteId);
          _zaps.remove(noteId);
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

      _allNotes.sort((a, b) {
        final aTime = _getTimestamp(a);
        final bTime = _getTimestamp(b);
        return bTime.compareTo(aTime);
      });

      final notesToKeep = _allNotes.take(maxNotes).toList();
      final notesToRemove = _allNotes.skip(maxNotes).toList();
      final removedCount = notesToRemove.length;

      final removedIds = notesToRemove
          .map((n) => n['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
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

  Stream<List<Map<String, dynamic>>> get notesStream => _notesController.stream;

  List<Map<String, dynamic>> get currentNotes => List.unmodifiable(_allNotes);

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

      final noteAuthor = note['pubkey'] as String? ?? '';
      return await _nostrDataService.repostNote(
        noteId: noteId,
        noteAuthor: noteAuthor,
      );
    } catch (e) {
      return Result.error('Failed to repost note: $e');
    }
  }

  Future<Result<Map<String, dynamic>>> postNote({
    required String content,
    List<List<String>>? tags,
  }) async {
    try {
      final result = await _nostrDataService.postNote(
        content: content,
        tags: tags,
      );
      return result.fold(
        (note) => Result.success(_noteToMap(note) ?? {}),
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Failed to post note: $e');
    }
  }

  Future<Result<Map<String, dynamic>>> postReply({
    required String content,
    required String rootId,
    String? replyId,
    required String parentAuthor,
    required List<String> relayUrls,
    List<List<String>>? additionalTags,
  }) async {
    try {
      final result = await _nostrDataService.postReply(
        content: content,
        rootId: rootId,
        replyId: replyId,
        parentAuthor: parentAuthor,
        relayUrls: relayUrls,
        additionalTags: additionalTags,
      );
      return result.fold(
        (note) => Result.success(_noteToMap(note) ?? {}),
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Failed to post reply: $e');
    }
  }

  Future<Result<Map<String, dynamic>>> postQuote({
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
            _allNotes.removeWhere((n) => (n['id'] as String? ?? '') == noteId);
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

  Stream<List<Map<String, dynamic>>> get realTimeNotesStream {
    return _notesController.stream;
  }

  void _insertSorted(Map<String, dynamic> note) {
    int left = 0;
    int right = _allNotes.length;
    final noteTime = _getTimestamp(note);

    while (left < right) {
      final mid = (left + right) ~/ 2;
      if (_getTimestamp(_allNotes[mid]).isAfter(noteTime)) {
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

        final newNotesToAdd = <Map<String, dynamic>>[];
        for (final note in newNotes) {
          final noteMap = _noteToMap(note);
          if (noteMap == null || _isNoteFromMutedUser(noteMap)) {
            continue;
          }

          final noteId = noteMap['id'] as String? ?? '';
          if (noteId.isNotEmpty && _noteIds.add(noteId)) {
            _notesCache[noteId] = noteMap;
            newNotesToAdd.add(noteMap);
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
    _deletionSubscription =
        _nostrDataService.noteDeletedStream.listen((deletedNoteId) {
      if (_isPaused) return;

      if (_noteIds.remove(deletedNoteId)) {
        _allNotes
            .removeWhere((n) => (n['id'] as String? ?? '') == deletedNoteId);
        _notesCache.remove(deletedNoteId);
        _throttledUpdate();
      }
    });

    _dataServiceSubscription =
        _nostrDataService.notesStream.listen((updatedNotes) {
      if (_isPaused) return;

      final updatedNoteIds = <String>{};
      final updatedNoteMaps = <Map<String, dynamic>>[];
      for (final note in updatedNotes) {
        final noteMap = _noteToMap(note);
        if (noteMap != null) {
          final noteId = noteMap['id'] as String? ?? '';
          if (noteId.isNotEmpty) {
            updatedNoteIds.add(noteId);
            updatedNoteMaps.add(noteMap);
          }
        }
      }

      final removedNoteIds = _noteIds.difference(updatedNoteIds);

      if (removedNoteIds.isNotEmpty) {
        for (final id in removedNoteIds) {
          _noteIds.remove(id);
          _notesCache.remove(id);
        }
        _allNotes.removeWhere(
            (n) => removedNoteIds.contains(n['id'] as String? ?? ''));
      }

      final newNotes = <Map<String, dynamic>>[];
      bool hasUpdates = removedNoteIds.isNotEmpty;

      for (final updatedNote in updatedNoteMaps) {
        if (_isNoteFromMutedUser(updatedNote)) {
          continue;
        }

        final noteId = updatedNote['id'] as String? ?? '';
        if (noteId.isEmpty) continue;

        final existingNote = _notesCache[noteId];
        if (existingNote != null) {
          final existingReactionCount =
              existingNote['reactionCount'] as int? ?? 0;
          final existingRepostCount = existingNote['repostCount'] as int? ?? 0;
          final existingReplyCount = existingNote['replyCount'] as int? ?? 0;
          final existingZapAmount = existingNote['zapAmount'] as int? ?? 0;

          final updatedReactionCount =
              updatedNote['reactionCount'] as int? ?? 0;
          final updatedRepostCount = updatedNote['repostCount'] as int? ?? 0;
          final updatedReplyCount = updatedNote['replyCount'] as int? ?? 0;
          final updatedZapAmount = updatedNote['zapAmount'] as int? ?? 0;

          if (existingReactionCount != updatedReactionCount ||
              existingRepostCount != updatedRepostCount ||
              existingReplyCount != updatedReplyCount ||
              existingZapAmount != updatedZapAmount) {
            _notesCache[noteId] = updatedNote;
            final index = _allNotes
                .indexWhere((n) => (n['id'] as String? ?? '') == noteId);
            if (index != -1) {
              _allNotes[index] = updatedNote;
            }
            hasUpdates = true;
          }
        } else if (_noteIds.add(noteId)) {
          _notesCache[noteId] = updatedNote;
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

  bool _isNoteFromMutedUser(Map<String, dynamic> note) {
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

      final kind = note['kind'] as int? ?? 0;
      final isRepost = kind == 6;
      if (isRepost) {
        final reposterPubkey = note['pubkey'] as String? ?? '';
        if (reposterPubkey.isNotEmpty) {
          final reposterHex = _npubToHex(reposterPubkey);
          if (reposterHex != null && mutedSet.contains(reposterHex)) {
            return true;
          }
        }
      }

      final noteAuthorPubkey = note['pubkey'] as String? ?? '';
      if (noteAuthorPubkey.isNotEmpty) {
        final noteAuthorHex = _npubToHex(noteAuthorPubkey);
        if (noteAuthorHex != null && mutedSet.contains(noteAuthorHex)) {
          return true;
        }
      }

      return false;
    } catch (e) {
      _logger.error(
          'Error checking if note is from muted user', 'NoteRepository', e);
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

  void _preloadMentionsForNotes(List<Map<String, dynamic>> notes) {
    if (_userRepository == null || notes.isEmpty) return;

    final Set<String> authorIds = {};
    for (final note in notes) {
      final pubkey = note['pubkey'] as String? ?? '';
      if (pubkey.isNotEmpty) {
        authorIds.add(pubkey);
      }

      final kind = note['kind'] as int? ?? 0;
      if (kind == 6) {
        final reposterPubkey = note['pubkey'] as String? ?? '';
        if (reposterPubkey.isNotEmpty) {
          authorIds.add(reposterPubkey);
        }
      }

      try {
        final tags = note['tags'] as List<dynamic>? ?? [];
        for (final tag in tags) {
          if (tag is List &&
              tag.isNotEmpty &&
              tag[0] == 'p' &&
              tag.length > 1) {
            final mentionPubkey = tag[1] as String? ?? '';
            if (mentionPubkey.isNotEmpty) {
              authorIds.add(mentionPubkey);
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

  int getReactionCount(String noteId) {
    try {
      return _nostrDataService.getReactionsForNote(noteId).length;
    } catch (e) {
      _logger.error('Error getting reaction count', 'NoteRepository', e);
      return 0;
    }
  }

  int getRepostCount(String noteId) {
    try {
      return _nostrDataService.getRepostsForNote(noteId).length;
    } catch (e) {
      _logger.error('Error getting repost count', 'NoteRepository', e);
      return 0;
    }
  }

  int getReplyCount(String noteId) {
    try {
      final cachedNotes = _nostrDataService.cachedNotes;
      return cachedNotes.where((note) {
        final isReply = note['isReply'] as bool? ?? false;
        final parentId = note['parentId'] as String?;
        final rootId = note['rootId'] as String?;
        return isReply && (parentId == noteId || rootId == noteId);
      }).length;
    } catch (e) {
      _logger.error('Error getting reply count', 'NoteRepository', e);
      return 0;
    }
  }

  int getZapAmount(String noteId) {
    try {
      final zaps = _nostrDataService.getZapsForNote(noteId);
      return zaps.fold<int>(0, (sum, zap) {
        final amount = zap['amount'] as int? ?? 0;
        return sum + amount;
      });
    } catch (e) {
      _logger.error('Error getting zap amount', 'NoteRepository', e);
      return 0;
    }
  }

  Future<Result<List<Map<String, dynamic>>>> getHashtagNotes({
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
        final noteMaps = result.data!
            .map((note) => _noteToMap(note))
            .whereType<Map<String, dynamic>>()
            .toList();
        _fetchInteractionsForNotes(noteMaps);
        return Result.success(noteMaps);
      }

      return Result.success([]);
    } catch (e) {
      _logger.error('Exception in getHashtagNotes', 'NoteRepository', e);
      return Result.error('Failed to get hashtag notes: ${e.toString()}');
    }
  }

  Future<Result<List<Map<String, dynamic>>>> getArticles({
    List<String>? authorHexKeys,
    int limit = 50,
    DateTime? until,
    DateTime? since,
    bool cacheOnly = false,
  }) async {
    try {
      final result = await _nostrDataService.fetchLongFormContent(
        authorHexKeys: authorHexKeys,
        limit: limit,
        until: until,
        since: since,
        cacheOnly: cacheOnly,
      );

      if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
        return Result.success(result.data!);
      }

      return Result.success([]);
    } catch (e) {
      _logger.error('Exception in getArticles', 'NoteRepository', e);
      return Result.error('Failed to get articles: ${e.toString()}');
    }
  }

  Future<Result<List<Map<String, dynamic>>>> getArticlesFromFollowList({
    required String currentUserNpub,
    int limit = 50,
    DateTime? until,
    DateTime? since,
    bool cacheOnly = false,
  }) async {
    try {
      final nostrService = _nostrDataService;
      final currentUserHex =
          nostrService.authService.npubToHex(currentUserNpub) ?? currentUserNpub;

      final followCacheService = FollowCacheService.instance;
      final cachedFollowList = followCacheService.getSync(currentUserHex);

      List<String> followedHexKeys = [];

      if (cachedFollowList == null || cachedFollowList.isEmpty) {
        if (!cacheOnly) {
          final followingResult =
              await nostrService.getFollowingList(currentUserNpub);

          if (followingResult.isSuccess &&
              followingResult.data != null &&
              followingResult.data!.isNotEmpty) {
            followedHexKeys = followingResult.data!;
          }
        }
      } else {
        followedHexKeys = cachedFollowList.toList();
      }

      if (followedHexKeys.isNotEmpty) {
        followedHexKeys.add(currentUserHex);
      }

      final result = await _nostrDataService.fetchLongFormContent(
        authorHexKeys: followedHexKeys.isNotEmpty ? followedHexKeys : null,
        limit: limit,
        until: until,
        since: since,
        cacheOnly: cacheOnly,
      );

      if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
        return Result.success(result.data!);
      }

      return Result.success([]);
    } catch (e) {
      _logger.error('Exception in getArticlesFromFollowList', 'NoteRepository', e);
      return Result.error('Failed to get articles: ${e.toString()}');
    }
  }

  Future<Result<List<Map<String, dynamic>>>> _getFeedNotesForAuthors({
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
        List<Map<String, dynamic>>? cachedNotes;

        if (cachedResult.isSuccess && cachedResult.data!.isNotEmpty) {
          cachedNotes = cachedResult.data!;

          if (until != null) {
            cachedNotes = cachedNotes.where((note) {
              final timestamp = note['timestamp'] as DateTime?;
              if (timestamp != null) {
                return timestamp.isBefore(until);
              }
              final createdAt = note['created_at'] as int? ?? 0;
              final noteTime =
                  DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
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
            _logger.error(
                'Error fetching notes in background', 'NoteRepository', e);
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
          final timestamp = note['timestamp'] as DateTime?;
          if (timestamp != null) {
            return timestamp.isBefore(until);
          }
          final createdAt = note['created_at'] as int? ?? 0;
          final noteTime =
              DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
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
      _logger.error(
          'Exception in _getFeedNotesForAuthors', 'NoteRepository', e);
      return Result.error('Failed to get feed notes: ${e.toString()}');
    }
  }

  Future<Result<List<Map<String, dynamic>>>> getFeedNotesFromFollowList({
    required String currentUserNpub,
    int limit = 50,
    DateTime? until,
    DateTime? since,
    bool skipCache = false,
  }) async {
    try {
      final nostrService = _nostrDataService;
      final currentUserHex =
          nostrService.authService.npubToHex(currentUserNpub) ??
              currentUserNpub;

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

        final followingResult =
            await nostrService.getFollowingList(currentUserNpub);

        if (followingResult.isError ||
            followingResult.data == null ||
            followingResult.data!.isEmpty) {
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
          _logger.error(
              'Error fetching notes in background', 'NoteRepository', e);
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
      _logger.error(
          'Exception in getFeedNotesFromFollowList', 'NoteRepository', e);
      return Result.error('Failed to get feed notes: ${e.toString()}');
    }
  }

  Future<Result<List<Map<String, dynamic>>>> getProfileNotes({
    required String authorNpub,
    int limit = 50,
    DateTime? until,
    DateTime? since,
    bool skipCache = false,
  }) async {
    if (authorNpub.isEmpty) {
      return const Result.error('NPUB cannot be empty');
    }

    final currentUserNpub = _nostrDataService.currentUserNpub;
    final filter = ProfileFeedFilter(
      targetUserNpub: authorNpub,
      currentUserNpub:
          currentUserNpub.isNotEmpty ? currentUserNpub : authorNpub,
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

  void fetchInteractionsForNoteIds(List<String> noteIds) {
    if (noteIds.isEmpty) return;
    try {
      _nostrDataService.fetchInteractionsForNotesBatchWithEOSE(noteIds);
    } catch (e) {
      _logger.error(
          'Error fetching interactions for note IDs', 'NoteRepository', e);
    }
  }

  void _fetchInteractionsForNotes(List<Map<String, dynamic>> notes) {
    try {
      final noteIds = notes
          .map((note) {
            final kind = note['kind'] as int? ?? 0;
            final isRepost = kind == 6;
            if (isRepost) {
              final rootId = _getRootId(note);
              if (rootId != null && rootId.isNotEmpty) {
                return rootId;
              }
            }
            return note['id'] as String? ?? '';
          })
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (noteIds.isEmpty) return;

      _nostrDataService.fetchInteractionsForNotesBatchWithEOSE(noteIds);
    } catch (e) {
      _logger.error(
          'Error fetching interactions for notes', 'NoteRepository', e);
    }
  }

  void dispose() {
    _updateThrottleTimer?.cancel();
    _dataServiceSubscription?.cancel();
    _deletionSubscription?.cancel();
    _notesController.close();
  }
}
