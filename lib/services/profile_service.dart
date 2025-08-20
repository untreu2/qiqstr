import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';
import '../models/user_model.dart';
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

class ProfileService {
  // Memory cache (existing)
  final Map<String, CachedProfile> _profileCache = {};

  // NEW STRUCTURE FOR PENDING REQUESTS
  // Keeps one Completer per 'npub'. This way, 10 simultaneous requests
  // for the same profile will all wait for a single network call result.
  final Map<String, Completer<Map<String, String>>> _pendingRequests = {};

  // QUEUE TO ACCUMULATE npubs TO BE PROCESSED
  final Set<String> _requestQueue = <String>{};

  // SHORT-TERM TIMER (DEBOUNCER)
  // When a request comes in, waits briefly for other requests to accumulate.
  Timer? _debounceTimer;

  // Cache configuration
  final Duration _cacheTTL = const Duration(minutes: 30);
  final int _maxCacheSize = 5000;
  Box<UserModel>? _usersBox;
  Timer? _cleanupTimer;

  // Performance metrics
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _relayFetches = 0;
  int _batchRequestsProcessed = 0;

  Future<void> initialize() async {
    _startPeriodicCleanup();
  }

  void _startPeriodicCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _performCleanup();
    });
  }

  void _performCleanup() {
    final now = DateTime.now();
    final cutoffTime = now.subtract(_cacheTTL);

    final sizeBefore = _profileCache.length;
    _profileCache.removeWhere((key, cached) => cached.fetchedAt.isBefore(cutoffTime));

    final removed = sizeBefore - _profileCache.length;
    if (removed > 0) {
      print('[ProfileService] Cleaned up $removed expired cache entries');
    }

    // LRU eviction if cache is too large
    if (_profileCache.length > _maxCacheSize) {
      _evictLeastRecentlyUsed();
    }
  }

  void setUsersBox(Box<UserModel> box) {
    _usersBox = box;
  }

  /// THE SINGLE METHOD USERS WILL CALL
  /// Never blocks UI - returns immediately with cached data or queues request
  Future<Map<String, String>> getCachedUserProfile(String npub) async {
    // 1. Check memory cache first (Fast path)
    if (_profileCache.containsKey(npub)) {
      final cached = _profileCache[npub]!;
      // TTL (Time-To-Live) check
      if (DateTime.now().difference(cached.fetchedAt) < _cacheTTL) {
        _cacheHits++;
        _profileCache[npub] = cached.copyWithAccess(); // Update access time
        return cached.data;
      } else {
        _profileCache.remove(npub); // Remove if expired
      }
    }

    _cacheMisses++;

    // 2. Is there already a pending request for this profile? If so, wait for its result.
    if (_pendingRequests.containsKey(npub)) {
      return _pendingRequests[npub]!.future;
    }

    // 3. No request exists, create a new one and add to queue.
    final completer = Completer<Map<String, String>>();
    _pendingRequests[npub] = completer;

    _requestQueue.add(npub);

    // Start/reset timer to process the queue
    _startDebounceTimer();

    return completer.future;
  }

  void _startDebounceTimer() {
    // If there's already a timer, cancel it.
    // This ensures multiple requests in short succession are batched together (debouncing).
    _debounceTimer?.cancel();

    // Process queue after 100ms. This duration can be adjusted based on your app's nature.
    _debounceTimer = Timer(const Duration(milliseconds: 100), _processRequestQueue);
  }

  Future<void> _processRequestQueue() async {
    if (_requestQueue.isEmpty) return;

    // Take all requests from queue and clear it.
    final npubsToFetch = List<String>.from(_requestQueue);
    _requestQueue.clear();

    print('[ProfileService] Processing batch of ${npubsToFetch.length} profiles.');

    // First check Hive cache.
    final npubsForRelay = <String>[];
    for (final npub in npubsToFetch) {
      final user = _usersBox?.get(npub);
      if (user != null && DateTime.now().difference(user.updatedAt) < _cacheTTL) {
        final data = _userModelToMap(user);
        _addToCache(npub, CachedProfile(data, user.updatedAt));
        // Complete this request
        _pendingRequests[npub]?.complete(data);
        _pendingRequests.remove(npub);
      } else {
        npubsForRelay.add(npub);
      }
    }

    // Make NETWORK request for the remaining ones
    if (npubsForRelay.isNotEmpty) {
      final results = await _batchFetchFromRelays(npubsForRelay);

      // Process results
      for (final npub in npubsForRelay) {
        final data = results[npub] ?? _getDefaultProfile();
        _addToCache(npub, CachedProfile(data, DateTime.now()));

        if (_usersBox != null && _usersBox!.isOpen) {
          final userModel = UserModel.fromCachedProfile(npub, data);
          _saveToHiveAsync(npub, userModel);
        }

        // Complete this request too
        _pendingRequests[npub]?.complete(data);
        _pendingRequests.remove(npub);
      }
    }

    _batchRequestsProcessed += npubsToFetch.length;
  }

  /// This method should now return a result map
  Future<Map<String, Map<String, String>>> _batchFetchFromRelays(List<String> npubs) async {
    final results = <String, Map<String, String>>{};
    if (npubs.isEmpty) return results;

    _relayFetches += npubs.length;

    // For simplicity, we'll use individual requests in parallel
    // In a real implementation, you'd want to use a single filter for all npubs
    final futures = npubs.map((npub) => _fetchUserProfileFromRelay(npub));
    final profileResults = await Future.wait(futures, eagerError: false);

    for (int i = 0; i < npubs.length; i++) {
      final npub = npubs[i];
      final profile = profileResults[i];
      if (profile != null) {
        results[npub] = profile;
      }
    }

    return results;
  }

  /// Legacy method for backward compatibility - now routes through unified system
  Future<void> batchFetchProfiles(List<String> npubs) async {
    if (npubs.isEmpty) return;

    final futures = npubs.map((npub) => getCachedUserProfile(npub));
    await Future.wait(futures, eagerError: false);
  }

  // Helper methods
  Map<String, String> _getDefaultProfile() {
    return {
      'name': 'Anonymous',
      'profileImage': '',
      'about': '',
      'nip05': '',
      'banner': '',
      'lud16': '',
      'website': '',
    };
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

  Future<Map<String, String>?> _fetchUserProfileFromRelay(String npub) async {
    // Validate hex string format
    if (!_isValidHex(npub)) {
      print('[ProfileService] Invalid hex format: $npub');
      return null;
    }

    // Use only 1 fast relay for individual requests
    final relayUrl = relaySetMainSockets.first;

    try {
      final result = await _fetchProfileFromSingleRelay(relayUrl, npub);
      return result;
    } catch (e) {
      print('[ProfileService] Error fetching from $relayUrl: $e');
      return null;
    }
  }

  Future<Map<String, String>?> _fetchProfileFromSingleRelay(String relayUrl, String npub) async {
    // Validate hex string format before making request
    if (!_isValidHex(npub)) {
      print('[ProfileService] Invalid hex format for relay request: $npub');
      return null;
    }

    WebSocket? ws;
    try {
      ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 3));
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

      final eventData = await completer.future.timeout(const Duration(seconds: 3), onTimeout: () => null);

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

  void _saveToHiveAsync(String npub, UserModel userModel) {
    // Save to Hive asynchronously without blocking
    Future.microtask(() async {
      try {
        final usersBox = _usersBox;
        if (usersBox != null && usersBox.isOpen) {
          await usersBox.put(npub, userModel);
        }
      } catch (e) {
        print('[ProfileService] Error saving to Hive: $e');
      }
    });
  }

  void cleanupCache() {
    _performCleanup();
  }

  Map<String, UserModel> getProfilesSnapshot() {
    return {for (var entry in _profileCache.entries) entry.key: UserModel.fromCachedProfile(entry.key, entry.value.data)};
  }

  Map<String, dynamic> getProfileStats() {
    final hitRate = _cacheHits + _cacheMisses > 0 ? (_cacheHits / (_cacheHits + _cacheMisses) * 100).toStringAsFixed(1) : '0.0';

    return {
      'cacheSize': _profileCache.length,
      'maxCacheSize': _maxCacheSize,
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'hitRate': '$hitRate%',
      'relayFetches': _relayFetches,
      'batchRequestsProcessed': _batchRequestsProcessed,
      'pendingRequests': _pendingRequests.length,
      'queuedRequests': _requestQueue.length,
    };
  }

  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _debounceTimer?.cancel();

    // Complete any pending requests
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.complete(_getDefaultProfile());
      }
    }

    _profileCache.clear();
    _pendingRequests.clear();
    _requestQueue.clear();
  }

  // Force process pending batches
  void flushPendingBatches() {
    _debounceTimer?.cancel();
    _processRequestQueue();
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
