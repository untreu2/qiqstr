import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';
import '../models/user_model.dart';
import '../models/note_model.dart';
import 'nostr_service.dart';
import '../constants/relays.dart';

class CachedProfile {
  final Map<String, String> data;
  final DateTime fetchedAt;
  final int accessCount;
  final DateTime lastAccessed;

  CachedProfile(this.data, this.fetchedAt, {this.accessCount = 1, DateTime? lastAccessed}) : lastAccessed = lastAccessed ?? DateTime.now();

  CachedProfile copyWithAccess() {
    return CachedProfile(data, fetchedAt, accessCount: accessCount + 1, lastAccessed: DateTime.now());
  }
}

class ProfileBatchRequest {
  final List<String> npubs;
  final Completer<void> completer;
  final DateTime requestedAt;

  ProfileBatchRequest(this.npubs, this.completer, this.requestedAt);
}

class ProfileService {
  final Map<String, CachedProfile> _profileCache = {};
  final Map<String, Completer<Map<String, String>>> _pendingRequests = {};
  final Queue<ProfileBatchRequest> _batchQueue = Queue();
  final Duration _cacheTTL = const Duration(minutes: 30);
  final int _maxCacheSize = 5000;

  Box<UserModel>? _usersBox;
  Timer? _batchTimer;
  Timer? _cleanupTimer;
  bool _isBatchProcessing = false;

  // Performance metrics
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _primalFetches = 0;
  int _relayFetches = 0;
  int _batchRequestsProcessed = 0;

  // Profile notes fetching - direct relay access
  final Map<String, List<NoteModel>> _profileNotesCache = {};
  final Map<String, DateTime> _profileNotesCacheTime = {};
  final Map<String, Completer<List<NoteModel>>> _pendingNotesRequests = {};
  final Duration _notesCacheTTL = const Duration(minutes: 15);
  int _directRelayFetches = 0;

  Future<void> initialize() async {
    _startBatchProcessing();
    _startPeriodicCleanup();
  }

  void _startBatchProcessing() {
    _batchTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _processBatchQueue();
    });
  }

  void _startPeriodicCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _performCleanup();
    });
  }

  void _performCleanup() {
    cleanupCache();
    _cleanupOldBatchRequests();
  }

  void _cleanupOldBatchRequests() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    while (_batchQueue.isNotEmpty && _batchQueue.first.requestedAt.isBefore(cutoff)) {
      final request = _batchQueue.removeFirst();
      if (!request.completer.isCompleted) {
        request.completer.complete();
      }
    }
  }

  void setUsersBox(Box<UserModel> box) {
    _usersBox = box;
  }

  Future<Map<String, String>> getCachedUserProfile(String npub) async {
    return await _getCachedUserProfileInternal(npub);
  }

  Future<Map<String, String>> _getCachedUserProfileInternal(String npub) async {
    final stopwatch = Stopwatch()..start();

    try {
      final now = DateTime.now();

      // Check memory cache first
      if (_profileCache.containsKey(npub)) {
        final cached = _profileCache[npub]!;
        if (now.difference(cached.fetchedAt) < _cacheTTL) {
          _profileCache[npub] = cached.copyWithAccess();
          _cacheHits++;
          _recordMetric('profile_cache_hit', stopwatch.elapsedMilliseconds);
          return cached.data;
        } else {
          _profileCache.remove(npub);
        }
      }

      _cacheMisses++;

      // Check if already fetching
      if (_pendingRequests.containsKey(npub)) {
        final result = await _pendingRequests[npub]!.future;
        _recordMetric('profile_pending_wait', stopwatch.elapsedMilliseconds);
        return result;
      }

      final completer = Completer<Map<String, String>>();
      _pendingRequests[npub] = completer;

      try {
        // Check Hive cache first
        final user = _usersBox?.get(npub);
        if (user != null && now.difference(user.updatedAt) < _cacheTTL) {
          final data = _userModelToMap(user);
          _profileCache[npub] = CachedProfile(data, user.updatedAt);
          completer.complete(data);
          _recordMetric('profile_hive_hit', stopwatch.elapsedMilliseconds);
          return data;
        }

        // Try Primal cache - fallback implementation
        try {
          // For now, skip Primal cache to avoid dependency issues
          // final primal = PrimalCacheClient();
          // final primalProfile = await primal.fetchUserProfile(npub);
          // if (primalProfile != null) { ... }
        } catch (e) {
          print('[ProfileService] Primal cache unavailable: $e');
        }

        // Fallback to relay fetch
        final fetched = await _fetchUserProfileFromRelay(npub);
        if (fetched != null) {
          _relayFetches++;
          final cached = CachedProfile(fetched, DateTime.now());
          _addToCache(npub, cached);

          final usersBox = _usersBox;
          if (usersBox != null) {
            unawaited(usersBox.put(npub, UserModel.fromCachedProfile(npub, fetched)));
          }

          completer.complete(fetched);
          _recordMetric('profile_relay_fetch', stopwatch.elapsedMilliseconds);
          return fetched;
        }

        // Return default profile
        final defaultProfile = _getDefaultProfile();
        completer.complete(defaultProfile);
        _recordMetric('profile_default', stopwatch.elapsedMilliseconds);
        return defaultProfile;
      } catch (e) {
        final defaultProfile = _getDefaultProfile();
        completer.complete(defaultProfile);
        _recordMetric('profile_error', stopwatch.elapsedMilliseconds);
        return defaultProfile;
      } finally {
        _pendingRequests.remove(npub);
      }
    } catch (e) {
      _recordMetric('profile_fetch_error', stopwatch.elapsedMilliseconds);
      return _getDefaultProfile();
    }
  }

  Map<String, String> _getDefaultProfile() {
    return {'name': 'Anonymous', 'profileImage': '', 'about': '', 'nip05': '', 'banner': '', 'lud16': '', 'website': ''};
  }

  Map<String, String> _userModelToMap(UserModel user) {
    return {
      'name': user.name,
      'profileImage': user.profileImage,
      'about': user.about,
      'nip05': user.nip05,
      'banner': user.banner,
      'lud16': user.lud16,
      'website': user.website,
    };
  }

  void _addToCache(String npub, CachedProfile cached) {
    // Implement LRU eviction if cache is full
    if (_profileCache.length >= _maxCacheSize) {
      _evictLeastRecentlyUsed();
    }
    _profileCache[npub] = cached;
  }

  void _evictLeastRecentlyUsed() {
    if (_profileCache.isEmpty) return;

    String? oldestKey;
    DateTime? oldestTime;

    for (final entry in _profileCache.entries) {
      if (oldestTime == null || entry.value.lastAccessed.isBefore(oldestTime)) {
        oldestTime = entry.value.lastAccessed;
        oldestKey = entry.key;
      }
    }

    if (oldestKey != null) {
      _profileCache.remove(oldestKey);
    }
  }

  Future<void> batchFetchProfiles(List<String> npubs) async {
    if (npubs.isEmpty) return;

    final completer = Completer<void>();
    final request = ProfileBatchRequest(
        npubs.toSet().toList(), // Remove duplicates
        completer,
        DateTime.now());

    _batchQueue.add(request);

    // Process immediately if queue is getting large
    if (_batchQueue.length >= 5) {
      unawaited(_processBatchQueue());
    }

    return completer.future;
  }

  Future<void> _processBatchQueue() async {
    if (_isBatchProcessing || _batchQueue.isEmpty) return;

    _isBatchProcessing = true;
    final stopwatch = Stopwatch()..start();

    try {
      final requestsToProcess = <ProfileBatchRequest>[];
      final allNpubs = <String>{};

      // Collect up to 3 batch requests to process together
      while (_batchQueue.isNotEmpty && requestsToProcess.length < 3) {
        final request = _batchQueue.removeFirst();
        requestsToProcess.add(request);
        allNpubs.addAll(request.npubs);
      }

      if (allNpubs.isNotEmpty) {
        await _processBatchInternal(allNpubs.toList());
        _batchRequestsProcessed += requestsToProcess.length;
      }

      // Complete all requests
      for (final request in requestsToProcess) {
        if (!request.completer.isCompleted) {
          request.completer.complete();
        }
      }

      _recordMetric('batch_processing', stopwatch.elapsedMilliseconds);
    } catch (e) {
      print('[ProfileService] Batch processing error: $e');
    } finally {
      _isBatchProcessing = false;
    }
  }

  Future<void> _processBatchInternal(List<String> npubs) async {
    final now = DateTime.now();
    final remainingForRelay = <String>[];

    // Filter out already cached profiles
    final npubsToFetch = npubs.where((npub) {
      if (_profileCache.containsKey(npub)) {
        final cached = _profileCache[npub]!;
        if (now.difference(cached.fetchedAt) < _cacheTTL) {
          return false; // Skip, already cached
        } else {
          _profileCache.remove(npub);
        }
      }
      return true;
    }).toList();

    // Process in smaller batches to avoid overwhelming services
    const batchSize = 15;
    for (int i = 0; i < npubsToFetch.length; i += batchSize) {
      final batch = npubsToFetch.skip(i).take(batchSize).toList();

      await Future.wait(batch.map((pub) async {
        try {
          // Check Hive cache first
          final user = _usersBox?.get(pub);
          if (user != null && now.difference(user.updatedAt) < _cacheTTL) {
            final data = _userModelToMap(user);
            _addToCache(pub, CachedProfile(data, user.updatedAt));
            return;
          }

          // Skip Primal cache for now to avoid dependency issues
          // TODO: Re-enable when PrimalCacheClient is properly imported
          remainingForRelay.add(pub);
        } catch (e) {
          print('[ProfileService] Error fetching profile for $pub: $e');
          remainingForRelay.add(pub);
        }
      }), eagerError: false);

      // Small delay between batches
      if (i + batchSize < npubsToFetch.length) {
        await Future.delayed(const Duration(milliseconds: 30));
      }
    }

    // Fetch remaining from relays if needed
    if (remainingForRelay.isNotEmpty) {
      unawaited(_batchFetchFromRelays(remainingForRelay));
    }
  }

  Future<void> _batchFetchFromRelays(List<String> npubs) async {
    if (npubs.isEmpty) return;

    _relayFetches += npubs.length;
    final now = DateTime.now();

    // Process in smaller batches to avoid overwhelming relays
    const batchSize = 10;
    for (int i = 0; i < npubs.length; i += batchSize) {
      final batch = npubs.skip(i).take(batchSize).toList();

      await Future.wait(batch.map((npub) async {
        try {
          final profile = await _fetchUserProfileFromRelay(npub);
          if (profile != null) {
            _addToCache(npub, CachedProfile(profile, now));

            final usersBox = _usersBox;
            if (usersBox != null && usersBox.isOpen) {
              final userModel = UserModel.fromCachedProfile(npub, profile);
              unawaited(usersBox.put(npub, userModel));
            }
          } else {
            // Add default profile to cache to avoid repeated fetching
            final defaultProfile = _getDefaultProfile();
            _addToCache(npub, CachedProfile(defaultProfile, now));
          }
        } catch (e) {
          print('[ProfileService] Error fetching profile for $npub: $e');
          final defaultProfile = _getDefaultProfile();
          _addToCache(npub, CachedProfile(defaultProfile, now));
        }
      }), eagerError: false);

      // Small delay between batches
      if (i + batchSize < npubs.length) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  Future<Map<String, String>?> _fetchUserProfileFromRelay(String npub) async {
    // Validate hex string format
    if (!_isValidHex(npub)) {
      print('[ProfileService] Invalid hex format: $npub');
      return null;
    }

    // Use a subset of main relays for profile fetching
    final relaysToUse = relaySetMainSockets.take(3).toList();

    for (final relayUrl in relaysToUse) {
      try {
        final result = await _fetchProfileFromSingleRelay(relayUrl, npub);
        if (result != null) {
          return result;
        }
      } catch (e) {
        print('[ProfileService] Error fetching from $relayUrl: $e');
        continue;
      }
    }

    return null;
  }

  Future<Map<String, String>?> _fetchProfileFromSingleRelay(String relayUrl, String npub) async {
    // Validate hex string format before making request
    if (!_isValidHex(npub)) {
      print('[ProfileService] Invalid hex format for relay request: $npub');
      return null;
    }

    WebSocket? ws;
    try {
      ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));
      final subscriptionId = DateTime.now().millisecondsSinceEpoch.toString();
      final request = jsonEncode([
        "REQ",
        subscriptionId,
        {
          "authors": [npub],
          "kinds": [0],
          "limit": 1
        }
      ]);

      final completer = Completer<Map<String, dynamic>?>();

      late StreamSubscription sub;
      sub = ws.listen((event) {
        try {
          if (completer.isCompleted) return;
          final decoded = jsonDecode(event);
          if (decoded is List && decoded.length >= 2) {
            if (decoded[0] == 'EVENT' && decoded[1] == subscriptionId) {
              completer.complete(decoded[2]);
            } else if (decoded[0] == 'EOSE' && decoded[1] == subscriptionId) {
              completer.complete(null);
            }
          }
        } catch (e) {
          if (!completer.isCompleted) completer.complete(null);
        }
      }, onError: (error) {
        if (!completer.isCompleted) completer.complete(null);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      }, cancelOnError: true);

      if (ws.readyState == WebSocket.open) {
        ws.add(request);
      }

      final eventData = await completer.future.timeout(const Duration(seconds: 5), onTimeout: () => null);

      try {
        await sub.cancel();
      } catch (_) {}

      try {
        await ws.close();
      } catch (_) {}

      if (eventData != null) {
        final contentRaw = eventData['content'];
        Map<String, dynamic> profileContent = {};
        if (contentRaw is String && contentRaw.isNotEmpty) {
          try {
            profileContent = jsonDecode(contentRaw);
          } catch (_) {}
        }

        return {
          'name': profileContent['name'] ?? 'Anonymous',
          'profileImage': profileContent['picture'] ?? '',
          'about': profileContent['about'] ?? '',
          'nip05': profileContent['nip05'] ?? '',
          'banner': profileContent['banner'] ?? '',
          'lud16': profileContent['lud16'] ?? '',
          'website': profileContent['website'] ?? '',
        };
      } else {
        return null;
      }
    } catch (e) {
      print('[ProfileService] Error fetching from $relayUrl: $e');
      try {
        await ws?.close();
      } catch (_) {}
      return null;
    }
  }

  // PROFILE NOTES FETCHING - DIRECT RELAY ACCESS
  // This method fetches kind 1 and 6 events directly from relays for profiles using the old approach
  Future<List<NoteModel>> fetchProfileNotesDirectly(String npub, {int limit = 100}) async {
    final stopwatch = Stopwatch()..start();

    try {
      final now = DateTime.now();

      // Check cache first
      if (_profileNotesCache.containsKey(npub)) {
        final cacheTime = _profileNotesCacheTime[npub];
        if (cacheTime != null && now.difference(cacheTime) < _notesCacheTTL) {
          _recordMetric('profile_notes_cache_hit', stopwatch.elapsedMilliseconds);
          return _profileNotesCache[npub]!;
        } else {
          _profileNotesCache.remove(npub);
          _profileNotesCacheTime.remove(npub);
        }
      }

      // Check if already fetching
      if (_pendingNotesRequests.containsKey(npub)) {
        final result = await _pendingNotesRequests[npub]!.future;
        _recordMetric('profile_notes_pending_wait', stopwatch.elapsedMilliseconds);
        return result;
      }

      final completer = Completer<List<NoteModel>>();
      _pendingNotesRequests[npub] = completer;

      try {
        final notes = await _fetchNotesFromRelaysDirectly(npub, limit);

        // Cache the results
        _profileNotesCache[npub] = notes;
        _profileNotesCacheTime[npub] = now;

        completer.complete(notes);
        _recordMetric('profile_notes_relay_fetch', stopwatch.elapsedMilliseconds);
        _directRelayFetches++;

        print('[ProfileService] Fetched ${notes.length} notes for profile $npub directly from relays');
        return notes;
      } catch (e) {
        print('[ProfileService] Error fetching profile notes for $npub: $e');
        final emptyList = <NoteModel>[];
        completer.complete(emptyList);
        _recordMetric('profile_notes_error', stopwatch.elapsedMilliseconds);
        return emptyList;
      } finally {
        _pendingNotesRequests.remove(npub);
      }
    } catch (e) {
      _recordMetric('profile_notes_fetch_error', stopwatch.elapsedMilliseconds);
      return <NoteModel>[];
    }
  }

  Future<List<NoteModel>> _fetchNotesFromRelaysDirectly(String npub, int limit) async {
    // Validate hex string format
    if (!_isValidHex(npub)) {
      print('[ProfileService] Invalid hex format for notes fetch: $npub');
      return <NoteModel>[];
    }

    final allNotes = <NoteModel>[];
    final processedEventIds = <String>{};

    // Create filter for kind 1 (notes) and kind 6 (reposts) for this specific user
    final filter = NostrService.createNotesFilter(
      authors: [npub],
      kinds: [1, 6],
      limit: limit,
    );

    final request = NostrService.serializeRequest(NostrService.createRequest(filter));

    // Use a subset of main relays for better performance
    final relaysToUse = relaySetMainSockets.take(5).toList();

    final futures = relaysToUse.map((relayUrl) => _fetchFromSingleRelayDirect(relayUrl, request, npub, processedEventIds));

    try {
      final results = await Future.wait(futures, eagerError: false);

      // Combine results from all relays
      for (final relayNotes in results) {
        for (final note in relayNotes) {
          if (!processedEventIds.contains(note.id)) {
            allNotes.add(note);
            processedEventIds.add(note.id);
          }
        }
      }

      // Sort by timestamp (newest first)
      allNotes.sort((a, b) {
        final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
        final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
        return bTime.compareTo(aTime);
      });

      // Limit the results
      return allNotes.take(limit).toList();
    } catch (e) {
      print('[ProfileService] Error in direct relay fetch: $e');
      return allNotes;
    }
  }

  Future<List<NoteModel>> _fetchFromSingleRelayDirect(String relayUrl, String request, String npub, Set<String> processedEventIds) async {
    final notes = <NoteModel>[];
    WebSocket? ws;

    try {
      ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));
      NostrService.generateUUID();
      final completer = Completer<void>();

      late StreamSubscription sub;
      sub = ws.listen(
        (event) {
          try {
            final decoded = jsonDecode(event);
            if (decoded is List && decoded.length >= 3) {
              if (decoded[0] == 'EVENT') {
                final eventData = decoded[2] as Map<String, dynamic>;
                final eventId = eventData['id'] as String?;

                if (eventId != null && !processedEventIds.contains(eventId)) {
                  final note = _parseEventToNote(eventData, npub);
                  if (note != null) {
                    notes.add(note);
                    processedEventIds.add(eventId);
                  }
                }
              } else if (decoded[0] == 'EOSE') {
                if (!completer.isCompleted) {
                  completer.complete();
                }
              }
            }
          } catch (e) {
            // Silently handle parsing errors
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        cancelOnError: false,
      );

      if (ws.readyState == WebSocket.open) {
        ws.add(request);
      }

      await completer.future.timeout(const Duration(seconds: 8), onTimeout: () {});

      await sub.cancel();
      await ws.close();
    } catch (e) {
      try {
        await ws?.close();
      } catch (_) {}
    }

    return notes;
  }

  NoteModel? _parseEventToNote(Map<String, dynamic> eventData, String expectedAuthor) {
    try {
      final kind = eventData['kind'] as int?;
      final eventId = eventData['id'] as String?;
      final author = eventData['pubkey'] as String?;
      final content = eventData['content'] as String?;
      final createdAt = eventData['created_at'] as int?;

      if (eventId == null || author == null || createdAt == null) {
        return null;
      }

      // Only process events from the expected author
      if (author != expectedAuthor) {
        return null;
      }

      final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
      final isRepost = kind == 6;

      // For reposts, try to parse the inner content
      String noteContent = content ?? '';
      String? originalAuthor;
      DateTime? repostTimestamp;

      if (isRepost) {
        repostTimestamp = timestamp;

        // Try to parse the reposted content
        if (content != null && content.isNotEmpty) {
          try {
            final innerEvent = jsonDecode(content) as Map<String, dynamic>;
            noteContent = innerEvent['content'] as String? ?? '';
            originalAuthor = innerEvent['pubkey'] as String?;
          } catch (e) {
            // If parsing fails, use the content as is
            noteContent = content;
          }
        }
      }

      return NoteModel(
        id: eventId,
        content: noteContent,
        author: originalAuthor ?? author,
        timestamp: isRepost ? (repostTimestamp ?? timestamp) : timestamp,
        isRepost: isRepost,
        repostedBy: isRepost ? author : null,
        repostTimestamp: repostTimestamp,
        rawWs: jsonEncode(eventData),
      );
    } catch (e) {
      print('[ProfileService] Error parsing event to note: $e');
      return null;
    }
  }

  // Clear profile notes cache
  void clearProfileNotesCache() {
    _profileNotesCache.clear();
    _profileNotesCacheTime.clear();
  }

  // Get cached profile notes without fetching
  List<NoteModel>? getCachedProfileNotes(String npub) {
    final now = DateTime.now();
    final cacheTime = _profileNotesCacheTime[npub];

    if (cacheTime != null && now.difference(cacheTime) < _notesCacheTTL) {
      return _profileNotesCache[npub];
    }

    return null;
  }

  void cleanupCache() {
    final now = DateTime.now();
    final cutoffTime = now.subtract(_cacheTTL);

    final sizeBefore = _profileCache.length;
    _profileCache.removeWhere((key, cached) => cached.fetchedAt.isBefore(cutoffTime));

    final removed = sizeBefore - _profileCache.length;
    if (removed > 0) {
      print('[ProfileService] Cleaned up $removed expired cache entries');
    }
  }

  Map<String, UserModel> getProfilesSnapshot() {
    return {for (var entry in _profileCache.entries) entry.key: UserModel.fromCachedProfile(entry.key, entry.value.data)};
  }

  // Enhanced statistics and monitoring
  Map<String, dynamic> getProfileStats() {
    final hitRate = _cacheHits + _cacheMisses > 0 ? (_cacheHits / (_cacheHits + _cacheMisses) * 100).toStringAsFixed(1) : '0.0';

    return {
      'cacheSize': _profileCache.length,
      'maxCacheSize': _maxCacheSize,
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'hitRate': '$hitRate%',
      'primalFetches': _primalFetches,
      'relayFetches': _relayFetches,
      'batchRequestsProcessed': _batchRequestsProcessed,
      'pendingRequests': _pendingRequests.length,
      'queuedBatches': _batchQueue.length,
      'isProcessing': _isBatchProcessing,
      // Profile notes stats
      'profileNotesCacheSize': _profileNotesCache.length,
      'directRelayFetches': _directRelayFetches,
      'pendingNotesRequests': _pendingNotesRequests.length,
    };
  }

  Future<void> dispose() async {
    _batchTimer?.cancel();
    _cleanupTimer?.cancel();

    // Complete any pending requests
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.complete(_getDefaultProfile());
      }
    }

    // Complete any pending batch requests
    for (final request in _batchQueue) {
      if (!request.completer.isCompleted) {
        request.completer.complete();
      }
    }

    _profileCache.clear();
    _pendingRequests.clear();
    _batchQueue.clear();

    // Clear profile notes cache
    _profileNotesCache.clear();
    _profileNotesCacheTime.clear();
    _pendingNotesRequests.clear();

    // Cleanup complete
  }

  // Force process pending batches
  void flushPendingBatches() {
    unawaited(_processBatchQueue());
  }

  // Performance metrics tracking
  final Map<String, List<int>> _metrics = {};

  void _recordMetric(String name, int value) {
    _metrics.putIfAbsent(name, () => []);
    _metrics[name]!.add(value);

    // Keep only recent metrics to prevent memory bloat
    if (_metrics[name]!.length > 100) {
      _metrics[name]!.removeRange(0, _metrics[name]!.length - 50);
    }
  }

  Map<String, dynamic> getMetrics() {
    final result = <String, dynamic>{};
    for (final entry in _metrics.entries) {
      if (entry.value.isNotEmpty) {
        final values = entry.value;
        result[entry.key] = {
          'count': values.length,
          'avg': values.reduce((a, b) => a + b) / values.length,
          'min': values.reduce((a, b) => a < b ? a : b),
          'max': values.reduce((a, b) => a > b ? a : b),
        };
      }
    }
    return result;
  }

  // Helper method to validate hex strings
  bool _isValidHex(String value) {
    if (value.isEmpty || value.length != 64) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }
}

// Helper function for fire-and-forget operations
void unawaited(Future<void> future) {
  future.catchError((error) {
    print('[ProfileService] Background operation failed: $error');
  });
}
