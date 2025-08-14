import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../models/repost_model.dart';
import '../models/zap_model.dart';
import '../models/following_model.dart';
import '../models/notification_model.dart';

class CacheService {
  // Hive boxes
  Box<UserModel>? usersBox;
  Box<NoteModel>? notesBox;
  Box<ReactionModel>? reactionsBox;
  Box<ReplyModel>? repliesBox;
  Box<RepostModel>? repostsBox;
  Box<FollowingModel>? followingBox;
  Box<ZapModel>? zapsBox;
  Box<NotificationModel>? notificationsBox;

  // Enhanced cache maps with LRU support
  final Map<String, List<ReactionModel>> reactionsMap = {};
  final Map<String, List<ReplyModel>> repliesMap = {};
  final Map<String, List<RepostModel>> repostsMap = {};
  final Map<String, List<ZapModel>> zapsMap = {};

  // Enhanced LRU tracking with frequency
  final Map<String, DateTime> _cacheAccessTimes = {};
  final Map<String, int> _cacheAccessFrequency = {};
  final Map<String, int> _cacheDataSize = {}; // Track data size for better eviction

  // Memory management - more aggressive limits
  static const int _maxCacheEntries = 1500; // Reduced from 2000
  static const int _cleanupThreshold = 1800; // Reduced threshold
  static const int _emergencyThreshold = 2000; // Emergency cleanup threshold
  Timer? _memoryCleanupTimer;

  // Performance metrics
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _cacheEvictions = 0;

  CacheService() {
    _startMemoryManagement();
  }

  void _startMemoryManagement() {
    // More frequent cleanup for better memory management
    _memoryCleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _performMemoryCleanup();
    });
  }

  void _performMemoryCleanup() {
    final totalEntries = reactionsMap.length + repliesMap.length + repostsMap.length + zapsMap.length;

    if (totalEntries > _emergencyThreshold) {
      _performEmergencyEviction();
    } else if (totalEntries > _cleanupThreshold) {
      _evictLeastRecentlyUsed();
    } else if (totalEntries > _maxCacheEntries) {
      _evictLeastFrequentlyUsed();
    }
  }

  void _performEmergencyEviction() {
    // Emergency: Remove 40% of cache entries
    final allKeys = _getAllCacheKeys();
    final removeCount = (allKeys.length * 0.4).round();

    // Prioritize removal by combining recency and frequency
    final scoredKeys = allKeys.map((key) {
      final lastAccess = _cacheAccessTimes[key] ?? DateTime.now().subtract(const Duration(days: 1));
      final frequency = _cacheAccessFrequency[key] ?? 0;
      final dataSize = _cacheDataSize[key] ?? 1;

      // Lower score = higher priority for removal
      final recencyScore = DateTime.now().difference(lastAccess).inMinutes;
      final frequencyScore = frequency == 0 ? 1000 : (1000 / frequency);
      final sizeScore = dataSize * 10; // Penalize large entries

      return MapEntry(key, recencyScore + frequencyScore + sizeScore);
    }).toList();

    scoredKeys.sort((a, b) => b.value.compareTo(a.value)); // Highest score first (least valuable)

    final keysToRemove = scoredKeys.take(removeCount).map((e) => e.key);
    _removeKeys(keysToRemove);

    _cacheEvictions += removeCount;
    debugPrint('[CacheService] Emergency eviction: removed $removeCount entries');
  }

  void _evictLeastRecentlyUsed() {
    final allKeys = _getAllCacheKeys();
    final removeCount = allKeys.length - _maxCacheEntries;

    if (removeCount <= 0) return;

    // Sort by access time (oldest first)
    final sortedKeys = allKeys.map((key) {
      final lastAccess = _cacheAccessTimes[key] ?? DateTime.now().subtract(const Duration(days: 1));
      return MapEntry(key, lastAccess);
    }).toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final keysToRemove = sortedKeys.take(removeCount).map((e) => e.key);
    _removeKeys(keysToRemove);

    _cacheEvictions += removeCount;
  }

  void _evictLeastFrequentlyUsed() {
    final allKeys = _getAllCacheKeys();
    final removeCount = (allKeys.length * 0.1).round(); // Remove 10%

    if (removeCount <= 0) return;

    // Sort by frequency (lowest first)
    final sortedKeys = allKeys.map((key) {
      final frequency = _cacheAccessFrequency[key] ?? 0;
      return MapEntry(key, frequency);
    }).toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final keysToRemove = sortedKeys.take(removeCount).map((e) => e.key);
    _removeKeys(keysToRemove);

    _cacheEvictions += removeCount;
  }

  List<String> _getAllCacheKeys() {
    final allKeys = <String>[];
    allKeys.addAll(reactionsMap.keys);
    allKeys.addAll(repliesMap.keys);
    allKeys.addAll(repostsMap.keys);
    allKeys.addAll(zapsMap.keys);
    return allKeys;
  }

  void _removeKeys(Iterable<String> keys) {
    for (final key in keys) {
      reactionsMap.remove(key);
      repliesMap.remove(key);
      repostsMap.remove(key);
      zapsMap.remove(key);
      _cacheAccessTimes.remove(key);
      _cacheAccessFrequency.remove(key);
      _cacheDataSize.remove(key);
    }
  }

  void _recordCacheAccess(String key, {int dataSize = 1}) {
    _cacheAccessTimes[key] = DateTime.now();
    _cacheAccessFrequency[key] = (_cacheAccessFrequency[key] ?? 0) + 1;
    _cacheDataSize[key] = dataSize;

    // Decay frequency over time to prevent old entries from staying forever
    if (_cacheAccessFrequency[key]! > 100) {
      _cacheAccessFrequency[key] = (_cacheAccessFrequency[key]! * 0.9).round();
    }
  }

  Future<void> initializeBoxes(String npub, String dataType) async {
    // Phase 1: Open critical boxes first (blocking)
    await _initializeCriticalBoxes(npub, dataType);

    // Phase 2: Open remaining boxes in background (non-blocking)
    _initializeRemainingBoxes(npub, dataType);

    // Phase 3: Start progressive cache loading (non-blocking)
    _startProgressiveCacheLoading();
  }

  Future<void> _initializeCriticalBoxes(String npub, String dataType) async {
    final criticalBoxFutures = [
      _openHiveBox<NoteModel>('notes_${dataType}_$npub'),
      _openHiveBox<UserModel>('users'),
      _openHiveBox<FollowingModel>('followingBox'),
    ];

    final boxes = await Future.wait(criticalBoxFutures);
    notesBox = boxes[0] as Box<NoteModel>;
    usersBox = boxes[1] as Box<UserModel>;
    followingBox = boxes[2] as Box<FollowingModel>;
  }

  void _initializeRemainingBoxes(String npub, String dataType) {
    Future.microtask(() async {
      final remainingBoxFutures = [
        _openHiveBox<ReactionModel>('reactions_${dataType}_$npub'),
        _openHiveBox<ReplyModel>('replies_${dataType}_$npub'),
        _openHiveBox<RepostModel>('reposts_${dataType}_$npub'),
        _openHiveBox<ZapModel>('zaps_${dataType}_$npub'),
        _openHiveBox<NotificationModel>('notifications_$npub'),
      ];

      final boxes = await Future.wait(remainingBoxFutures);
      reactionsBox = boxes[0] as Box<ReactionModel>;
      repliesBox = boxes[1] as Box<ReplyModel>;
      repostsBox = boxes[2] as Box<RepostModel>;
      zapsBox = boxes[3] as Box<ZapModel>;
      notificationsBox = boxes[4] as Box<NotificationModel>;
    });
  }

  void _startProgressiveCacheLoading() {
    Future.microtask(() async {
      // Load critical cache first (reactions for immediate display)
      await loadReactionsFromCache();

      // Small delay then load remaining cache progressively
      await Future.delayed(const Duration(milliseconds: 50));

      // Load remaining cache in parallel but with lower priority
      Future.wait([
        loadRepliesFromCache(),
        loadRepostsFromCache(),
        loadZapsFromCache(),
      ]);
    });
  }

  Future<Box<T>> _openHiveBox<T>(String boxName) async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<T>(boxName);
    } else {
      return await Hive.openBox<T>(boxName);
    }
  }

  Future<void> loadReactionsFromCache() async {
    if (reactionsBox == null || !reactionsBox!.isOpen) return;

    try {
      final allReactions = reactionsBox!.values.cast<ReactionModel>().toList();
      if (allReactions.isEmpty) return;

      // Ultra-fast loading with minimal processing
      const batchSize = 200; // Larger batches for speed
      final Map<String, List<ReactionModel>> tempMap = {};

      for (int i = 0; i < allReactions.length; i += batchSize) {
        final batch = allReactions.skip(i).take(batchSize);

        for (var reaction in batch) {
          tempMap.putIfAbsent(reaction.targetEventId, () => []).add(reaction);
        }

        // Minimal yielding - only every 1000 items
        if (i % 1000 == 0 && i > 0) {
          await Future.delayed(Duration.zero);
        }
      }

      // Direct assignment for speed (no duplicate checking during initial load)
      reactionsMap.addAll(tempMap);

      // Record access times in batch with data size
      for (final entry in tempMap.entries) {
        _recordCacheAccess(entry.key, dataSize: entry.value.length);
      }

      _cacheHits += tempMap.length;
    } catch (e) {
      print('Error loading reactions from cache: $e');
      _cacheMisses++;
    }
  }

  Future<void> loadRepliesFromCache() async {
    if (repliesBox == null || !repliesBox!.isOpen) return;

    try {
      final allReplies = repliesBox!.values.cast<ReplyModel>().toList();
      if (allReplies.isEmpty) return;

      // Fast loading with larger batches
      const batchSize = 300;
      final Map<String, List<ReplyModel>> tempMap = {};

      for (int i = 0; i < allReplies.length; i += batchSize) {
        final batch = allReplies.skip(i).take(batchSize);

        for (var reply in batch) {
          tempMap.putIfAbsent(reply.parentEventId, () => []).add(reply);
        }

        // Minimal yielding
        if (i % 1500 == 0 && i > 0) {
          await Future.delayed(Duration.zero);
        }
      }

      // Direct merge for speed
      for (final entry in tempMap.entries) {
        if (repliesMap.containsKey(entry.key)) {
          repliesMap[entry.key]!.addAll(entry.value);
        } else {
          repliesMap[entry.key] = entry.value;
        }
      }
    } catch (e) {
      print('Error loading replies from cache: $e');
    }
  }

  Future<void> loadRepostsFromCache() async {
    if (repostsBox == null || !repostsBox!.isOpen) return;

    try {
      final allReposts = repostsBox!.values.cast<RepostModel>().toList();
      if (allReposts.isEmpty) return;

      // Process in batches to avoid blocking the UI
      const batchSize = 100;
      final Map<String, List<RepostModel>> tempMap = {};

      for (int i = 0; i < allReposts.length; i += batchSize) {
        final batch = allReposts.skip(i).take(batchSize);

        for (var repost in batch) {
          tempMap.putIfAbsent(repost.originalNoteId, () => []);
          if (!tempMap[repost.originalNoteId]!.any((r) => r.id == repost.id)) {
            tempMap[repost.originalNoteId]!.add(repost);
          }
        }

        // Yield control to prevent blocking
        if (i % (batchSize * 5) == 0) {
          await Future.delayed(Duration.zero);
        }
      }

      // Merge with existing cache
      for (final entry in tempMap.entries) {
        repostsMap.putIfAbsent(entry.key, () => []);
        for (final repost in entry.value) {
          if (!repostsMap[entry.key]!.any((r) => r.id == repost.id)) {
            repostsMap[entry.key]!.add(repost);
          }
        }
      }
    } catch (e) {
      print('Error loading reposts from cache: $e');
    }
  }

  Future<void> loadZapsFromCache() async {
    if (zapsBox == null || !zapsBox!.isOpen) return;

    try {
      final allZaps = zapsBox!.values.cast<ZapModel>().toList();
      if (allZaps.isEmpty) return;

      // Process in batches to avoid blocking the UI
      const batchSize = 100;
      final Map<String, List<ZapModel>> tempMap = {};

      for (int i = 0; i < allZaps.length; i += batchSize) {
        final batch = allZaps.skip(i).take(batchSize);

        for (var zap in batch) {
          tempMap.putIfAbsent(zap.targetEventId, () => []);
          if (!tempMap[zap.targetEventId]!.any((r) => r.id == zap.id)) {
            tempMap[zap.targetEventId]!.add(zap);
          }
        }

        // Yield control to prevent blocking
        if (i % (batchSize * 5) == 0) {
          await Future.delayed(Duration.zero);
        }
      }

      // Merge with existing cache
      for (final entry in tempMap.entries) {
        zapsMap.putIfAbsent(entry.key, () => []);
        for (final zap in entry.value) {
          if (!zapsMap[entry.key]!.any((r) => r.id == zap.id)) {
            zapsMap[entry.key]!.add(zap);
          }
        }
      }
    } catch (e) {
      print('Error loading zaps from cache: $e');
    }
  }

  Future<void> batchSaveNotes(List<NoteModel> notes) async {
    if (notesBox?.isOpen != true || notes.isEmpty) return;

    try {
      // Enhanced memory management
      final maxNotes = min(300, notes.length);
      final notesToSave = notes.take(maxNotes).toList();
      final notesMap = <String, NoteModel>{};

      // Adaptive batch processing
      int batchSize = 50;
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < notesToSave.length; i += batchSize) {
        final batch = notesToSave.skip(i).take(batchSize);

        for (final note in batch) {
          notesMap[note.id] = note;
        }

        // Adaptive batch sizing
        if (stopwatch.elapsedMilliseconds > 100) {
          batchSize = max(25, batchSize - 5);
        } else if (stopwatch.elapsedMilliseconds < 20) {
          batchSize = min(100, batchSize + 5);
        }

        // Yield control periodically
        if (i % (batchSize * 2) == 0) {
          await Future.delayed(Duration.zero);
          stopwatch.reset();
        }
      }

      // Efficient save operation
      if (notesMap.length < notesBox!.length * 0.8) {
        // If we're saving significantly fewer notes, clear first
        await notesBox!.clear();
      }
      await notesBox!.putAll(notesMap);
    } catch (e) {
      print('Error batch saving notes: $e');
    }
  }

  // Enhanced memory management methods
  Future<void> clearMemoryCache() async {
    reactionsMap.clear();
    repliesMap.clear();
    repostsMap.clear();
    zapsMap.clear();
    _cacheAccessTimes.clear();
    _cacheAccessFrequency.clear();
    _cacheDataSize.clear();
    _cacheHits = 0;
    _cacheMisses = 0;
    _cacheEvictions = 0;
  }

  Future<void> optimizeMemoryUsage() async {
    // Smart memory optimization using enhanced LRU
    _performMemoryCleanup();

    // Compact lists to remove null entries
    _compactCacheMaps();

    // Clean up tracking maps
    _cleanupTrackingMaps();
  }

  void _compactCacheMaps() {
    // Remove empty lists and compact non-empty ones
    reactionsMap.removeWhere((key, value) => value.isEmpty);
    repliesMap.removeWhere((key, value) => value.isEmpty);
    repostsMap.removeWhere((key, value) => value.isEmpty);
    zapsMap.removeWhere((key, value) => value.isEmpty);
  }

  void _cleanupTrackingMaps() {
    // Get all valid keys
    final allKeys = _getAllCacheKeys().toSet();

    // Remove orphaned tracking entries
    _cacheAccessTimes.removeWhere((key, value) => !allKeys.contains(key));
    _cacheAccessFrequency.removeWhere((key, value) => !allKeys.contains(key));
    _cacheDataSize.removeWhere((key, value) => !allKeys.contains(key));
  }

  // Memory pressure handling
  Future<void> handleMemoryPressure() async {
    _performEmergencyEviction();
    await optimizeMemoryUsage();
  }

  // Enhanced cache statistics
  Map<String, dynamic> getCacheStats() {
    final totalEntries = reactionsMap.length + repliesMap.length + repostsMap.length + zapsMap.length;
    final totalDataSize = _cacheDataSize.values.fold<int>(0, (sum, size) => sum + size);

    return {
      'reactionsCount': reactionsMap.length,
      'repliesCount': repliesMap.length,
      'repostsCount': repostsMap.length,
      'zapsCount': zapsMap.length,
      'totalEntries': totalEntries,
      'totalDataSize': totalDataSize,
      'maxEntries': _maxCacheEntries,
      'cleanupThreshold': _cleanupThreshold,
      'emergencyThreshold': _emergencyThreshold,
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'cacheEvictions': _cacheEvictions,
      'hitRate': _cacheHits + _cacheMisses > 0 ? (_cacheHits / (_cacheHits + _cacheMisses) * 100).toStringAsFixed(2) : '0.00',
      'memoryPressure': totalEntries > _cleanupThreshold,
      'emergencyPressure': totalEntries > _emergencyThreshold,
      'trackingMapSizes': {
        'accessTimes': _cacheAccessTimes.length,
        'frequency': _cacheAccessFrequency.length,
        'dataSize': _cacheDataSize.length,
      },
    };
  }

  // Cleanup method
  void dispose() {
    _memoryCleanupTimer?.cancel();
    clearMemoryCache();
  }

  void cleanupExpiredCache(Duration ttl) {
    final now = DateTime.now();
    final cutoffTime = now.subtract(ttl);

    // Clean reactions
    reactionsMap.removeWhere((eventId, reactions) {
      reactions.removeWhere((reaction) => reaction.fetchedAt.isBefore(cutoffTime));
      return reactions.isEmpty;
    });

    // Clean replies
    repliesMap.removeWhere((eventId, replies) {
      replies.removeWhere((reply) => reply.fetchedAt.isBefore(cutoffTime));
      return replies.isEmpty;
    });
  }
}
