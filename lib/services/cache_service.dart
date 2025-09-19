import 'dart:async';
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
import 'hive_manager.dart';

class CacheService {
  static CacheService? _instance;
  static CacheService get instance => _instance ??= CacheService._internal();

  CacheService._internal() {
    _startBasicCleanup();
  }

  final HiveManager _hiveManager = HiveManager.instance;

  Box<UserModel>? get usersBox => _hiveManager.usersBox;
  Box<NoteModel>? get notesBox => _hiveManager.notesBox;
  Box<ReactionModel>? get reactionsBox => _hiveManager.reactionsBox;
  Box<ReplyModel>? get repliesBox => _hiveManager.repliesBox;
  Box<RepostModel>? get repostsBox => _hiveManager.repostsBox;
  Box<FollowingModel>? get followingBox => _hiveManager.followingBox;
  Box<ZapModel>? get zapsBox => _hiveManager.zapsBox;
  Box<NotificationModel>? getNotificationBox(String npub) => _hiveManager.getNotificationBox(npub);

  Box<NotificationModel>? notificationsBox;

  final Map<String, List<ReactionModel>> reactionsMap = {};
  final Map<String, List<ReplyModel>> repliesMap = {};
  final Map<String, List<RepostModel>> repostsMap = {};
  final Map<String, List<ZapModel>> zapsMap = {};

  Timer? _cleanupTimer;
  Timer? _performanceMonitorTimer;
  static const int _maxCacheEntries = 1500; // Reduced for better performance
  static const int _highMemoryThreshold = 1200; // Trigger cleanup earlier
  static const int _criticalMemoryThreshold = 1400; // Emergency cleanup

  void _startBasicCleanup() {
    // More frequent cleanup for better performance
    _cleanupTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _performBasicCleanup();
    });

    // Performance monitoring
    _performanceMonitorTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _monitorPerformance();
    });
  }

  void _performBasicCleanup() {
    final totalEntries = reactionsMap.length + repliesMap.length + repostsMap.length + zapsMap.length;

    if (totalEntries > _maxCacheEntries) {
      final removeCount = (totalEntries * 0.3).round(); // More thorough cleanup
      final allKeys = [...reactionsMap.keys, ...repliesMap.keys, ...repostsMap.keys, ...zapsMap.keys];
      allKeys.shuffle();

      final keysToRemove = allKeys.take(removeCount);
      for (final key in keysToRemove) {
        reactionsMap.remove(key);
        repliesMap.remove(key);
        repostsMap.remove(key);
        zapsMap.remove(key);
      }
      debugPrint('[CacheService] Cleanup: removed $removeCount entries');
    }
  }

  void _monitorPerformance() {
    final totalEntries = reactionsMap.length + repliesMap.length + repostsMap.length + zapsMap.length;

    if (totalEntries > _criticalMemoryThreshold) {
      debugPrint('[CacheService] Critical memory usage detected, performing emergency cleanup');
      _performEmergencyCleanup();
    } else if (totalEntries > _highMemoryThreshold) {
      debugPrint('[CacheService] High memory usage detected, performing proactive cleanup');
      _performProactiveCleanup();
    }
  }

  void _performEmergencyCleanup() {
    // Keep only most recent 25% of cache
    final targetSize = (_maxCacheEntries * 0.25).round();
    final allKeys = [...reactionsMap.keys, ...repliesMap.keys, ...repostsMap.keys, ...zapsMap.keys];
    allKeys.shuffle();

    final keysToRemove = allKeys.skip(targetSize);
    for (final key in keysToRemove) {
      reactionsMap.remove(key);
      repliesMap.remove(key);
      repostsMap.remove(key);
      zapsMap.remove(key);
    }
    debugPrint('[CacheService] Emergency cleanup: cache reduced to $targetSize entries');
  }

  void _performProactiveCleanup() {
    // Remove 40% of cache proactively
    final totalEntries = reactionsMap.length + repliesMap.length + repostsMap.length + zapsMap.length;
    final removeCount = (totalEntries * 0.4).round();
    final allKeys = [...reactionsMap.keys, ...repliesMap.keys, ...repostsMap.keys, ...zapsMap.keys];
    allKeys.shuffle();

    final keysToRemove = allKeys.take(removeCount);
    for (final key in keysToRemove) {
      reactionsMap.remove(key);
      repliesMap.remove(key);
      repostsMap.remove(key);
      zapsMap.remove(key);
    }
    debugPrint('[CacheService] Proactive cleanup: removed $removeCount entries');
  }

  Future<void> initializeBoxes(String npub, String dataType) async {
    try {
      if (!_hiveManager.isInitialized) {
        await _hiveManager.initializeBoxes();
      }

      await _hiveManager.initializeNotificationBox(npub);

      if (dataType == 'profile') {
        Future.microtask(() async {
          await loadReactionsFromCache();
          await Future.delayed(Duration.zero);
          await loadRepliesFromCache();
          await Future.delayed(Duration.zero);
          await loadRepostsFromCache();
          await Future.delayed(Duration.zero);
          await loadZapsFromCache();
        });
      } else {
        Future.microtask(() async {
          await Future.wait([
            loadReactionsFromCache(),
            loadRepliesFromCache(),
            loadRepostsFromCache(),
            loadZapsFromCache(),
          ], eagerError: false);
        });
      }
    } catch (e) {
      debugPrint('[CacheService] Initialization error: $e');
    }
  }

  Future<void> loadReactionsFromCache() async {
    if (reactionsBox == null || !reactionsBox!.isOpen) return;

    Future.microtask(() async {
      try {
        final allReactions = reactionsBox!.values.cast<ReactionModel>().toList();
        if (allReactions.isEmpty) return;

        const batchSize = 100;
        for (int i = 0; i < allReactions.length; i += batchSize) {
          final batch = allReactions.skip(i).take(batchSize);

          for (var reaction in batch) {
            reactionsMap.putIfAbsent(reaction.targetEventId, () => []).add(reaction);
          }

          await Future.delayed(Duration.zero);
        }

        print('[CacheService] Loaded ${allReactions.length} reactions');
      } catch (e) {
        print('Error loading reactions from cache: $e');
      }
    });
  }

  Future<void> loadRepliesFromCache() async {
    if (repliesBox == null || !repliesBox!.isOpen) return;

    Future.microtask(() async {
      try {
        final allReplies = repliesBox!.values.cast<ReplyModel>().toList();
        if (allReplies.isEmpty) return;

        const batchSize = 100;
        for (int i = 0; i < allReplies.length; i += batchSize) {
          final batch = allReplies.skip(i).take(batchSize);

          for (var reply in batch) {
            repliesMap.putIfAbsent(reply.parentEventId, () => []).add(reply);
          }

          await Future.delayed(Duration.zero);
        }

        print('[CacheService] Loaded ${allReplies.length} replies');
      } catch (e) {
        print('Error loading replies from cache: $e');
      }
    });
  }

  Future<void> loadRepostsFromCache() async {
    if (repostsBox == null || !repostsBox!.isOpen) return;

    Future.microtask(() async {
      try {
        final allReposts = repostsBox!.values.cast<RepostModel>().toList();
        if (allReposts.isEmpty) return;

        const batchSize = 100;
        for (int i = 0; i < allReposts.length; i += batchSize) {
          final batch = allReposts.skip(i).take(batchSize);

          for (var repost in batch) {
            repostsMap.putIfAbsent(repost.originalNoteId, () => []);
            if (!repostsMap[repost.originalNoteId]!.any((r) => r.id == repost.id)) {
              repostsMap[repost.originalNoteId]!.add(repost);
            }
          }

          await Future.delayed(Duration.zero);
        }

        print('[CacheService] Loaded ${allReposts.length} reposts');
      } catch (e) {
        print('Error loading reposts from cache: $e');
      }
    });
  }

  Future<void> loadZapsFromCache() async {
    if (zapsBox == null || !zapsBox!.isOpen) return;

    Future.microtask(() async {
      try {
        final allZaps = zapsBox!.values.cast<ZapModel>().toList();
        if (allZaps.isEmpty) return;

        const batchSize = 100;
        for (int i = 0; i < allZaps.length; i += batchSize) {
          final batch = allZaps.skip(i).take(batchSize);

          for (var zap in batch) {
            zapsMap.putIfAbsent(zap.targetEventId, () => []);
            if (!zapsMap[zap.targetEventId]!.any((r) => r.id == zap.id)) {
              zapsMap[zap.targetEventId]!.add(zap);
            }
          }

          await Future.delayed(Duration.zero);
        }

        print('[CacheService] Loaded ${allZaps.length} zaps');
      } catch (e) {
        print('Error loading zaps from cache: $e');
      }
    });
  }

  Future<void> batchSaveNotes(List<NoteModel> notes) async {
    if (notesBox?.isOpen != true || notes.isEmpty) return;

    Future.microtask(() async {
      try {
        final notesToSave = notes.take(300).toList();
        final notesMap = <String, NoteModel>{};

        const batchSize = 50;
        for (int i = 0; i < notesToSave.length; i += batchSize) {
          final batch = notesToSave.skip(i).take(batchSize);

          for (final note in batch) {
            notesMap[note.id] = note;
          }

          if (notesMap.isNotEmpty) {
            await notesBox!.putAll(Map.from(notesMap));
            notesMap.clear();
          }

          await Future.delayed(Duration.zero);
        }

        print('[CacheService] Saved ${notesToSave.length} notes');
      } catch (e) {
        print('Error batch saving notes: $e');
      }
    });
  }

  Future<void> clearMemoryCache() async {
    // Clear in stages to prevent UI freeze
    Future.microtask(() {
      reactionsMap.clear();
    });

    await Future.delayed(const Duration(milliseconds: 10));
    Future.microtask(() {
      repliesMap.clear();
    });

    await Future.delayed(const Duration(milliseconds: 10));
    Future.microtask(() {
      repostsMap.clear();
      zapsMap.clear();
    });

    debugPrint('[CacheService] Memory cache cleared in stages');
  }

  Future<void> optimizeMemoryUsage() async {
    // Staged optimization to prevent blocking
    Future.microtask(() {
      _performBasicCleanup();
    });

    await Future.delayed(const Duration(milliseconds: 25));
    Future.microtask(() {
      reactionsMap.removeWhere((key, value) => value.isEmpty);
      repliesMap.removeWhere((key, value) => value.isEmpty);
    });

    await Future.delayed(const Duration(milliseconds: 25));
    Future.microtask(() {
      repostsMap.removeWhere((key, value) => value.isEmpty);
      zapsMap.removeWhere((key, value) => value.isEmpty);
    });
  }

  Future<void> handleMemoryPressure() async {
    // Pressure relief
    _performEmergencyCleanup();

    // Follow up with optimization
    await Future.delayed(const Duration(milliseconds: 50));
    await optimizeMemoryUsage();
  }

  Future<void> optimizeForProfileTransition() async {
    Future.microtask(() async {
      final now = DateTime.now();
      final cutoffTime = now.subtract(const Duration(minutes: 10));

      reactionsMap.removeWhere((eventId, reactions) {
        reactions.removeWhere((reaction) => reaction.fetchedAt.isBefore(cutoffTime));
        return reactions.isEmpty;
      });

      repliesMap.removeWhere((eventId, replies) {
        replies.removeWhere((reply) => reply.fetchedAt.isBefore(cutoffTime));
        return replies.isEmpty;
      });

      debugPrint('[CacheService] Profile transition optimization completed');
    });
  }

  /// Optimize cache for visible notes only - keep interactions for currently visible notes
  Future<void> optimizeForVisibleNotes(Set<String> visibleNoteIds) async {
    if (visibleNoteIds.isEmpty) return;

    Future.microtask(() async {
      final now = DateTime.now();
      final recentCutoff = now.subtract(const Duration(minutes: 5));
      final oldCutoff = now.subtract(const Duration(hours: 1));

      int removedReactions = 0;
      int removedReplies = 0;
      int removedReposts = 0;
      int removedZaps = 0;

      // Clean reactions - keep visible notes and recent interactions
      reactionsMap.removeWhere((eventId, reactions) {
        if (visibleNoteIds.contains(eventId)) return false; // Keep visible

        reactions.removeWhere((reaction) => reaction.fetchedAt.isBefore(oldCutoff));
        if (reactions.isEmpty) {
          removedReactions++;
          return true;
        }
        return false;
      });

      // Clean replies - more thorough for non-visible notes
      repliesMap.removeWhere((eventId, replies) {
        if (visibleNoteIds.contains(eventId)) return false; // Keep visible

        replies.removeWhere((reply) => reply.fetchedAt.isBefore(recentCutoff));
        if (replies.isEmpty) {
          removedReplies++;
          return true;
        }
        return false;
      });

      // Clean reposts - keep visible and recent
      repostsMap.removeWhere((eventId, reposts) {
        if (visibleNoteIds.contains(eventId)) return false; // Keep visible

        reposts.removeWhere((repost) => repost.repostTimestamp.isBefore(oldCutoff));
        if (reposts.isEmpty) {
          removedReposts++;
          return true;
        }
        return false;
      });

      // Clean zaps - keep visible and recent
      zapsMap.removeWhere((eventId, zaps) {
        if (visibleNoteIds.contains(eventId)) return false; // Keep visible

        zaps.removeWhere((zap) => zap.timestamp.isBefore(oldCutoff));
        if (zaps.isEmpty) {
          removedZaps++;
          return true;
        }
        return false;
      });

      debugPrint(
          '[CacheService] Visible notes optimization: Kept ${visibleNoteIds.length} visible, removed $removedReactions reactions, $removedReplies replies, $removedReposts reposts, $removedZaps zaps');
    });
  }

  Map<String, dynamic> getCacheStats() {
    final totalEntries = reactionsMap.length + repliesMap.length + repostsMap.length + zapsMap.length;

    return {
      'reactionsCount': reactionsMap.length,
      'repliesCount': repliesMap.length,
      'repostsCount': repostsMap.length,
      'zapsCount': zapsMap.length,
      'totalEntries': totalEntries,
      'maxEntries': _maxCacheEntries,
    };
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _performanceMonitorTimer?.cancel();
    clearMemoryCache();
  }

  void cleanupExpiredCache(Duration ttl) {
    final now = DateTime.now();
    final cutoffTime = now.subtract(ttl);

    reactionsMap.removeWhere((eventId, reactions) {
      reactions.removeWhere((reaction) => reaction.fetchedAt.isBefore(cutoffTime));
      return reactions.isEmpty;
    });

    repliesMap.removeWhere((eventId, replies) {
      replies.removeWhere((reply) => reply.fetchedAt.isBefore(cutoffTime));
      return replies.isEmpty;
    });
  }
}
