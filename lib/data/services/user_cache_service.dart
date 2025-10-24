import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../../models/user_model.dart';
import 'isar_database_service.dart';

class CachedUserEntry {
  final UserModel user;
  final DateTime cachedAt;
  final DateTime expiresAt;
  int accessCount;
  DateTime lastAccessedAt;

  CachedUserEntry({
    required this.user,
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

class UserCacheService {
  static UserCacheService? _instance;
  static UserCacheService get instance => _instance ??= UserCacheService._internal();

  UserCacheService._internal() {
    _initializeIsar();
    _startCacheCleanup();
  }

  static const int maxCacheSize = 5000;
  static const Duration defaultTTL = Duration(minutes: 30);
  static const Duration persistentTTL = Duration(days: 7);
  static const Duration cleanupInterval = Duration(minutes: 5);

  final LinkedHashMap<String, CachedUserEntry> _memoryCache = LinkedHashMap();

  final IsarDatabaseService _isarService = IsarDatabaseService.instance;

  final Map<String, Completer<UserModel?>> _pendingRequests = {};

  int _l1CacheHits = 0;
  int _l2CacheHits = 0;
  int _cacheMisses = 0;
  int _cacheEvictions = 0;
  int _cacheExpiries = 0;
  int _deduplicatedRequests = 0;
  int _persistentWrites = 0;
  int _persistentReads = 0;

  Timer? _cleanupTimer;
  bool _isIsarInitialized = false;

  IsarDatabaseService get isarService => _isarService;

  Future<void> _initializeIsar() async {
    try {
      await _isarService.initialize();
      _isIsarInitialized = true;
      debugPrint('[UserCacheService] Isar persistent cache initialized');
    } catch (e) {
      debugPrint('[UserCacheService] Error initializing Isar: $e');
      _isIsarInitialized = false;
    }
  }

  Future<UserModel?> get(String pubkeyHex) async {
    final memoryEntry = _memoryCache[pubkeyHex];

    if (memoryEntry != null) {
      if (memoryEntry.isExpired) {
        _memoryCache.remove(pubkeyHex);
        _cacheExpiries++;
      } else {
        memoryEntry.recordAccess();

        _memoryCache.remove(pubkeyHex);
        _memoryCache[pubkeyHex] = memoryEntry;

        _l1CacheHits++;
        debugPrint('[UserCacheService] L1 Cache HIT: ${memoryEntry.user.name}');
        return memoryEntry.user;
      }
    }

    if (_isIsarInitialized) {
      try {
        final profileData = await _isarService.getUserProfile(pubkeyHex);
        if (profileData != null) {
          _l2CacheHits++;
          _persistentReads++;

          final user = UserModel.fromCachedProfile(pubkeyHex, profileData);
          _putInMemory(user);

          debugPrint('[UserCacheService] L2 Cache HIT (promoted to L1): ${user.name}');
          return user;
        }
      } catch (e) {
        debugPrint('[UserCacheService] Error reading from L2 cache: $e');
      }
    }

    _cacheMisses++;
    return null;
  }

  UserModel? getSync(String pubkeyHex) {
    final entry = _memoryCache[pubkeyHex];

    if (entry == null) {
      return null;
    }

    if (entry.isExpired) {
      _memoryCache.remove(pubkeyHex);
      _cacheExpiries++;
      return null;
    }

    entry.recordAccess();

    _memoryCache.remove(pubkeyHex);
    _memoryCache[pubkeyHex] = entry;

    _l1CacheHits++;
    return entry.user;
  }

  void _putInMemory(UserModel user, {Duration? ttl}) {
    final now = DateTime.now();
    final expiresAt = now.add(ttl ?? defaultTTL);

    final entry = CachedUserEntry(
      user: user,
      cachedAt: now,
      expiresAt: expiresAt,
      lastAccessedAt: now,
    );

    if (_memoryCache.containsKey(user.pubkeyHex)) {
      _memoryCache.remove(user.pubkeyHex);
      _memoryCache[user.pubkeyHex] = entry;
      return;
    }

    if (_memoryCache.length >= maxCacheSize) {
      _evictLRU();
    }

    _memoryCache[user.pubkeyHex] = entry;
  }

  Future<void> put(UserModel user, {Duration? ttl}) async {
    _memoryCache.remove(user.pubkeyHex);
    _putInMemory(user, ttl: ttl);

    if (_isIsarInitialized) {
      try {
        final profileData = {
          'name': user.name,
          'about': user.about,
          'nip05': user.nip05,
          'banner': user.banner,
          'profileImage': user.profileImage,
          'lud16': user.lud16,
          'website': user.website,
          'nip05Verified': user.nip05Verified.toString(),
        };
        await _isarService.deleteUserProfile(user.pubkeyHex);
        await _isarService.saveUserProfile(user.pubkeyHex, profileData);
        _persistentWrites++;
        debugPrint('[UserCacheService] Profile cache updated: ${user.name}');
      } catch (e) {
        debugPrint('[UserCacheService] Error writing to persistent cache: $e');
      }
    }
  }

  Future<UserModel?> getOrFetch(
    String pubkeyHex,
    Future<UserModel?> Function() fetcher,
  ) async {
    final cached = await get(pubkeyHex);
    if (cached != null) {
      return cached;
    }

    if (_pendingRequests.containsKey(pubkeyHex)) {
      _deduplicatedRequests++;
      debugPrint('[UserCacheService] Deduplicating request for: $pubkeyHex');
      return await _pendingRequests[pubkeyHex]!.future;
    }

    final completer = Completer<UserModel?>();
    _pendingRequests[pubkeyHex] = completer;

    try {
      final user = await fetcher();

      if (user != null) {
        await put(user);
      }

      completer.complete(user);
      return user;
    } catch (e) {
      debugPrint('[UserCacheService] Error fetching user $pubkeyHex: $e');
      completer.completeError(e);
      rethrow;
    } finally {
      _pendingRequests.remove(pubkeyHex);
    }
  }

  Future<Map<String, UserModel>> batchGet(List<String> pubkeyHexList) async {
    final result = <String, UserModel>{};
    final missingKeys = <String>[];

    for (final pubkeyHex in pubkeyHexList) {
      final user = getSync(pubkeyHex);
      if (user != null) {
        result[pubkeyHex] = user;
      } else {
        missingKeys.add(pubkeyHex);
      }
    }

    if (missingKeys.isNotEmpty && _isIsarInitialized) {
      try {
        final persistentProfiles = await _isarService.getUserProfiles(missingKeys);

        for (final entry in persistentProfiles.entries) {
          _l2CacheHits++;
          _persistentReads++;

          final user = UserModel.fromCachedProfile(entry.key, entry.value);
          _putInMemory(user);
          result[entry.key] = user;
        }
      } catch (e) {
        debugPrint('[UserCacheService] Error batch reading from L2 cache: $e');
      }
    }

    return result;
  }

  Future<void> batchPut(List<UserModel> users, {Duration? ttl}) async {
    for (final user in users) {
      _putInMemory(user, ttl: ttl);
    }

    if (_isIsarInitialized && users.isNotEmpty) {
      try {
        final profilesMap = <String, Map<String, String>>{};

        for (final user in users) {
          profilesMap[user.pubkeyHex] = {
            'name': user.name,
            'about': user.about,
            'nip05': user.nip05,
            'banner': user.banner,
            'profileImage': user.profileImage,
            'lud16': user.lud16,
            'website': user.website,
            'nip05Verified': user.nip05Verified.toString(),
          };
        }

        await _isarService.saveUserProfiles(profilesMap);
        _persistentWrites += users.length;
      } catch (e) {
        debugPrint('[UserCacheService] Error batch writing to persistent cache: $e');
      }
    }
  }

  Future<bool> contains(String pubkeyHex) async {
    final entry = _memoryCache[pubkeyHex];
    if (entry != null) {
      if (entry.isExpired) {
        _memoryCache.remove(pubkeyHex);
        _cacheExpiries++;
      } else {
        return true;
      }
    }

    if (_isIsarInitialized) {
      return await _isarService.hasUserProfile(pubkeyHex);
    }

    return false;
  }

  Future<void> invalidate(String pubkeyHex) async {
    _memoryCache.remove(pubkeyHex);

    if (_isIsarInitialized) {
      await _isarService.deleteUserProfile(pubkeyHex);
    }
  }

  Future<void> batchInvalidate(List<String> pubkeyHexList) async {
    for (final pubkeyHex in pubkeyHexList) {
      _memoryCache.remove(pubkeyHex);
    }

    if (_isIsarInitialized) {
      for (final pubkeyHex in pubkeyHexList) {
        await _isarService.deleteUserProfile(pubkeyHex);
      }
    }
  }

  Future<void> clear() async {
    _memoryCache.clear();
    _pendingRequests.clear();

    if (_isIsarInitialized) {
      await _isarService.clearAllUserProfiles();
    }

    _resetStats();
  }

  void _evictLRU() {
    if (_memoryCache.isEmpty) return;

    final firstKey = _memoryCache.keys.first;
    _memoryCache.remove(firstKey);
    _cacheEvictions++;
  }

  void _startCacheCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(cleanupInterval, (_) {
      _cleanupExpiredEntries();
    });
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
      _cacheExpiries++;
    }

    if (keysToRemove.isNotEmpty) {
      debugPrint('[UserCacheService] Cleaned up ${keysToRemove.length} expired L1 entries');
    }

    if (_isIsarInitialized) {
      _isarService.cleanupExpiredProfiles(ttl: persistentTTL).then((count) {
        if (count > 0) {
          debugPrint('[UserCacheService] Cleaned up $count expired L2 entries');
        }
      });
    }
  }

  Future<Map<String, dynamic>> getStats() async {
    final totalHits = _l1CacheHits + _l2CacheHits;
    final totalRequests = totalHits + _cacheMisses;
    final hitRate = totalRequests > 0 ? (totalHits / totalRequests * 100).toStringAsFixed(1) : '0.0';
    final l1HitRate = totalRequests > 0 ? (_l1CacheHits / totalRequests * 100).toStringAsFixed(1) : '0.0';
    final l2HitRate = totalRequests > 0 ? (_l2CacheHits / totalRequests * 100).toStringAsFixed(1) : '0.0';

    int? persistentCount;
    if (_isIsarInitialized) {
      persistentCount = await _isarService.getUserProfileCount();
    }

    return {
      'l1CacheSize': _memoryCache.length,
      'l1MaxSize': maxCacheSize,
      'l1CacheHits': _l1CacheHits,
      'l1HitRate': '$l1HitRate%',
      'l2Initialized': _isIsarInitialized,
      'l2CacheSize': persistentCount,
      'l2CacheHits': _l2CacheHits,
      'l2HitRate': '$l2HitRate%',
      'persistentWrites': _persistentWrites,
      'persistentReads': _persistentReads,
      'cacheMisses': _cacheMisses,
      'cacheEvictions': _cacheEvictions,
      'cacheExpiries': _cacheExpiries,
      'deduplicatedRequests': _deduplicatedRequests,
      'overallHitRate': '$hitRate%',
      'pendingRequests': _pendingRequests.length,
      'totalRequests': totalRequests,
    };
  }

  Future<void> printStats() async {
    final stats = await getStats();
    debugPrint('\n=== UserCacheService Statistics (2-Tier) ===');
    debugPrint('--- L1 Cache (Memory) ---');
    debugPrint('  Size: ${stats['l1CacheSize']}/${stats['l1MaxSize']}');
    debugPrint('  Hits: ${stats['l1CacheHits']} (${stats['l1HitRate']})');
    debugPrint('--- L2 Cache (Persistent) ---');
    debugPrint('  Initialized: ${stats['l2Initialized']}');
    debugPrint('  Size: ${stats['l2CacheSize']}');
    debugPrint('  Hits: ${stats['l2CacheHits']} (${stats['l2HitRate']})');
    debugPrint('  Reads: ${stats['persistentReads']}');
    debugPrint('  Writes: ${stats['persistentWrites']}');
    debugPrint('--- Overall ---');
    debugPrint('  Hit Rate: ${stats['overallHitRate']}');
    debugPrint('  Misses: ${stats['cacheMisses']}');
    debugPrint('  Evictions: ${stats['cacheEvictions']}');
    debugPrint('  Deduplicated: ${stats['deduplicatedRequests']}');
    debugPrint('  Pending: ${stats['pendingRequests']}');
    debugPrint('==========================================\n');
  }

  void _resetStats() {
    _l1CacheHits = 0;
    _l2CacheHits = 0;
    _cacheMisses = 0;
    _cacheEvictions = 0;
    _cacheExpiries = 0;
    _deduplicatedRequests = 0;
    _persistentWrites = 0;
    _persistentReads = 0;
  }

  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _memoryCache.clear();
    _pendingRequests.clear();

    if (_isIsarInitialized) {
      await _isarService.close();
    }
  }
}
