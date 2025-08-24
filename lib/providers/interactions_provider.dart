import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../models/repost_model.dart';
import '../models/zap_model.dart';

import 'package:rxdart/rxdart.dart';

class InteractionsProvider extends ChangeNotifier {
  static InteractionsProvider? _instance;
  static InteractionsProvider get instance => _instance ??= InteractionsProvider._internal();

  InteractionsProvider._internal();

  final _reactionStreamController = StreamController<String>.broadcast();
  final _replyStreamController = StreamController<String>.broadcast();
  final _repostStreamController = StreamController<String>.broadcast();
  final _zapStreamController = StreamController<String>.broadcast();

  Stream<String> get reactionsStream => _reactionStreamController.stream.debounceTime(const Duration(milliseconds: 300));
  Stream<String> get repliesStream => _replyStreamController.stream.debounceTime(const Duration(milliseconds: 300));
  Stream<String> get repostsStream => _repostStreamController.stream.debounceTime(const Duration(milliseconds: 300));
  Stream<String> get zapsStream => _zapStreamController.stream.debounceTime(const Duration(milliseconds: 300));

  final Map<String, List<ReactionModel>> _reactionsByNote = {};
  final Map<String, List<ReplyModel>> _repliesByNote = {};
  final Map<String, List<RepostModel>> _repostsByNote = {};
  final Map<String, List<ZapModel>> _zapsByNote = {};

  final Map<String, Set<String>> _userReactions = {};
  final Map<String, Set<String>> _userReplies = {};
  final Map<String, Set<String>> _userReposts = {};
  final Map<String, Set<String>> _userZaps = {};

  bool _isInitialized = false;

  Box<ReactionModel>? _reactionsBox;
  Box<ReplyModel>? _repliesBox;
  Box<RepostModel>? _repostsBox;
  Box<ZapModel>? _zapsBox;

  bool get isInitialized => _isInitialized;

  Future<void> initialize(String npub, {String dataType = 'Feed'}) async {
    if (_isInitialized) return;

    try {
      _reactionsBox = await Hive.openBox<ReactionModel>('reactions');
      _repliesBox = await Hive.openBox<ReplyModel>('replies');
      _repostsBox = await Hive.openBox<RepostModel>('reposts');
      _zapsBox = await Hive.openBox<ZapModel>('zaps');

      await _loadInteractionsFromHive();

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[InteractionsProvider] Initialization error: $e');
    }
  }

  Future<void> _loadInteractionsFromHive() async {
    if (_reactionsBox != null) {
      for (final reaction in _reactionsBox!.values) {
        _addReactionToCache(reaction);
      }
    }

    if (_repliesBox != null) {
      for (final reply in _repliesBox!.values) {
        _addReplyToCache(reply);
      }
    }

    if (_repostsBox != null) {
      for (final repost in _repostsBox!.values) {
        _addRepostToCache(repost);
      }
    }

    if (_zapsBox != null) {
      for (final zap in _zapsBox!.values) {
        _addZapToCache(zap);
      }
    }
  }

  void _addReactionToCache(ReactionModel reaction) {
    _reactionsByNote.putIfAbsent(reaction.targetEventId, () => []);
    if (!_reactionsByNote[reaction.targetEventId]!.any((r) => r.id == reaction.id)) {
      _reactionsByNote[reaction.targetEventId]!.add(reaction);

      _userReactions.putIfAbsent(reaction.author, () => {});
      _userReactions[reaction.author]!.add(reaction.targetEventId);
    }
  }

  void _addReplyToCache(ReplyModel reply) {
    _repliesByNote.putIfAbsent(reply.parentEventId, () => []);
    if (!_repliesByNote[reply.parentEventId]!.any((r) => r.id == reply.id)) {
      _repliesByNote[reply.parentEventId]!.add(reply);

      _userReplies.putIfAbsent(reply.author, () => {});
      _userReplies[reply.author]!.add(reply.parentEventId);
    }
  }

  void _addRepostToCache(RepostModel repost) {
    _repostsByNote.putIfAbsent(repost.originalNoteId, () => []);
    if (!_repostsByNote[repost.originalNoteId]!.any((r) => r.id == repost.id)) {
      _repostsByNote[repost.originalNoteId]!.add(repost);

      _userReposts.putIfAbsent(repost.repostedBy, () => {});
      _userReposts[repost.repostedBy]!.add(repost.originalNoteId);
    }
  }

  void _addZapToCache(ZapModel zap) {
    _zapsByNote.putIfAbsent(zap.targetEventId, () => []);
    if (!_zapsByNote[zap.targetEventId]!.any((z) => z.id == zap.id)) {
      _zapsByNote[zap.targetEventId]!.add(zap);

      _userZaps.putIfAbsent(zap.sender, () => {});
      _userZaps[zap.sender]!.add(zap.targetEventId);
    }
  }

  List<ReactionModel> getReactionsForNote(String noteId) => _reactionsByNote[noteId] ?? [];
  List<ReplyModel> getRepliesForNote(String noteId) => _repliesByNote[noteId] ?? [];
  List<RepostModel> getRepostsForNote(String noteId) => _repostsByNote[noteId] ?? [];
  List<ZapModel> getZapsForNote(String noteId) => _zapsByNote[noteId] ?? [];
  int getReactionCount(String noteId) => _reactionsByNote[noteId]?.length ?? 0;
  int getReplyCount(String noteId) => _repliesByNote[noteId]?.length ?? 0;
  int getRepostCount(String noteId) => _repostsByNote[noteId]?.length ?? 0;
  int getZapAmount(String noteId) => _zapsByNote[noteId]?.fold<int>(0, (sum, zap) => sum + zap.amount) ?? 0;
  bool hasUserReacted(String userId, String noteId) => _userReactions[userId]?.contains(noteId) ?? false;
  bool hasUserReplied(String userId, String noteId) => _userReplies[userId]?.contains(noteId) ?? false;
  bool hasUserReposted(String userId, String noteId) => _userReposts[userId]?.contains(noteId) ?? false;
  bool hasUserZapped(String userId, String noteId) => _userZaps[userId]?.contains(noteId) ?? false;

  Future<void> addReaction(ReactionModel reaction) async {
    if (!reaction.id.startsWith('optimistic_')) {
      _reactionsByNote[reaction.targetEventId]?.removeWhere((r) => r.author == reaction.author && r.id.startsWith('optimistic_'));
    }
    _addReactionToCache(reaction);
    try {
      await _reactionsBox?.put(reaction.id, reaction);
      _reactionStreamController.add(reaction.targetEventId);
    } catch (e) {
      debugPrint('[InteractionsProvider] Error saving reaction: $e');
    }
  }

  Future<void> addReply(ReplyModel reply) async {
    _addReplyToCache(reply);
    try {
      await _repliesBox?.put(reply.id, reply);
      _replyStreamController.add(reply.parentEventId);
    } catch (e) {
      debugPrint('[InteractionsProvider] Error saving reply: $e');
    }
  }

  Future<void> addRepost(RepostModel repost) async {
    if (!repost.id.startsWith('optimistic_')) {
      _repostsByNote[repost.originalNoteId]?.removeWhere((r) => r.repostedBy == repost.repostedBy && r.id.startsWith('optimistic_'));
    }
    _addRepostToCache(repost);
    try {
      await _repostsBox?.put(repost.id, repost);
      _repostStreamController.add(repost.originalNoteId);
    } catch (e) {
      debugPrint('[InteractionsProvider] Error saving repost: $e');
    }
  }

  Future<void> addZap(ZapModel zap) async {
    _addZapToCache(zap);
    try {
      await _zapsBox?.put(zap.id, zap);
      _zapStreamController.add(zap.targetEventId);
    } catch (e) {
      debugPrint('[InteractionsProvider] Error saving zap: $e');
    }
  }

  Future<void> addReactions(List<ReactionModel> reactions) async {
    if (reactions.isEmpty) return;

    final noteIdsToUpdate = <String>{};
    for (final reaction in reactions) {
      _addReactionToCache(reaction);
      noteIdsToUpdate.add(reaction.targetEventId);
    }

    try {
      final reactionsMap = {for (var r in reactions) r.id: r};
      await _reactionsBox?.putAll(reactionsMap);
    } catch (e) {
      debugPrint('[InteractionsProvider] Error batch saving reactions: $e');
    }

    for (var id in noteIdsToUpdate) {
      _reactionStreamController.add(id);
    }
  }

  Future<void> addReplies(List<ReplyModel> replies) async {
    if (replies.isEmpty) return;
    final noteIdsToUpdate = <String>{};
    for (final reply in replies) {
      _addReplyToCache(reply);
      noteIdsToUpdate.add(reply.parentEventId);
    }
    try {
      final repliesMap = {for (var r in replies) r.id: r};
      await _repliesBox?.putAll(repliesMap);
    } catch (e) {
      debugPrint('[InteractionsProvider] Error batch saving replies: $e');
    }
    for (var id in noteIdsToUpdate) {
      _replyStreamController.add(id);
    }
  }

  Future<void> addReposts(List<RepostModel> reposts) async {
    if (reposts.isEmpty) return;
    final noteIdsToUpdate = <String>{};
    for (final repost in reposts) {
      _addRepostToCache(repost);
      noteIdsToUpdate.add(repost.originalNoteId);
    }
    try {
      final repostsMap = {for (var r in reposts) r.id: r};
      await _repostsBox?.putAll(repostsMap);
    } catch (e) {
      debugPrint('[InteractionsProvider] Error batch saving reposts: $e');
    }
    for (var id in noteIdsToUpdate) {
      _repostStreamController.add(id);
    }
  }

  Future<void> addZaps(List<ZapModel> zaps) async {
    if (zaps.isEmpty) return;
    final noteIdsToUpdate = <String>{};
    for (final zap in zaps) {
      _addZapToCache(zap);
      noteIdsToUpdate.add(zap.targetEventId);
    }
    try {
      final zapsMap = {for (var z in zaps) z.id: z};
      await _zapsBox?.putAll(zapsMap);
    } catch (e) {
      debugPrint('[InteractionsProvider] Error batch saving zaps: $e');
    }
    for (var id in noteIdsToUpdate) {
      _zapStreamController.add(id);
    }
  }

  void updateReactions(String noteId, List<ReactionModel> reactions) {
    _reactionsByNote[noteId] = reactions;
    for (final reaction in reactions) {
      _userReactions.putIfAbsent(reaction.author, () => {}).add(reaction.targetEventId);
    }
    _reactionStreamController.add(noteId);
  }

  void updateReplies(String noteId, List<ReplyModel> replies) {
    _repliesByNote[noteId] = replies;
    for (final reply in replies) {
      _userReplies.putIfAbsent(reply.author, () => {}).add(reply.parentEventId);
    }
    _replyStreamController.add(noteId);
  }

  void updateReposts(String noteId, List<RepostModel> reposts) {
    _repostsByNote[noteId] = reposts;
    for (final repost in reposts) {
      _userReposts.putIfAbsent(repost.repostedBy, () => {}).add(repost.originalNoteId);
    }
    _repostStreamController.add(noteId);
  }

  void updateZaps(String noteId, List<ZapModel> zaps) {
    _zapsByNote[noteId] = zaps;
    for (final zap in zaps) {
      _userZaps.putIfAbsent(zap.sender, () => {}).add(zap.targetEventId);
    }
    _zapStreamController.add(noteId);
  }

  void removeReaction(String reactionId, String noteId, String userId) {
    _reactionsByNote[noteId]?.removeWhere((r) => r.id == reactionId);
    _userReactions[userId]?.remove(noteId);
    _reactionsBox?.delete(reactionId);
    _reactionStreamController.add(noteId);
  }

  void removeRepost(String repostId, String noteId, String userId) {
    _repostsByNote[noteId]?.removeWhere((r) => r.id == repostId);
    _userReposts[userId]?.remove(noteId);
    _repostsBox?.delete(repostId);
    _repostStreamController.add(noteId);
  }

  void addOptimisticReaction(String noteId, String userId) {
    final optimisticReaction = ReactionModel(
      id: 'optimistic_${DateTime.now().millisecondsSinceEpoch}',
      author: userId,
      content: '+',
      targetEventId: noteId,
      timestamp: DateTime.now(),
      fetchedAt: DateTime.now(),
    );
    _addReactionToCache(optimisticReaction);
    _reactionStreamController.add(noteId);
  }

  void addOptimisticRepost(String noteId, String userId) {
    final optimisticRepost = RepostModel(
      id: 'optimistic_${DateTime.now().millisecondsSinceEpoch}',
      originalNoteId: noteId,
      repostedBy: userId,
      repostTimestamp: DateTime.now(),
    );
    _addRepostToCache(optimisticRepost);
    _repostStreamController.add(noteId);
  }

  void removeOptimisticReaction(String noteId, String userId) {
    _reactionsByNote[noteId]?.removeWhere((r) => r.author == userId && r.id.startsWith('optimistic_'));
    _userReactions[userId]?.remove(noteId);
    _reactionStreamController.add(noteId);
  }

  void removeOptimisticRepost(String noteId, String userId) {
    _repostsByNote[noteId]?.removeWhere((r) => r.repostedBy == userId && r.id.startsWith('optimistic_'));
    _userReposts[userId]?.remove(noteId);
    _repostStreamController.add(noteId);
  }

  void clearCache() {
    _reactionsByNote.clear();
    _repliesByNote.clear();
    _repostsByNote.clear();
    _zapsByNote.clear();
    _userReactions.clear();
    _userReplies.clear();
    _userReposts.clear();
    _userZaps.clear();
    notifyListeners();
  }

  Map<String, dynamic> getStats() {
    return {
      'totalReactions': _reactionsByNote.values.fold<int>(0, (sum, list) => sum + list.length),
      'totalReplies': _repliesByNote.values.fold<int>(0, (sum, list) => sum + list.length),
      'totalReposts': _repostsByNote.values.fold<int>(0, (sum, list) => sum + list.length),
      'totalZaps': _zapsByNote.values.fold<int>(0, (sum, list) => sum + list.length),
      'notesWithReactions': _reactionsByNote.length,
      'notesWithReplies': _repliesByNote.length,
      'notesWithReposts': _repostsByNote.length,
      'notesWithZaps': _zapsByNote.length,
      'isInitialized': _isInitialized,
    };
  }

  @override
  void dispose() {
    _reactionStreamController.close();
    _replyStreamController.close();
    _repostStreamController.close();
    _zapStreamController.close();
    _reactionsBox?.close();
    _repliesBox?.close();
    _repostsBox?.close();
    _zapsBox?.close();
    super.dispose();
  }
}
