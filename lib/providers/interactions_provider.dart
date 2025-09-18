import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../models/repost_model.dart';
import '../models/zap_model.dart';
import '../services/hive_manager.dart';
import '../services/data_service.dart';

import 'package:rxdart/rxdart.dart';

class InteractionsProvider extends ChangeNotifier {
  static InteractionsProvider? _instance;
  static InteractionsProvider get instance => _instance ??= InteractionsProvider._internal();

  InteractionsProvider._internal();

  Timer? _periodicTimer;
  Set<String> _visibleNoteIds = {};

  final _reactionStreamController = StreamController<String>.broadcast();
  final _replyStreamController = StreamController<String>.broadcast();
  final _repostStreamController = StreamController<String>.broadcast();
  final _zapStreamController = StreamController<String>.broadcast();

  Stream<String> get reactionsStream => _reactionStreamController.stream.debounceTime(const Duration(milliseconds: 50));
  Stream<String> get repliesStream => _replyStreamController.stream.debounceTime(const Duration(milliseconds: 50));
  Stream<String> get repostsStream => _repostStreamController.stream.debounceTime(const Duration(milliseconds: 50));
  Stream<String> get zapsStream => _zapStreamController.stream.debounceTime(const Duration(milliseconds: 50));

  final Map<String, List<ReactionModel>> _reactionsByNote = {};
  final Map<String, List<ReplyModel>> _repliesByNote = {};
  final Map<String, List<RepostModel>> _repostsByNote = {};
  final Map<String, List<ZapModel>> _zapsByNote = {};

  final Map<String, Set<String>> _userReactions = {};
  final Map<String, Set<String>> _userReplies = {};
  final Map<String, Set<String>> _userReposts = {};
  final Map<String, Set<String>> _userZaps = {};

  bool _isInitialized = false;
  final HiveManager _hiveManager = HiveManager.instance;

  final Set<String> _fetchedInteractionNotes = {};
  final Map<String, DateTime> _lastManualFetch = {};

  Box<ReactionModel>? get _reactionsBox => _hiveManager.reactionsBox;
  Box<ReplyModel>? get _repliesBox => _hiveManager.repliesBox;
  Box<RepostModel>? get _repostsBox => _hiveManager.repostsBox;
  Box<ZapModel>? get _zapsBox => _hiveManager.zapsBox;

  bool get isInitialized => _isInitialized;

  Future<void> initialize(String npub, {String dataType = 'Feed'}) async {
    if (_isInitialized) return;

    try {
      if (!_hiveManager.isInitialized) {
        await _hiveManager.initializeBoxes();
      }

      await _loadInteractionsFromHive();

      _isInitialized = true;
      Timer(const Duration(seconds: 1), () {
        notifyListeners();
        _startPeriodicUpdates();
      });
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
  int getZapAmount(String noteId) =>
      _zapsByNote[noteId]?.where((zap) => !zap.id.startsWith('optimistic_')).fold<int>(0, (sum, zap) => sum + zap.amount) ?? 0;

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
      if (_visibleNoteIds.contains(reaction.targetEventId)) {
        _reactionStreamController.add(reaction.targetEventId);
      }
    } catch (e) {
      debugPrint('[InteractionsProvider] Error saving reaction: $e');
    }
  }

  Future<void> addReply(ReplyModel reply) async {
    _addReplyToCache(reply);
    try {
      await _repliesBox?.put(reply.id, reply);
      if (_visibleNoteIds.contains(reply.parentEventId)) {
        _replyStreamController.add(reply.parentEventId);
      }
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
      if (_visibleNoteIds.contains(repost.originalNoteId)) {
        _repostStreamController.add(repost.originalNoteId);
      }
    } catch (e) {
      debugPrint('[InteractionsProvider] Error saving repost: $e');
    }
  }

  Future<void> addZap(ZapModel zap) async {
    if (!zap.id.startsWith('optimistic_')) {
      _zapsByNote[zap.targetEventId]?.removeWhere((z) => z.sender == zap.sender && z.id.startsWith('optimistic_'));
    }

    _addZapToCache(zap);
    try {
      await _zapsBox?.put(zap.id, zap);
      if (_visibleNoteIds.contains(zap.targetEventId)) {
        _zapStreamController.add(zap.targetEventId);
      }
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

    notifyListeners();
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

    notifyListeners();
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

    notifyListeners();
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

    notifyListeners();
  }

  void updateVisibleNotes(Set<String> visibleNoteIds) {
    final oldVisibleCount = _visibleNoteIds.length;
    _visibleNoteIds = visibleNoteIds;

    if ((visibleNoteIds.length - oldVisibleCount).abs() > 3) {
      print('[InteractionsProvider] Visible notes updated: ${visibleNoteIds.length} notes tracked for interactions');
    }
  }

  Map<String, dynamic> getVisibleInteractionsData() {
    final visibleReactions = <String, List<ReactionModel>>{};
    final visibleReplies = <String, List<ReplyModel>>{};
    final visibleReposts = <String, List<RepostModel>>{};
    final visibleZaps = <String, List<ZapModel>>{};

    for (final noteId in _visibleNoteIds) {
      if (_reactionsByNote.containsKey(noteId)) {
        visibleReactions[noteId] = _reactionsByNote[noteId]!;
      }
      if (_repliesByNote.containsKey(noteId)) {
        visibleReplies[noteId] = _repliesByNote[noteId]!;
      }
      if (_repostsByNote.containsKey(noteId)) {
        visibleReposts[noteId] = _repostsByNote[noteId]!;
      }
      if (_zapsByNote.containsKey(noteId)) {
        visibleZaps[noteId] = _zapsByNote[noteId]!;
      }
    }

    return {
      'reactions': visibleReactions,
      'replies': visibleReplies,
      'reposts': visibleReposts,
      'zaps': visibleZaps,
      'visibleNotesCount': _visibleNoteIds.length,
    };
  }

  void updateReactions(String noteId, List<ReactionModel> reactions) {
    _reactionsByNote[noteId] = reactions;
    for (final reaction in reactions) {
      _userReactions.putIfAbsent(reaction.author, () => {}).add(reaction.targetEventId);
    }
    if (_visibleNoteIds.contains(noteId)) {
      _reactionStreamController.add(noteId);
    }
  }

  void updateReplies(String noteId, List<ReplyModel> replies) {
    _repliesByNote[noteId] = replies;
    for (final reply in replies) {
      _userReplies.putIfAbsent(reply.author, () => {}).add(reply.parentEventId);
    }
    if (_visibleNoteIds.contains(noteId)) {
      _replyStreamController.add(noteId);
    }
  }

  void updateReposts(String noteId, List<RepostModel> reposts) {
    _repostsByNote[noteId] = reposts;
    for (final repost in reposts) {
      _userReposts.putIfAbsent(repost.repostedBy, () => {}).add(repost.originalNoteId);
    }
    if (_visibleNoteIds.contains(noteId)) {
      _repostStreamController.add(noteId);
    }
  }

  void updateZaps(String noteId, List<ZapModel> zaps) {
    final realZaps = zaps.where((z) => !z.id.startsWith('optimistic_')).toList();
    final optimisticZaps = _zapsByNote[noteId]?.where((z) => z.id.startsWith('optimistic_')) ?? [];

    final filteredOptimisticZaps = optimisticZaps.where((optimistic) {
      return !realZaps.any((real) => real.sender == optimistic.sender);
    }).toList();

    _zapsByNote[noteId] = [...realZaps, ...filteredOptimisticZaps];

    for (final zap in _zapsByNote[noteId]!) {
      _userZaps.putIfAbsent(zap.sender, () => {}).add(zap.targetEventId);
    }
    if (_visibleNoteIds.contains(noteId)) {
      _zapStreamController.add(noteId);
    }
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

  void addOptimisticZap(String noteId, String userId, int amount) {
    _zapsByNote[noteId]?.removeWhere((z) => z.sender == userId && z.id.startsWith('optimistic_'));
    _userZaps[userId]?.remove(noteId);

    final optimisticZap = ZapModel(
      id: 'optimistic_${DateTime.now().millisecondsSinceEpoch}',
      sender: userId,
      recipient: '',
      targetEventId: noteId,
      timestamp: DateTime.now(),
      bolt11: '',
      comment: null,
      amount: amount,
    );
    _addZapToCache(optimisticZap);
    _zapStreamController.add(noteId);
  }

  void removeOptimisticZap(String noteId, String userId) {
    final hasOptimistic = _zapsByNote[noteId]?.any((z) => z.sender == userId && z.id.startsWith('optimistic_')) ?? false;
    if (hasOptimistic) {
      _zapsByNote[noteId]?.removeWhere((z) => z.sender == userId && z.id.startsWith('optimistic_'));
      _userZaps[userId]?.remove(noteId);
      _zapStreamController.add(noteId);
    }
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

  Future<void> fetchInteractionsForNote(String noteId) async {
    await fetchInteractionsForNotes([noteId]);
  }

  Future<void> fetchInteractionsForNotes(List<String> noteIds) async {
    if (!_isInitialized || noteIds.isEmpty) return;

    final now = DateTime.now();
    final notesToFetch = <String>[];

    for (final noteId in noteIds) {
      if (shouldFetchInteractions(noteId)) {
        notesToFetch.add(noteId);
        _lastManualFetch[noteId] = now;
        _fetchedInteractionNotes.add(noteId);
      }
    }

    if (notesToFetch.isNotEmpty) {
      try {
        print('[InteractionsProvider] Manually fetching interactions for ${notesToFetch.length} notes');

        final dataService = DataService.instance;
        await dataService.fetchInteractionsForEvents(notesToFetch, forceLoad: true);

        print('[InteractionsProvider] Manual interaction fetching completed for ${notesToFetch.length} notes');

        notifyListeners();

        for (final noteId in notesToFetch) {
          _reactionStreamController.add(noteId);
          _replyStreamController.add(noteId);
          _repostStreamController.add(noteId);
          _zapStreamController.add(noteId);
        }
      } catch (e) {
        print('[InteractionsProvider] Error in manual interaction fetching: $e');

        for (final noteId in notesToFetch) {
          _fetchedInteractionNotes.remove(noteId);
          _lastManualFetch.remove(noteId);
        }
      }
    } else {
      print('[InteractionsProvider] No new interactions needed - all notes recently fetched');

      notifyListeners();
    }
  }

  bool shouldFetchInteractions(String noteId) {
    final lastFetch = _lastManualFetch[noteId];
    if (lastFetch != null) {
      final timeSinceLastFetch = DateTime.now().difference(lastFetch);

      if (timeSinceLastFetch < const Duration(seconds: 10)) {
        return false;
      }
    }

    return true;
  }

  bool hasLoadedInteractions(String noteId) {
    return _fetchedInteractionNotes.contains(noteId) ||
        (_reactionsByNote[noteId]?.isNotEmpty ?? false) ||
        (_repliesByNote[noteId]?.isNotEmpty ?? false) ||
        (_repostsByNote[noteId]?.isNotEmpty ?? false) ||
        (_zapsByNote[noteId]?.isNotEmpty ?? false);
  }

  void clearFetchTracking() {
    _fetchedInteractionNotes.clear();
    _lastManualFetch.clear();
    print('[InteractionsProvider] Interaction fetch tracking cleared');
  }

  void _startPeriodicUpdates() {
    _periodicTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    _reactionStreamController.close();
    _replyStreamController.close();
    _repostStreamController.close();
    _zapStreamController.close();

    clearFetchTracking();

    super.dispose();
  }
}
