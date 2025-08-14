import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../models/repost_model.dart';
import '../models/zap_model.dart';

class InteractionsProvider extends ChangeNotifier {
  static InteractionsProvider? _instance;
  static InteractionsProvider get instance => _instance ??= InteractionsProvider._internal();

  InteractionsProvider._internal();

  // Data maps
  final Map<String, List<ReactionModel>> _reactionsByNote = {};
  final Map<String, List<ReplyModel>> _repliesByNote = {};
  final Map<String, List<RepostModel>> _repostsByNote = {};
  final Map<String, List<ZapModel>> _zapsByNote = {};

  // User interaction tracking
  final Map<String, Set<String>> _userReactions = {}; // userId -> Set of noteIds
  final Map<String, Set<String>> _userReplies = {};
  final Map<String, Set<String>> _userReposts = {};
  final Map<String, Set<String>> _userZaps = {};

  bool _isInitialized = false;

  // Hive boxes - single boxes for all interactions
  Box<ReactionModel>? _reactionsBox;
  Box<ReplyModel>? _repliesBox;
  Box<RepostModel>? _repostsBox;
  Box<ZapModel>? _zapsBox;

  // Getters
  bool get isInitialized => _isInitialized;

  Future<void> initialize(String npub, {String dataType = 'Feed'}) async {
    if (_isInitialized) return;

    try {
      // Open single Hive boxes for all interactions
      _reactionsBox = await Hive.openBox<ReactionModel>('reactions');
      _repliesBox = await Hive.openBox<ReplyModel>('replies');
      _repostsBox = await Hive.openBox<RepostModel>('reposts');
      _zapsBox = await Hive.openBox<ZapModel>('zaps');

      // Load existing data from Hive
      await _loadInteractionsFromHive();

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[InteractionsProvider] Initialization error: $e');
    }
  }

  Future<void> _loadInteractionsFromHive() async {
    // Load reactions
    if (_reactionsBox != null) {
      for (final reaction in _reactionsBox!.values) {
        _addReactionToCache(reaction);
      }
    }

    // Load replies
    if (_repliesBox != null) {
      for (final reply in _repliesBox!.values) {
        _addReplyToCache(reply);
      }
    }

    // Load reposts
    if (_repostsBox != null) {
      for (final repost in _repostsBox!.values) {
        _addRepostToCache(repost);
      }
    }

    // Load zaps
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

      // Track user reaction
      _userReactions.putIfAbsent(reaction.author, () => {});
      _userReactions[reaction.author]!.add(reaction.targetEventId);
    }
  }

  void _addReplyToCache(ReplyModel reply) {
    _repliesByNote.putIfAbsent(reply.parentEventId, () => []);
    if (!_repliesByNote[reply.parentEventId]!.any((r) => r.id == reply.id)) {
      _repliesByNote[reply.parentEventId]!.add(reply);

      // Track user reply
      _userReplies.putIfAbsent(reply.author, () => {});
      _userReplies[reply.author]!.add(reply.parentEventId);
    }
  }

  void _addRepostToCache(RepostModel repost) {
    _repostsByNote.putIfAbsent(repost.originalNoteId, () => []);
    if (!_repostsByNote[repost.originalNoteId]!.any((r) => r.id == repost.id)) {
      _repostsByNote[repost.originalNoteId]!.add(repost);

      // Track user repost
      _userReposts.putIfAbsent(repost.repostedBy, () => {});
      _userReposts[repost.repostedBy]!.add(repost.originalNoteId);
    }
  }

  void _addZapToCache(ZapModel zap) {
    _zapsByNote.putIfAbsent(zap.targetEventId, () => []);
    if (!_zapsByNote[zap.targetEventId]!.any((z) => z.id == zap.id)) {
      _zapsByNote[zap.targetEventId]!.add(zap);

      // Track user zap
      _userZaps.putIfAbsent(zap.sender, () => {});
      _userZaps[zap.sender]!.add(zap.targetEventId);
    }
  }

  // Getters for interactions
  List<ReactionModel> getReactionsForNote(String noteId) {
    return _reactionsByNote[noteId] ?? [];
  }

  List<ReplyModel> getRepliesForNote(String noteId) {
    return _repliesByNote[noteId] ?? [];
  }

  List<RepostModel> getRepostsForNote(String noteId) {
    return _repostsByNote[noteId] ?? [];
  }

  List<ZapModel> getZapsForNote(String noteId) {
    return _zapsByNote[noteId] ?? [];
  }

  // Count getters
  int getReactionCount(String noteId) {
    return _reactionsByNote[noteId]?.length ?? 0;
  }

  int getReplyCount(String noteId) {
    return _repliesByNote[noteId]?.length ?? 0;
  }

  int getRepostCount(String noteId) {
    return _repostsByNote[noteId]?.length ?? 0;
  }

  int getZapAmount(String noteId) {
    return _zapsByNote[noteId]?.fold<int>(0, (sum, zap) => sum + zap.amount) ?? 0;
  }

  // User interaction checks
  bool hasUserReacted(String userId, String noteId) {
    return _userReactions[userId]?.contains(noteId) ?? false;
  }

  bool hasUserReplied(String userId, String noteId) {
    return _userReplies[userId]?.contains(noteId) ?? false;
  }

  bool hasUserReposted(String userId, String noteId) {
    return _userReposts[userId]?.contains(noteId) ?? false;
  }

  bool hasUserZapped(String userId, String noteId) {
    return _userZaps[userId]?.contains(noteId) ?? false;
  }

  // Add new interactions
  Future<void> addReaction(ReactionModel reaction) async {
    _addReactionToCache(reaction);

    try {
      await _reactionsBox?.put(reaction.id, reaction);
    } catch (e) {
      debugPrint('[InteractionsProvider] Error saving reaction: $e');
    }

    notifyListeners();
  }

  Future<void> addReply(ReplyModel reply) async {
    _addReplyToCache(reply);

    try {
      await _repliesBox?.put(reply.id, reply);
    } catch (e) {
      debugPrint('[InteractionsProvider] Error saving reply: $e');
    }

    notifyListeners();
  }

  Future<void> addRepost(RepostModel repost) async {
    _addRepostToCache(repost);

    try {
      await _repostsBox?.put(repost.id, repost);
    } catch (e) {
      debugPrint('[InteractionsProvider] Error saving repost: $e');
    }

    notifyListeners();
  }

  Future<void> addZap(ZapModel zap) async {
    _addZapToCache(zap);

    try {
      await _zapsBox?.put(zap.id, zap);
    } catch (e) {
      debugPrint('[InteractionsProvider] Error saving zap: $e');
    }

    notifyListeners();
  }

  // Batch operations
  Future<void> addReactions(List<ReactionModel> reactions) async {
    for (final reaction in reactions) {
      _addReactionToCache(reaction);
    }

    try {
      final reactionsMap = {for (var r in reactions) r.id: r};
      await _reactionsBox?.putAll(reactionsMap);
    } catch (e) {
      debugPrint('[InteractionsProvider] Error batch saving reactions: $e');
    }

    notifyListeners();
  }

  Future<void> addReplies(List<ReplyModel> replies) async {
    for (final reply in replies) {
      _addReplyToCache(reply);
    }

    try {
      final repliesMap = {for (var r in replies) r.id: r};
      await _repliesBox?.putAll(repliesMap);
    } catch (e) {
      debugPrint('[InteractionsProvider] Error batch saving replies: $e');
    }

    notifyListeners();
  }

  Future<void> addReposts(List<RepostModel> reposts) async {
    for (final repost in reposts) {
      _addRepostToCache(repost);
    }

    try {
      final repostsMap = {for (var r in reposts) r.id: r};
      await _repostsBox?.putAll(repostsMap);
    } catch (e) {
      debugPrint('[InteractionsProvider] Error batch saving reposts: $e');
    }

    notifyListeners();
  }

  Future<void> addZaps(List<ZapModel> zaps) async {
    for (final zap in zaps) {
      _addZapToCache(zap);
    }

    try {
      final zapsMap = {for (var z in zaps) z.id: z};
      await _zapsBox?.putAll(zapsMap);
    } catch (e) {
      debugPrint('[InteractionsProvider] Error batch saving zaps: $e');
    }

    notifyListeners();
  }

  // Update methods for DataService integration
  void updateReactions(String noteId, List<ReactionModel> reactions) {
    _reactionsByNote[noteId] = reactions;

    // Update user tracking
    for (final reaction in reactions) {
      _userReactions.putIfAbsent(reaction.author, () => {});
      _userReactions[reaction.author]!.add(reaction.targetEventId);
    }

    notifyListeners();
  }

  void updateReplies(String noteId, List<ReplyModel> replies) {
    _repliesByNote[noteId] = replies;

    // Update user tracking
    for (final reply in replies) {
      _userReplies.putIfAbsent(reply.author, () => {});
      _userReplies[reply.author]!.add(reply.parentEventId);
    }

    notifyListeners();
  }

  void updateReposts(String noteId, List<RepostModel> reposts) {
    _repostsByNote[noteId] = reposts;

    // Update user tracking
    for (final repost in reposts) {
      _userReposts.putIfAbsent(repost.repostedBy, () => {});
      _userReposts[repost.repostedBy]!.add(repost.originalNoteId);
    }

    notifyListeners();
  }

  void updateZaps(String noteId, List<ZapModel> zaps) {
    _zapsByNote[noteId] = zaps;

    // Update user tracking
    for (final zap in zaps) {
      _userZaps.putIfAbsent(zap.sender, () => {});
      _userZaps[zap.sender]!.add(zap.targetEventId);
    }

    notifyListeners();
  }

  // Remove interactions
  void removeReaction(String reactionId, String noteId, String userId) {
    _reactionsByNote[noteId]?.removeWhere((r) => r.id == reactionId);
    _userReactions[userId]?.remove(noteId);
    _reactionsBox?.delete(reactionId);
    notifyListeners();
  }

  void removeRepost(String repostId, String noteId, String userId) {
    _repostsByNote[noteId]?.removeWhere((r) => r.id == repostId);
    _userReposts[userId]?.remove(noteId);
    _repostsBox?.delete(repostId);
    notifyListeners();
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
    _reactionsBox?.close();
    _repliesBox?.close();
    _repostsBox?.close();
    _zapsBox?.close();
    super.dispose();
  }
}
