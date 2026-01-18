import 'dart:async';
import 'package:flutter/foundation.dart';
import 'isar_database_service.dart';

class UserCacheService {
  static UserCacheService? _instance;
  static UserCacheService get instance =>
      _instance ??= UserCacheService._internal();

  UserCacheService._internal() {
    _initializeIsar();
  }

  static const Duration persistentTTL = Duration(days: 7);

  final IsarDatabaseService _isarService = IsarDatabaseService.instance;

  final Map<String, Completer<Map<String, dynamic>?>> _pendingRequests = {};

  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _deduplicatedRequests = 0;
  int _persistentWrites = 0;
  int _persistentReads = 0;

  bool _isIsarInitialized = false;

  IsarDatabaseService get isarService => _isarService;

  Future<void> _initializeIsar() async {
    try {
      await _isarService.initialize();
      _isIsarInitialized = true;
      debugPrint('[UserCacheService] Isar cache initialized');
    } catch (e) {
      debugPrint('[UserCacheService] Error initializing Isar: $e');
      _isIsarInitialized = false;
    }
  }

  Future<Map<String, dynamic>?> get(String pubkeyHex) async {
    if (!_isIsarInitialized) {
      _cacheMisses++;
      return null;
    }

    try {
      final profileData = await _isarService.getUserProfile(pubkeyHex);
      if (profileData != null) {
        _cacheHits++;
        _persistentReads++;

        final user = _createUserFromProfileData(pubkeyHex, profileData);
        return user;
      }
    } catch (e) {
      debugPrint('[UserCacheService] Error reading from cache: $e');
    }

    _cacheMisses++;
    return null;
  }

  Future<void> put(Map<String, dynamic> user, {Duration? ttl}) async {
    final pubkeyHex = user['pubkeyHex'] as String? ?? '';

    if (_isIsarInitialized && pubkeyHex.isNotEmpty) {
      try {
        final profileData = <String, String>{
          'name': user['name'] as String? ?? '',
          'about': user['about'] as String? ?? '',
          'nip05': user['nip05'] as String? ?? '',
          'banner': user['banner'] as String? ?? '',
          'profileImage': user['profileImage'] as String? ?? '',
          'lud16': user['lud16'] as String? ?? '',
          'website': user['website'] as String? ?? '',
          'nip05Verified': (user['nip05Verified'] as bool? ?? false).toString(),
        };
        await _isarService.saveUserProfile(pubkeyHex, profileData);
        _persistentWrites++;
      } catch (e) {
        debugPrint('[UserCacheService] Error writing to cache: $e');
      }
    }
  }

  Future<Map<String, dynamic>?> getOrFetch(
    String pubkeyHex,
    Future<Map<String, dynamic>?> Function() fetcher,
  ) async {
    final cached = await get(pubkeyHex);
    if (cached != null) {
      return cached;
    }

    if (_pendingRequests.containsKey(pubkeyHex)) {
      _deduplicatedRequests++;
      return await _pendingRequests[pubkeyHex]!.future;
    }

    final completer = Completer<Map<String, dynamic>?>();
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

  Future<Map<String, Map<String, dynamic>>> batchGet(
      List<String> pubkeyHexList) async {
    final result = <String, Map<String, dynamic>>{};

    if (!_isIsarInitialized || pubkeyHexList.isEmpty) {
      return result;
    }

    try {
      final persistentProfiles =
          await _isarService.getUserProfiles(pubkeyHexList);

      for (final entry in persistentProfiles.entries) {
        _cacheHits++;
        _persistentReads++;

        final user = _createUserFromProfileData(entry.key, entry.value);
        result[entry.key] = user;
      }
    } catch (e) {
      debugPrint('[UserCacheService] Error batch reading from cache: $e');
    }

    return result;
  }

  Future<void> batchPut(List<Map<String, dynamic>> users,
      {Duration? ttl}) async {
    if (!_isIsarInitialized || users.isEmpty) {
      return;
    }

    try {
      final profilesMap = <String, Map<String, String>>{};

      for (final user in users) {
        final pubkeyHex = user['pubkeyHex'] as String? ?? '';
        if (pubkeyHex.isNotEmpty) {
          profilesMap[pubkeyHex] = {
            'name': user['name'] as String? ?? '',
            'about': user['about'] as String? ?? '',
            'nip05': user['nip05'] as String? ?? '',
            'banner': user['banner'] as String? ?? '',
            'profileImage': user['profileImage'] as String? ?? '',
            'lud16': user['lud16'] as String? ?? '',
            'website': user['website'] as String? ?? '',
            'nip05Verified':
                (user['nip05Verified'] as bool? ?? false).toString(),
          };
        }
      }

      await _isarService.saveUserProfiles(profilesMap);
      _persistentWrites += users.length;
    } catch (e) {
      debugPrint('[UserCacheService] Error batch writing to cache: $e');
    }
  }

  Future<bool> contains(String pubkeyHex) async {
    if (!_isIsarInitialized) {
      return false;
    }

    return await _isarService.hasUserProfile(pubkeyHex);
  }

  Future<void> invalidate(String pubkeyHex) async {}

  Future<void> clear() async {
    _pendingRequests.clear();
    _resetStats();
  }

  Future<Map<String, dynamic>> getStats() async {
    final totalRequests = _cacheHits + _cacheMisses;
    final hitRate = totalRequests > 0
        ? (_cacheHits / totalRequests * 100).toStringAsFixed(1)
        : '0.0';

    int? cacheCount;
    if (_isIsarInitialized) {
      cacheCount = await _isarService.getUserProfileCount();
    }

    return {
      'initialized': _isIsarInitialized,
      'cacheSize': cacheCount,
      'cacheHits': _cacheHits,
      'hitRate': '$hitRate%',
      'cacheMisses': _cacheMisses,
      'persistentWrites': _persistentWrites,
      'persistentReads': _persistentReads,
      'deduplicatedRequests': _deduplicatedRequests,
      'pendingRequests': _pendingRequests.length,
      'totalRequests': totalRequests,
    };
  }

  Future<void> printStats() async {
    final stats = await getStats();
    debugPrint('\n=== UserCacheService Statistics ===');
    debugPrint('  Initialized: ${stats['initialized']}');
    debugPrint('  Size: ${stats['cacheSize']}');
    debugPrint('  Hits: ${stats['cacheHits']} (${stats['hitRate']})');
    debugPrint('  Misses: ${stats['cacheMisses']}');
    debugPrint('  Reads: ${stats['persistentReads']}');
    debugPrint('  Writes: ${stats['persistentWrites']}');
    debugPrint('  Deduplicated: ${stats['deduplicatedRequests']}');
    debugPrint('  Pending: ${stats['pendingRequests']}');
    debugPrint('====================================\n');
  }

  void _resetStats() {
    _cacheHits = 0;
    _cacheMisses = 0;
    _deduplicatedRequests = 0;
    _persistentWrites = 0;
    _persistentReads = 0;
  }

  Future<void> dispose() async {
    _pendingRequests.clear();

    if (_isIsarInitialized) {
      await _isarService.close();
    }
  }

  Map<String, dynamic> _createUserFromProfileData(
      String pubkeyHex, Map<String, String> profileData) {
    return {
      'pubkeyHex': pubkeyHex,
      'name': profileData['name'] ?? '',
      'about': profileData['about'] ?? '',
      'profileImage': profileData['profileImage'] ?? '',
      'banner': profileData['banner'] ?? '',
      'website': profileData['website'] ?? '',
      'nip05': profileData['nip05'] ?? '',
      'lud16': profileData['lud16'] ?? '',
      'updatedAt': DateTime.now(),
      'nip05Verified': profileData['nip05Verified'] == 'true',
      'followerCount': 0,
    };
  }
}
