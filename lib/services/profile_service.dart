import 'dart:async';
import 'dart:collection';
import 'package:hive/hive.dart';
import '../models/user_model.dart';
import 'relay_service.dart';
import 'base/service_base.dart';

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

        // Try Primal cache
        final primal = PrimalCacheClient();
        final primalProfile = await primal.fetchUserProfile(npub);
        if (primalProfile != null) {
          _primalFetches++;
          final cached = CachedProfile(primalProfile, DateTime.now());
          _addToCache(npub, cached);

          final usersBox = _usersBox;
          if (usersBox != null && usersBox.isOpen) {
            final userModel = UserModel.fromCachedProfile(npub, primalProfile);
            unawaited(usersBox.put(npub, userModel));
          }

          completer.complete(primalProfile);
          _recordMetric('profile_primal_fetch', stopwatch.elapsedMilliseconds);
          return primalProfile;
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
    final primal = PrimalCacheClient();
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

          // Try Primal cache
          final primalProfile = await primal.fetchUserProfile(pub);
          if (primalProfile != null) {
            _primalFetches++;
            final cached = CachedProfile(primalProfile, now);
            _addToCache(pub, cached);

            final usersBox = _usersBox;
            if (usersBox != null && usersBox.isOpen) {
              final userModel = UserModel.fromCachedProfile(pub, primalProfile);
              unawaited(usersBox.put(pub, userModel));
            }
            return;
          }

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
    // Implementation for relay batch fetching
    // This would use the existing relay infrastructure
    _relayFetches += npubs.length;

    // For now, just mark as attempted
    for (final npub in npubs) {
      final defaultProfile = _getDefaultProfile();
      _addToCache(npub, CachedProfile(defaultProfile, DateTime.now()));
    }
  }

  Future<Map<String, String>?> _fetchUserProfileFromRelay(String npub) async {
    // Implementation for single relay fetch
    // This would use the existing relay infrastructure
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
}

// Helper function for fire-and-forget operations
void unawaited(Future<void> future) {
  future.catchError((error) {
    print('[ProfileService] Background operation failed: $error');
  });
}
