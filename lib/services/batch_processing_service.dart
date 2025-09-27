import 'dart:async';
import 'network_service.dart';
import 'nostr_service.dart';

class BatchProcessingService {
  final NetworkService _networkService;
  bool _isClosed = false;

  BatchProcessingService({required NetworkService networkService}) : _networkService = networkService;

  Future<void> processUserReaction(String targetEventId, String reactionContent) async {
    if (_isClosed) return;

    try {
      final reactionFilter = NostrService.createReactionFilter(eventIds: [targetEventId], limit: 1);
      final request = NostrService.serializeRequest(NostrService.createRequest(reactionFilter));
      await _networkService.broadcastRequest(request);
    } catch (e) {}
  }

  Future<void> processUserReply(String parentEventId, String replyContent) async {
    if (_isClosed) return;

    try {
      final replyFilter = NostrService.createReplyFilter(eventIds: [parentEventId], limit: 1);
      final request = NostrService.serializeRequest(NostrService.createRequest(replyFilter));
      await _networkService.broadcastRequest(request);
    } catch (e) {}
  }

  Future<void> processUserRepost(String noteId, String noteAuthor) async {
    if (_isClosed) return;

    try {
      final repostFilter = NostrService.createRepostFilter(eventIds: [noteId], limit: 1);
      final request = NostrService.serializeRequest(NostrService.createRequest(repostFilter));
      await _networkService.broadcastRequest(request);
    } catch (e) {}
  }

  Future<void> processUserNote(String noteContent) async {
    if (_isClosed) return;
  }

  Future<void> processUserInteraction(List<String> eventIds, String interactionType) async {
    if (_isClosed || eventIds.isEmpty) return;

    try {
      const batchSize = 25;
      for (int i = 0; i < eventIds.length; i += batchSize) {
        final batch = eventIds.skip(i).take(batchSize).toList();

        String request;
        switch (interactionType) {
          case 'reaction':
            final filter = NostrService.createReactionFilter(eventIds: batch, limit: 100);
            request = NostrService.serializeRequest(NostrService.createRequest(filter));
            break;
          case 'reply':
            final filter = NostrService.createReplyFilter(eventIds: batch, limit: 100);
            request = NostrService.serializeRequest(NostrService.createRequest(filter));
            break;
          case 'repost':
            final filter = NostrService.createRepostFilter(eventIds: batch, limit: 100);
            request = NostrService.serializeRequest(NostrService.createRequest(filter));
            break;
          case 'zap':
            final filter = NostrService.createZapFilter(eventIds: batch, limit: 100);
            request = NostrService.serializeRequest(NostrService.createRequest(filter));
            break;
          default:
            continue;
        }

        await _networkService.broadcastRequest(request);

        if (i + batchSize < eventIds.length) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
      }
    } catch (e) {}
  }

  final Set<String> _fetchedReactions = {};
  final Set<String> _fetchedReplies = {};
  final Set<String> _fetchedReposts = {};
  final Set<String> _fetchedZaps = {};

  Future<void> processVisibleNotesInteractions(List<String> visibleEventIds) async {
    if (_isClosed || visibleEventIds.isEmpty) return;

    return;
  }

  Future<void> _processInteractionType(List<String> eventIds, String interactionType, Set<String> fetchedCache, int batchSize) async {
    for (int i = 0; i < eventIds.length; i += batchSize) {
      final batch = eventIds.skip(i).take(batchSize).toList();

      Future.microtask(() => _processVisibleBatchInteraction(batch, interactionType));

      fetchedCache.addAll(batch);

      if (i + batchSize < eventIds.length) {
        await Future.delayed(Duration.zero);
      }
    }
  }

  void clearVisibleNotesCache() {
    _fetchedReactions.clear();
    _fetchedReplies.clear();
    _fetchedReposts.clear();
    _fetchedZaps.clear();
  }

  Future<void> fetchInteractionsForNotes(List<String> eventIds, {bool force = false}) async {
    if (_isClosed || eventIds.isEmpty) return;

    try {
      final needsReactions = force ? eventIds : eventIds.where((id) => !_fetchedReactions.contains(id)).toList();
      final needsReplies = force ? eventIds : eventIds.where((id) => !_fetchedReplies.contains(id)).toList();
      final needsReposts = force ? eventIds : eventIds.where((id) => !_fetchedReposts.contains(id)).toList();
      final needsZaps = force ? eventIds : eventIds.where((id) => !_fetchedZaps.contains(id)).toList();

      const batchSize = 8;

      if (needsReactions.isNotEmpty) {
        await _processInteractionType(needsReactions, 'reaction', _fetchedReactions, batchSize);
      }

      if (needsReplies.isNotEmpty) {
        await _processInteractionType(needsReplies, 'reply', _fetchedReplies, batchSize);
      }

      if (needsReposts.isNotEmpty) {
        await _processInteractionType(needsReposts, 'repost', _fetchedReposts, batchSize);
      }

      if (needsZaps.isNotEmpty) {
        await _processInteractionType(needsZaps, 'zap', _fetchedZaps, batchSize);
      }
    } catch (e) {}
  }

  Future<void> _processVisibleBatchInteraction(List<String> eventIds, String interactionType) async {
    if (_isClosed || eventIds.isEmpty) return;

    Future.microtask(() async {
      try {
        String request;

        switch (interactionType) {
          case 'reaction':
            final filter = NostrService.createReactionFilter(eventIds: eventIds, limit: 50);
            request = NostrService.serializeRequest(NostrService.createRequest(filter));
            break;
          case 'reply':
            final filter = NostrService.createReplyFilter(eventIds: eventIds, limit: 30);
            request = NostrService.serializeRequest(NostrService.createRequest(filter));
            break;
          case 'repost':
            final filter = NostrService.createRepostFilter(eventIds: eventIds, limit: 20);
            request = NostrService.serializeRequest(NostrService.createRequest(filter));
            break;
          case 'zap':
            final filter = NostrService.createZapFilter(eventIds: eventIds, limit: 40);
            request = NostrService.serializeRequest(NostrService.createRequest(filter));
            break;
          default:
            return;
        }

        _networkService.broadcastRequest(request).catchError((e) {});
      } catch (e) {}
    });
  }

  void close() {
    _isClosed = true;
    clearVisibleNotesCache();
  }
}
