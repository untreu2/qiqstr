import 'dart:async';
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

  // Cache maps
  final Map<String, List<ReactionModel>> reactionsMap = {};
  final Map<String, List<ReplyModel>> repliesMap = {};
  final Map<String, List<RepostModel>> repostsMap = {};
  final Map<String, List<ZapModel>> zapsMap = {};

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

      // Process in batches to avoid blocking the UI
      const batchSize = 100;
      final Map<String, List<ReactionModel>> tempMap = {};
      
      for (int i = 0; i < allReactions.length; i += batchSize) {
        final batch = allReactions.skip(i).take(batchSize);
        
        for (var reaction in batch) {
          tempMap.putIfAbsent(reaction.targetEventId, () => []);
          if (!tempMap[reaction.targetEventId]!.any((r) => r.id == reaction.id)) {
            tempMap[reaction.targetEventId]!.add(reaction);
          }
        }
        
        // Yield control to prevent blocking
        if (i % (batchSize * 5) == 0) {
          await Future.delayed(Duration.zero);
        }
      }
      
      // Merge with existing cache
      for (final entry in tempMap.entries) {
        reactionsMap.putIfAbsent(entry.key, () => []);
        for (final reaction in entry.value) {
          if (!reactionsMap[entry.key]!.any((r) => r.id == reaction.id)) {
            reactionsMap[entry.key]!.add(reaction);
          }
        }
      }
    } catch (e) {
      print('Error loading reactions from cache: $e');
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
      // Limit notes to prevent memory issues
      final notesToSave = notes.take(200).toList();
      final notesMap = <String, NoteModel>{};
      
      // Process in batches to avoid blocking
      const batchSize = 50;
      for (int i = 0; i < notesToSave.length; i += batchSize) {
        final batch = notesToSave.skip(i).take(batchSize);
        
        for (final note in batch) {
          notesMap[note.id] = note;
        }
        
        // Yield control periodically
        if (i % (batchSize * 2) == 0) {
          await Future.delayed(Duration.zero);
        }
      }
      
      // Clear and save in one operation
      await notesBox!.clear();
      await notesBox!.putAll(notesMap);
    } catch (e) {
      print('Error batch saving notes: $e');
    }
  }

  // Add memory management methods
  Future<void> clearMemoryCache() async {
    reactionsMap.clear();
    repliesMap.clear();
    repostsMap.clear();
    zapsMap.clear();
  }

  Future<void> optimizeMemoryUsage() async {
    // Remove old entries to prevent memory bloat
    const maxEntriesPerType = 1000;
    
    if (reactionsMap.length > maxEntriesPerType) {
      final sortedKeys = reactionsMap.keys.toList()..shuffle();
      final keysToRemove = sortedKeys.take(reactionsMap.length - maxEntriesPerType);
      for (final key in keysToRemove) {
        reactionsMap.remove(key);
      }
    }
    
    if (repliesMap.length > maxEntriesPerType) {
      final sortedKeys = repliesMap.keys.toList()..shuffle();
      final keysToRemove = sortedKeys.take(repliesMap.length - maxEntriesPerType);
      for (final key in keysToRemove) {
        repliesMap.remove(key);
      }
    }
    
    if (repostsMap.length > maxEntriesPerType) {
      final sortedKeys = repostsMap.keys.toList()..shuffle();
      final keysToRemove = sortedKeys.take(repostsMap.length - maxEntriesPerType);
      for (final key in keysToRemove) {
        repostsMap.remove(key);
      }
    }
    
    if (zapsMap.length > maxEntriesPerType) {
      final sortedKeys = zapsMap.keys.toList()..shuffle();
      final keysToRemove = sortedKeys.take(zapsMap.length - maxEntriesPerType);
      for (final key in keysToRemove) {
        zapsMap.remove(key);
      }
    }
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