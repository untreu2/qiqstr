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
      // Process in batches for better efficiency
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

        // Small delay between batches to prevent overwhelming the network
        if (i + batchSize < eventIds.length) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

      print('[BatchProcessingService] $interactionType processed for ${eventIds.length} events in batches');
    } catch (e) {
      print('[BatchProcessingService] Error processing interaction: $e');
    }
  }

  /// Process interactions specifically for visible notes with priority
  Future<void> processVisibleNotesInteractions(List<String> visibleEventIds) async {
    if (_isClosed || visibleEventIds.isEmpty) return;

    try {
      print('[BatchProcessingService] Processing interactions for ${visibleEventIds.length} visible notes');

      // Fetch all interaction types for visible notes in parallel
      final futures = <Future>[];

      // Split into smaller batches to avoid overwhelming the network
      const batchSize = 15;
      for (int i = 0; i < visibleEventIds.length; i += batchSize) {
        final batch = visibleEventIds.skip(i).take(batchSize).toList();

        futures.addAll([
          _processBatchInteraction(batch, 'reaction'),
          _processBatchInteraction(batch, 'reply'),
          _processBatchInteraction(batch, 'repost'),
          _processBatchInteraction(batch, 'zap'),
        ]);
      }

      await Future.wait(futures, eagerError: false);
      print('[BatchProcessingService] Completed processing visible notes interactions');
    } catch (e) {
      print('[BatchProcessingService] Error processing visible notes interactions: $e');
    }
  }

  Future<void> _processBatchInteraction(List<String> eventIds, String interactionType) async {
    if (_isClosed || eventIds.isEmpty) return;

    try {
      String request;
      switch (interactionType) {
        case 'reaction':
          final filter = NostrService.createReactionFilter(eventIds: eventIds, limit: 50);
          request = NostrService.serializeRequest(NostrService.createRequest(filter));
          break;
        case 'reply':
          final filter = NostrService.createReplyFilter(eventIds: eventIds, limit: 50);
          request = NostrService.serializeRequest(NostrService.createRequest(filter));
          break;
        case 'repost':
          final filter = NostrService.createRepostFilter(eventIds: eventIds, limit: 50);
          request = NostrService.serializeRequest(NostrService.createRequest(filter));
          break;
        case 'zap':
          final filter = NostrService.createZapFilter(eventIds: eventIds, limit: 50);
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
  }
}
