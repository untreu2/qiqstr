import 'dart:async';
import 'dart:math';
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

  // Cache access tracking for LRU
  final Map<String, DateTime> _cacheAccessTimes = {};

  // Memory management
  static const int _maxCacheEntries = 2000;
  static const int _cleanupThreshold = 2500;
  Timer? _memoryCleanupTimer;

  // Performance metrics
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _cacheEvictions = 0;

  CacheService() {
    _startMemoryManagement();
  }

  void _startMemoryManagement() {
    _memoryCleanupTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _performMemoryCleanup();
    });
  }

  void _performMemoryCleanup() {
    final totalEntries = reactionsMap.length + repliesMap.length + repostsMap.length + zapsMap.length;

    if (totalEntries > _cleanupThreshold) {
      _evictLeastRecentlyUsed();
    }
  }

  void _evictLeastRecentlyUsed() {
    final allKeys = <String, DateTime>{};

    // Collect all keys with their access times
    for (final key in reactionsMap.keys) {
      allKeys[key] = _cacheAccessTimes[key] ?? DateTime.now();
    }
    for (final key in repliesMap.keys) {
      allKeys[key] = _cacheAccessTimes[key] ?? DateTime.now();
    }
    for (final key in repostsMap.keys) {
      allKeys[key] = _cacheAccessTimes[key] ?? DateTime.now();
    }
    for (final key in zapsMap.keys) {
      allKeys[key] = _cacheAccessTimes[key] ?? DateTime.now();
    }

    // Sort by access time and remove oldest entries
    final sortedKeys = allKeys.entries.toList()..sort((a, b) => a.value.compareTo(b.value));

    final keysToRemove = sortedKeys.take(allKeys.length - _maxCacheEntries);

    for (final entry in keysToRemove) {
      final key = entry.key;
      reactionsMap.remove(key);
      repliesMap.remove(key);
      repostsMap.remove(key);
      zapsMap.remove(key);
      _cacheAccessTimes.remove(key);
      _cacheEvictions++;
    }
  }

  void _recordCacheAccess(String key) {
    _cacheAccessTimes[key] = DateTime.now();
  }

  Future<void> initializeBoxes(String npub, String dataType) async {
    final boxInitFutures = [
      _openHiveBox<NoteModel>('notes_${dataType}_$npub'),
      _openHiveBox<UserModel>('users'),
      _openHiveBox<ReactionModel>('reactions_${dataType}_$npub'),
      _openHiveBox<ReplyModel>('replies_${dataType}_$npub'),
      _openHiveBox<RepostModel>('reposts_${dataType}_$npub'),
      _openHiveBox<ZapModel>('zaps_${dataType}_$npub'),
      _openHiveBox<FollowingModel>('followingBox'),
      _openHiveBox<NotificationModel>('notifications_$npub'),
    ];

    final boxes = await Future.wait(boxInitFutures);
    notesBox = boxes[0] as Box<NoteModel>;
    usersBox = boxes[1] as Box<UserModel>;
    reactionsBox = boxes[2] as Box<ReactionModel>;
    repliesBox = boxes[3] as Box<ReplyModel>;
    repostsBox = boxes[4] as Box<RepostModel>;
    zapsBox = boxes[5] as Box<ZapModel>;
    followingBox = boxes[6] as Box<FollowingModel>;
    notificationsBox = boxes[7] as Box<NotificationModel>;

    // Load cache data in background to avoid blocking
    Future.microtask(() async {
      await Future.wait([
        loadReactionsFromCache(),
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

      // Enhanced batch processing with adaptive sizing
      int batchSize = 100;
      final Map<String, List<ReactionModel>> tempMap = {};
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < allReactions.length; i += batchSize) {
        final batch = allReactions.skip(i).take(batchSize);

        for (var reaction in batch) {
          tempMap.putIfAbsent(reaction.targetEventId, () => []);
          if (!tempMap[reaction.targetEventId]!.any((r) => r.id == reaction.id)) {
            tempMap[reaction.targetEventId]!.add(reaction);
          }
        }

        // Adaptive batch sizing based on performance
        if (stopwatch.elapsedMilliseconds > 50) {
          batchSize = max(50, batchSize - 10);
          stopwatch.reset();
        } else if (stopwatch.elapsedMilliseconds < 10) {
          batchSize = min(200, batchSize + 10);
        }

        // Yield control to prevent blocking
        if (i % (batchSize * 3) == 0) {
          await Future.delayed(Duration.zero);
          stopwatch.reset();
        }
      }

      // Efficient merge with existing cache
      for (final entry in tempMap.entries) {
        if (reactionsMap.containsKey(entry.key)) {
          final existing = reactionsMap[entry.key]!;
          final existingIds = existing.map((r) => r.id).toSet();
          final newReactions = entry.value.where((r) => !existingIds.contains(r.id));
          existing.addAll(newReactions);
        } else {
          reactionsMap[entry.key] = entry.value;
        }
        _recordCacheAccess(entry.key);
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

      // Process in batches to avoid blocking the UI
      const batchSize = 100;
      final Map<String, List<ReplyModel>> tempMap = {};

      for (int i = 0; i < allReplies.length; i += batchSize) {
        final batch = allReplies.skip(i).take(batchSize);

        for (var reply in batch) {
          tempMap.putIfAbsent(reply.parentEventId, () => []);
          if (!tempMap[reply.parentEventId]!.any((r) => r.id == reply.id)) {
            tempMap[reply.parentEventId]!.add(reply);
          }
        }

        // Yield control to prevent blocking
        if (i % (batchSize * 5) == 0) {
          await Future.delayed(Duration.zero);
        }
      }

      // Merge with existing cache
      for (final entry in tempMap.entries) {
        repliesMap.putIfAbsent(entry.key, () => []);
        for (final reply in entry.value) {
          if (!repliesMap[entry.key]!.any((r) => r.id == reply.id)) {
            repliesMap[entry.key]!.add(reply);
          }
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
    _cacheHits = 0;
    _cacheMisses = 0;
    _cacheEvictions = 0;
  }

  Future<void> optimizeMemoryUsage() async {
    // Smart memory optimization using LRU
    _evictLeastRecentlyUsed();

    // Compact lists to remove null entries
    _compactCacheMaps();
  }

  void _compactCacheMaps() {
    // Remove empty lists and compact non-empty ones
    reactionsMap.removeWhere((key, value) => value.isEmpty);
    repliesMap.removeWhere((key, value) => value.isEmpty);
    repostsMap.removeWhere((key, value) => value.isEmpty);
    zapsMap.removeWhere((key, value) => value.isEmpty);

    // Remove orphaned access times
    final allKeys = <String>{};
    allKeys.addAll(reactionsMap.keys);
    allKeys.addAll(repliesMap.keys);
    allKeys.addAll(repostsMap.keys);
    allKeys.addAll(zapsMap.keys);

    _cacheAccessTimes.removeWhere((key, value) => !allKeys.contains(key));
  }

  // Cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'reactionsCount': reactionsMap.length,
      'repliesCount': repliesMap.length,
      'repostsCount': repostsMap.length,
      'zapsCount': zapsMap.length,
      'totalEntries': reactionsMap.length + repliesMap.length + repostsMap.length + zapsMap.length,
      'maxEntries': _maxCacheEntries,
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'cacheEvictions': _cacheEvictions,
      'hitRate': _cacheHits + _cacheMisses > 0 ? (_cacheHits / (_cacheHits + _cacheMisses) * 100).toStringAsFixed(2) : '0.00',
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
