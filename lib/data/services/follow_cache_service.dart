import 'dart:async';
import 'dart:collection';
import 'isar_database_service.dart';

class CachedFollowEntry {
  final List<String> followingList;
  final DateTime cachedAt;
  final DateTime expiresAt;
  int accessCount;
  DateTime lastAccessedAt;

  CachedFollowEntry({
    required this.followingList,
    required this.cachedAt,
    required this.expiresAt,
    this.accessCount = 1,
    required this.lastAccessedAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  void recordAccess() {
    accessCount++;
    lastAccessedAt = DateTime.now();
  }
}

class FollowCacheService {
  static FollowCacheService? _instance;
  static FollowCacheService get instance =>
      _instance ??= FollowCacheService._internal();

  FollowCacheService._internal() {
    _initializeIsar();
    _startCacheCleanup();
  }

  static const int maxCacheSize = 2000;
  static const Duration defaultTTL = Duration(days: 1);
  static const Duration cleanupInterval = Duration(hours: 6);

  final LinkedHashMap<String, CachedFollowEntry> _memoryCache = LinkedHashMap();

  final IsarDatabaseService _isarService = IsarDatabaseService.instance;

  final Map<String, Completer<List<String>?>> _pendingRequests = {};

  bool _isCleanupRunning = false;
  bool _isIsarInitialized = false;

  IsarDatabaseService get isarService => _isarService;

  Future<void> _initializeIsar() async {
    try {
      await _isarService.initialize();
      _isIsarInitialized = true;
    } catch (e) {
      _isIsarInitialized = false;
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_isIsarInitialized) {
      await _initializeIsar();
    }
  }

  Future<List<String>?> get(String userPubkeyHex) async {
    final memoryEntry = _memoryCache[userPubkeyHex];

    if (memoryEntry != null) {
      if (memoryEntry.isExpired) {
        _memoryCache.remove(userPubkeyHex);
      } else {
        memoryEntry.recordAccess();

        _memoryCache.remove(userPubkeyHex);
        _memoryCache[userPubkeyHex] = memoryEntry;

        return List<String>.from(memoryEntry.followingList);
      }
    }

    await _ensureInitialized();

    if (_isIsarInitialized) {
      try {
        final followingData =
            await _isarService.getFollowingList(userPubkeyHex);
        if (followingData != null) {
          _putInMemory(userPubkeyHex, followingData);
          return followingData;
        }
      } catch (e) {
        // Silently handle error - cache miss is acceptable
      }
    }

    return null;
  }

  List<String>? getSync(String userPubkeyHex) {
    final entry = _memoryCache[userPubkeyHex];

    if (entry == null) {
      return null;
    }

    if (entry.isExpired) {
      _memoryCache.remove(userPubkeyHex);
      return null;
    }

    entry.recordAccess();

    _memoryCache.remove(userPubkeyHex);
    _memoryCache[userPubkeyHex] = entry;

    return List<String>.from(entry.followingList);
  }

  void _putInMemory(String userPubkeyHex, List<String> followingList,
      {Duration? ttl}) {
    final now = DateTime.now();
    final expiresAt = now.add(ttl ?? defaultTTL);

    final entry = CachedFollowEntry(
      followingList: List<String>.from(followingList),
      cachedAt: now,
      expiresAt: expiresAt,
      lastAccessedAt: now,
    );

    if (_memoryCache.containsKey(userPubkeyHex)) {
      _memoryCache.remove(userPubkeyHex);
      _memoryCache[userPubkeyHex] = entry;
      return;
    }

    if (_memoryCache.length >= maxCacheSize) {
      _evictLRU();
    }

    _memoryCache[userPubkeyHex] = entry;
  }

  Future<void> put(String userPubkeyHex, List<String> followingList,
      {Duration? ttl}) async {
    _memoryCache.remove(userPubkeyHex);
    _putInMemory(userPubkeyHex, followingList, ttl: ttl);

    await _ensureInitialized();

    if (_isIsarInitialized) {
      try {
        await _isarService.saveFollowingList(userPubkeyHex, followingList);
      } catch (e) {
        // Handle error silently
      }
    }
  }

  Future<List<String>?> getOrFetch(
    String userPubkeyHex,
    Future<List<String>?> Function() fetcher,
  ) async {
    final cached = await get(userPubkeyHex);
    if (cached != null) {
      return cached;
    }

    if (_pendingRequests.containsKey(userPubkeyHex)) {
      return await _pendingRequests[userPubkeyHex]!.future;
    }

    final completer = Completer<List<String>?>();
    _pendingRequests[userPubkeyHex] = completer;

    try {
      final followingList = await fetcher();

      if (followingList != null) {
        await put(userPubkeyHex, followingList);
      }

      completer.complete(followingList);
      return followingList;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _pendingRequests.remove(userPubkeyHex);
    }
  }

  Future<Map<String, List<String>>> batchGet(
      List<String> userPubkeyHexList) async {
    final result = <String, List<String>>{};
    final missingKeys = <String>[];

    for (final userPubkeyHex in userPubkeyHexList) {
      final followingList = getSync(userPubkeyHex);
      if (followingList != null) {
        result[userPubkeyHex] = followingList;
      } else {
        missingKeys.add(userPubkeyHex);
      }
    }

    if (missingKeys.isNotEmpty && _isIsarInitialized) {
      try {
        final persistentFollowingLists =
            await _isarService.getFollowingLists(missingKeys);

        for (final entry in persistentFollowingLists.entries) {
          _putInMemory(entry.key, entry.value);
          result[entry.key] = entry.value;
        }
      } catch (e) {
        // Silently handle error - cache miss is acceptable
      }
    }

    return result;
  }

  Future<void> batchPut(Map<String, List<String>> followingLists,
      {Duration? ttl}) async {
    for (final entry in followingLists.entries) {
      _putInMemory(entry.key, entry.value, ttl: ttl);
    }

    if (_isIsarInitialized && followingLists.isNotEmpty) {
      try {
        await _isarService.saveFollowingLists(followingLists);
      } catch (e) {
        // Handle error silently
      }
    }
  }

  Future<bool> contains(String userPubkeyHex) async {
    final entry = _memoryCache[userPubkeyHex];
    if (entry != null) {
      if (entry.isExpired) {
        _memoryCache.remove(userPubkeyHex);
      } else {
        return true;
      }
    }

    if (_isIsarInitialized) {
      return await _isarService.hasFollowingList(userPubkeyHex);
    }

    return false;
  }

  Future<void> invalidate(String userPubkeyHex) async {
    _memoryCache.remove(userPubkeyHex);

    if (_isIsarInitialized) {
      await _isarService.deleteFollowingList(userPubkeyHex);
    }
  }

  Future<void> batchInvalidate(List<String> userPubkeyHexList) async {
    for (final userPubkeyHex in userPubkeyHexList) {
      _memoryCache.remove(userPubkeyHex);
    }

    if (_isIsarInitialized) {
      for (final userPubkeyHex in userPubkeyHexList) {
        await _isarService.deleteFollowingList(userPubkeyHex);
      }
    }
  }

  Future<void> clear() async {
    _memoryCache.clear();
    _pendingRequests.clear();

    if (_isIsarInitialized) {
      await _isarService.clearAllFollowingLists();
    }
  }

  void _evictLRU() {
    if (_memoryCache.isEmpty) return;

    final firstKey = _memoryCache.keys.first;
    _memoryCache.remove(firstKey);
  }

  void _startCacheCleanup() {
    _isCleanupRunning = true;
    _runCleanupLoop();
  }

  Future<void> _runCleanupLoop() async {
    while (_isCleanupRunning) {
      await Future.delayed(cleanupInterval);
      if (!_isCleanupRunning) break;
      _cleanupExpiredEntries();
    }
  }

  void _cleanupExpiredEntries() {
    final keysToRemove = <String>[];

    for (final entry in _memoryCache.entries) {
      if (entry.value.isExpired) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _memoryCache.remove(key);
    }
  }

  Future<void> dispose() async {
    _isCleanupRunning = false;
    _memoryCache.clear();
    _pendingRequests.clear();

    if (_isIsarInitialized) {
      await _isarService.close();
    }
  }
}
