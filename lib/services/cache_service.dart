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
    
    final allReactions = reactionsBox!.values.cast<ReactionModel>().toList();
    if (allReactions.isEmpty) return;

    for (var reaction in allReactions) {
      reactionsMap.putIfAbsent(reaction.targetEventId, () => []);
      if (!reactionsMap[reaction.targetEventId]!.any((r) => r.id == reaction.id)) {
        reactionsMap[reaction.targetEventId]!.add(reaction);
      }
    }
  }

  Future<void> loadRepliesFromCache() async {
    if (repliesBox == null || !repliesBox!.isOpen) return;
    
    final allReplies = repliesBox!.values.cast<ReplyModel>().toList();
    if (allReplies.isEmpty) return;

    for (var reply in allReplies) {
      repliesMap.putIfAbsent(reply.parentEventId, () => []);
      if (!repliesMap[reply.parentEventId]!.any((r) => r.id == reply.id)) {
        repliesMap[reply.parentEventId]!.add(reply);
      }
    }
  }

  Future<void> loadRepostsFromCache() async {
    if (repostsBox == null || !repostsBox!.isOpen) return;
    
    final allReposts = repostsBox!.values.cast<RepostModel>().toList();
    if (allReposts.isEmpty) return;

    for (var repost in allReposts) {
      repostsMap.putIfAbsent(repost.originalNoteId, () => []);
      if (!repostsMap[repost.originalNoteId]!.any((r) => r.id == repost.id)) {
        repostsMap[repost.originalNoteId]!.add(repost);
      }
    }
  }

  Future<void> loadZapsFromCache() async {
    if (zapsBox == null || !zapsBox!.isOpen) return;
    
    final allZaps = zapsBox!.values.cast<ZapModel>().toList();
    if (allZaps.isEmpty) return;

    for (var zap in allZaps) {
      zapsMap.putIfAbsent(zap.targetEventId, () => []);
      if (!zapsMap[zap.targetEventId]!.any((r) => r.id == zap.id)) {
        zapsMap[zap.targetEventId]!.add(zap);
      }
    }
  }

  Future<void> batchSaveNotes(List<NoteModel> notes) async {
    if (notesBox?.isOpen != true || notes.isEmpty) return;
    
    final notesToSave = notes.take(150).toList();
    final notesMap = <String, NoteModel>{};
    
    for (final note in notesToSave) {
      notesMap[note.id] = note;
    }
    
    await notesBox!.clear();
    await notesBox!.putAll(notesMap);
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