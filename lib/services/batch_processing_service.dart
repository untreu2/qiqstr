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
          await Future.delayed(const Duration(milliseconds: 10));
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

  // DISABLED: Automatic interaction fetching for visible notes
  // Interactions will only be fetched when entering thread pages for better performance
  Future<void> processVisibleNotesInteractions(List<String> visibleEventIds) async {
    if (_isClosed || visibleEventIds.isEmpty) return;

    // Disabled automatic interaction fetching for visible notes
    // Interactions are now only fetched when entering thread pages
    print('[BatchProcessingService] Automatic interaction fetching disabled - use manual fetchInteractionsForNotes() for thread pages');
    return;
  }

  Future<void> _processInteractionType(List<String> eventIds, String interactionType, Set<String> fetchedCache, int batchSize) async {
    for (int i = 0; i < eventIds.length; i += batchSize) {
      final batch = eventIds.skip(i).take(batchSize).toList();

      // Process this batch asynchronously for better performance
      Future.microtask(() => _processVisibleBatchInteraction(batch, interactionType));

      // Mark as fetched to avoid duplicate requests
      fetchedCache.addAll(batch);

      // Small delay between batches for better performance
      if (i + batchSize < eventIds.length) {
        await Future.delayed(const Duration(milliseconds: 5));
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

  // Method to manually fetch interactions for specific notes (e.g., for thread page)
  Future<void> fetchInteractionsForNotes(List<String> eventIds, {bool force = false}) async {
    if (_isClosed || eventIds.isEmpty) return;

    try {
      print('[BatchProcessingService] Manual interaction fetching for ${eventIds.length} notes');

      // Filter out already fetched interactions unless forced
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

      print('[BatchProcessingService] Manual interaction fetching completed');
    } catch (e) {
      print('[BatchProcessingService] Error in manual interaction fetching: $e');
    }
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

        // Background processing for visible notes - no need to wait
        _networkService.broadcastRequest(request).catchError((e) {
          print('[BatchProcessingService] Visible notes $interactionType fetch error: $e');
        });
      } catch (e) {
        print('[BatchProcessingService] Error in visible notes $interactionType processing: $e');
      }
    });
  }

  void close() {
    _isClosed = true;
    clearVisibleNotesCache();
    print('[BatchProcessingService] Service closed and caches cleared');
  }
}
