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

  Future<void> processVisibleNotesInteractions(List<String> visibleEventIds) async {
    if (_isClosed || visibleEventIds.isEmpty) return;

    try {
      print('[BatchProcessingService] Ultra-fast processing for ${visibleEventIds.length} visible notes');

      const batchSize = 6;
      for (int i = 0; i < visibleEventIds.length; i += batchSize) {
        final batch = visibleEventIds.skip(i).take(batchSize).toList();

        Future.microtask(() => _processVisibleBatchInteraction(batch, 'reaction'));
        Future.microtask(() => _processVisibleBatchInteraction(batch, 'reply'));
        Future.microtask(() => _processVisibleBatchInteraction(batch, 'repost'));
        Future.microtask(() => _processVisibleBatchInteraction(batch, 'zap'));

        if (i + batchSize < visibleEventIds.length && i % (batchSize * 3) == 0) {
          await Future.delayed(const Duration(milliseconds: 15));
        }
      }

      print('[BatchProcessingService] Ultra-fast processing completed for smooth transitions');
    } catch (e) {
      print('[BatchProcessingService] Error in ultra-fast processing: $e');
    }
  }

  Future<void> _processVisibleBatchInteraction(List<String> eventIds, String interactionType) async {
    if (_isClosed || eventIds.isEmpty) return;

    Future.microtask(() async {
      try {
        String request;
        switch (interactionType) {
          case 'reaction':
            final filter = NostrService.createReactionFilter(eventIds: eventIds, limit: 25);
            request = NostrService.serializeRequest(NostrService.createRequest(filter));
            break;
          case 'reply':
            final filter = NostrService.createReplyFilter(eventIds: eventIds, limit: 25);
            request = NostrService.serializeRequest(NostrService.createRequest(filter));
            break;
          case 'repost':
            final filter = NostrService.createRepostFilter(eventIds: eventIds, limit: 25);
            request = NostrService.serializeRequest(NostrService.createRequest(filter));
            break;
          case 'zap':
            final filter = NostrService.createZapFilter(eventIds: eventIds, limit: 25);
            request = NostrService.serializeRequest(NostrService.createRequest(filter));
            break;
          default:
            return;
        }

        _networkService.broadcastRequest(request).catchError((e) {
          print('[BatchProcessingService] Background broadcast error for $interactionType: $e');
        });
      } catch (e) {
        print('[BatchProcessingService] Error in smooth batch interaction for $interactionType: $e');
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
  }
}
