import 'dart:async';
import 'network_service.dart';
import 'nostr_service.dart';

class BatchProcessingService {
  final NetworkService _networkService;
  bool _isClosed = false;

  BatchProcessingService({required NetworkService networkService}) : _networkService = networkService;

  Future<void> processUserReaction(String targetEventId, String reactionContent, String privateKey) async {
    if (_isClosed) return;

    try {
      final reactionFilter = NostrService.createReactionFilter(eventIds: [targetEventId], limit: 1);
      final request = NostrService.serializeRequest(NostrService.createRequest(reactionFilter));
      await _networkService.broadcastRequest(request);
    } catch (e) {
      print('[BatchProcessingService] Error processing reaction: $e');
    }
  }

  Future<void> processUserReply(String parentEventId, String replyContent, String privateKey) async {
    if (_isClosed) return;

    try {
      final replyFilter = NostrService.createReplyFilter(eventIds: [parentEventId], limit: 1);
      final request = NostrService.serializeRequest(NostrService.createRequest(replyFilter));
      await _networkService.broadcastRequest(request);
    } catch (e) {
      print('[BatchProcessingService] Error processing reply: $e');
    }
  }

  Future<void> processUserRepost(String noteId, String noteAuthor, String privateKey) async {
    if (_isClosed) return;

    try {
      final repostFilter = NostrService.createRepostFilter(eventIds: [noteId], limit: 1);
      final request = NostrService.serializeRequest(NostrService.createRequest(repostFilter));
      await _networkService.broadcastRequest(request);
    } catch (e) {
      print('[BatchProcessingService] Error processing repost: $e');
    }
  }

  Future<void> processUserNote(String noteContent, String privateKey) async {
    if (_isClosed) return;
    print('[BatchProcessingService] User note processed');
  }

  Future<void> processUserInteractionInstantly(List<String> eventIds, String interactionType) async {
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
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

      print('[BatchProcessingService] $interactionType processed for ${eventIds.length} events in batches');
    } catch (e) {
      print('[BatchProcessingService] Error processing interaction: $e');
    }
  }

  // Cache to track which interactions we've already fetched for visible notes
  final Set<String> _fetchedReactions = {};
  final Set<String> _fetchedReplies = {};
  final Set<String> _fetchedReposts = {};
  final Set<String> _fetchedZaps = {};

  Future<void> processVisibleNotesInteractions(List<String> visibleEventIds) async {
    if (_isClosed || visibleEventIds.isEmpty) return;

    try {
      print('[BatchProcessingService] Smart processing for ${visibleEventIds.length} visible notes only');

      // Filter out already fetched interactions to avoid duplicate requests
      final needsReactions = visibleEventIds.where((id) => !_fetchedReactions.contains(id)).toList();
      final needsReplies = visibleEventIds.where((id) => !_fetchedReplies.contains(id)).toList();
      final needsReposts = visibleEventIds.where((id) => !_fetchedReposts.contains(id)).toList();
      final needsZaps = visibleEventIds.where((id) => !_fetchedZaps.contains(id)).toList();

      // Only process if there are new interactions needed
      const batchSize = 8; // Slightly larger batches for efficiency

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

      print(
          '[BatchProcessingService] Smart processing completed - avoided ${visibleEventIds.length - needsReactions.length} duplicate reaction fetches');
    } catch (e) {
      print('[BatchProcessingService] Error in smart visible notes processing: $e');
    }
  }

  Future<void> _processInteractionType(List<String> eventIds, String interactionType, Set<String> fetchedCache, int batchSize) async {
    for (int i = 0; i < eventIds.length; i += batchSize) {
      final batch = eventIds.skip(i).take(batchSize).toList();

      // Process this batch asynchronously for better performance
      Future.microtask(() => _processVisibleBatchInteraction(batch, interactionType));

      // Mark as fetched to avoid duplicate requests
      fetchedCache.addAll(batch);

      // Small delay between batches to prevent overwhelming the network
      if (i + batchSize < eventIds.length) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    }
  }

  void clearVisibleNotesCache() {
    _fetchedReactions.clear();
    _fetchedReplies.clear();
    _fetchedReposts.clear();
    _fetchedZaps.clear();
    print('[BatchProcessingService] Cleared visible notes interaction cache');
  }

  Future<void> _processVisibleBatchInteraction(List<String> eventIds, String interactionType) async {
    if (_isClosed || eventIds.isEmpty) return;

    Future.microtask(() async {
      try {
        String request;
        // Optimized limits for visible notes only - higher limits since we're being selective
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

        // Fire and forget for visible notes - no need to wait
        _networkService.broadcastRequest(request).catchError((e) {
          print('[BatchProcessingService] Visible notes $interactionType fetch error: $e');
        });
      } catch (e) {
        print('[BatchProcessingService] Error in visible notes $interactionType processing: $e');
      }
    });
  }

  Future<void> _processBatchInteraction(List<String> eventIds, String interactionType) async {
    if (_isClosed || eventIds.isEmpty) return;

    try {
      String request;
      switch (interactionType) {
        case 'reaction':
          final filter = NostrService.createReactionFilter(eventIds: eventIds, limit: 20);
          request = NostrService.serializeRequest(NostrService.createRequest(filter));
          break;
        case 'reply':
          final filter = NostrService.createReplyFilter(eventIds: eventIds, limit: 20);
          request = NostrService.serializeRequest(NostrService.createRequest(filter));
          break;
        case 'repost':
          final filter = NostrService.createRepostFilter(eventIds: eventIds, limit: 20);
          request = NostrService.serializeRequest(NostrService.createRequest(filter));
          break;
        case 'zap':
          final filter = NostrService.createZapFilter(eventIds: eventIds, limit: 20);
          request = NostrService.serializeRequest(NostrService.createRequest(filter));
          break;
        default:
          return;
      }

      await _networkService.broadcastRequest(request);
    } catch (e) {
      print('[BatchProcessingService] Error in _processBatchInteraction for $interactionType: $e');
    }
  }

  void close() {
    _isClosed = true;
    clearVisibleNotesCache();
    print('[BatchProcessingService] Service closed and caches cleared');
  }
}
