import 'dart:async';
import 'dart:collection';
import 'network_service.dart';
import 'nostr_service.dart';

class BatchItem<T> {
  final T data;
  final int priority;
  final DateTime timestamp;

  BatchItem(this.data, this.priority) : timestamp = DateTime.now();
}

class BatchProcessingService {
  final NetworkService _networkService;

  final Queue<BatchItem<Map<String, dynamic>>> _eventQueue = Queue();
  final Queue<BatchItem<String>> _profileQueue = Queue();
  final Queue<BatchItem<List<String>>> _interactionQueue = Queue();

  final Queue<BatchItem<Map<String, dynamic>>> _priorityEventQueue = Queue();
  final Queue<BatchItem<String>> _priorityProfileQueue = Queue();
  final Queue<BatchItem<List<String>>> _priorityInteractionQueue = Queue();

  static const Duration _batchTimeout = Duration(milliseconds: 100);
  static const Duration _profileBatchTimeout = Duration(milliseconds: 200);

  int _currentEventBatchSize = 5;
  int _currentProfileBatchSize = 20;

  Timer? _eventBatchTimer;
  Timer? _profileBatchTimer;
  Timer? _interactionBatchTimer;

  bool _isProcessingEvents = false;
  bool _isProcessingProfiles = false;
  bool _isProcessingInteractions = false;
  bool _isClosed = false;

  BatchProcessingService({required NetworkService networkService}) : _networkService = networkService;

  void addEventToBatch(Map<String, dynamic> eventData, {int priority = 2}) {
    if (_isClosed) return;

    final item = BatchItem(eventData, priority);
    if (priority > 2) {
      _priorityEventQueue.add(item);
    } else {
      _eventQueue.add(item);
    }

    final totalLength = _eventQueue.length + _priorityEventQueue.length;
    if (totalLength >= _currentEventBatchSize) {
      _flushEventBatch();
    } else {
      _eventBatchTimer?.cancel();
      _eventBatchTimer = Timer(_batchTimeout, _flushEventBatch);
    }
  }

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

    try {
      print('[BatchProcessingService] User note processed');
    } catch (e) {
      print('[BatchProcessingService] Error processing note: $e');
    }
  }

  Future<void> processUserInteractionInstantly(List<String> eventIds, String interactionType) async {
    if (_isClosed || eventIds.isEmpty) return;

    try {
      final futures = <Future>[];

      for (final eventId in eventIds) {
        switch (interactionType) {
          case 'reaction':
            final reactionFilter = NostrService.createReactionFilter(eventIds: [eventId], limit: 500);
            futures.add(_networkService.broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(reactionFilter))));
            break;
          case 'reply':
            final replyFilter = NostrService.createReplyFilter(eventIds: [eventId], limit: 500);
            futures.add(_networkService.broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(replyFilter))));
            break;
          case 'repost':
            final repostFilter = NostrService.createRepostFilter(eventIds: [eventId], limit: 500);
            futures.add(_networkService.broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(repostFilter))));
            break;
          case 'zap':
            final zapFilter = NostrService.createZapFilter(eventIds: [eventId], limit: 500);
            futures.add(_networkService.broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(zapFilter))));
            break;
        }
      }

      if (futures.isNotEmpty) {
        await Future.wait(futures);
      }

      print('[BatchProcessingService] User $interactionType processed for ${eventIds.length} events');
    } catch (e) {
      print('[BatchProcessingService] Error processing user interaction: $e');
    }
  }

  void _flushEventBatch() {
    if ((_eventQueue.isEmpty && _priorityEventQueue.isEmpty) || _isProcessingEvents) return;

    _isProcessingEvents = true;
    _eventBatchTimer?.cancel();

    final batch = <Map<String, dynamic>>[];
    final totalItems = _eventQueue.length + _priorityEventQueue.length;
    final batchSize = totalItems.clamp(1, _currentEventBatchSize);

    for (int i = 0; i < batchSize; i++) {
      if (_priorityEventQueue.isNotEmpty) {
        batch.add(_priorityEventQueue.removeFirst().data);
      } else if (_eventQueue.isNotEmpty) {
        batch.add(_eventQueue.removeFirst().data);
      }
    }

    if (batch.isNotEmpty) {
      _processEventBatch(batch);
    }

    _isProcessingEvents = false;

    if (_eventQueue.isNotEmpty || _priorityEventQueue.isNotEmpty) {
      Future.microtask(_flushEventBatch);
    }
  }

  Future<void> _processEventBatch(List<Map<String, dynamic>> events) async {}

  void addProfileToBatch(String npub, {int priority = 2}) {
    if (_isClosed) return;

    final existsInNormal = _profileQueue.any((item) => item.data == npub);
    final existsInPriority = _priorityProfileQueue.any((item) => item.data == npub);

    if (!existsInNormal && !existsInPriority) {
      final item = BatchItem(npub, priority);
      if (priority > 2) {
        _priorityProfileQueue.add(item);
      } else {
        _profileQueue.add(item);
      }
    }

    final totalLength = _profileQueue.length + _priorityProfileQueue.length;
    if (totalLength >= _currentProfileBatchSize) {
      _flushProfileBatch();
    } else {
      _profileBatchTimer?.cancel();
      _profileBatchTimer = Timer(_profileBatchTimeout, _flushProfileBatch);
    }
  }

  void _flushProfileBatch() {
    if ((_profileQueue.isEmpty && _priorityProfileQueue.isEmpty) || _isProcessingProfiles) return;

    _isProcessingProfiles = true;
    _profileBatchTimer?.cancel();

    final batch = <String>[];
    final totalItems = _profileQueue.length + _priorityProfileQueue.length;
    final batchSize = totalItems.clamp(1, _currentProfileBatchSize);

    for (int i = 0; i < batchSize; i++) {
      if (_priorityProfileQueue.isNotEmpty) {
        batch.add(_priorityProfileQueue.removeFirst().data);
      } else if (_profileQueue.isNotEmpty) {
        batch.add(_profileQueue.removeFirst().data);
      }
    }

    if (batch.isNotEmpty) {
      _processProfileBatch(batch);
    }

    _isProcessingProfiles = false;

    if (_profileQueue.isNotEmpty || _priorityProfileQueue.isNotEmpty) {
      Future.microtask(_flushProfileBatch);
    }
  }

  Future<void> _processProfileBatch(List<String> npubs) async {}

  void addInteractionBatch(List<String> eventIds, {int priority = 2}) {
    if (_isClosed || eventIds.isEmpty) return;

    print('[BatchProcessingService] Interaction batch disabled - ${eventIds.length} events skipped');
    return;
  }

  void _flushInteractionBatch() {
    if ((_interactionQueue.isEmpty && _priorityInteractionQueue.isEmpty) || _isProcessingInteractions) return;

    _isProcessingInteractions = true;
    _interactionBatchTimer?.cancel();

    final allEventIds = <String>{};

    while (_priorityInteractionQueue.isNotEmpty) {
      final batch = _priorityInteractionQueue.removeFirst();
      allEventIds.addAll(batch.data);
    }

    while (_interactionQueue.isNotEmpty) {
      final batch = _interactionQueue.removeFirst();
      allEventIds.addAll(batch.data);
    }

    if (allEventIds.isNotEmpty) {
      _processInteractionBatch(allEventIds.toList());
    }

    _isProcessingInteractions = false;
  }

  Future<void> _processInteractionBatch(List<String> eventIds) async {
    print('[BatchProcessingService] Interaction processing disabled - ${eventIds.length} events skipped');
    return;
  }

  Future<void> batchSubscribeToInteractions(List<String> eventIds) async {
    if (_isClosed || eventIds.isEmpty) return;

    print('[BatchProcessingService] Interaction subscription disabled - ${eventIds.length} events skipped');
    return;
  }

  void processPriorityEvent(Map<String, dynamic> eventData) {
    if (_isClosed) return;

    _processEventBatch([eventData]);
  }

  void clearQueues() {
    _eventQueue.clear();
    _profileQueue.clear();
    _interactionQueue.clear();
    _priorityEventQueue.clear();
    _priorityProfileQueue.clear();
    _priorityInteractionQueue.clear();
  }

  void close() {
    _isClosed = true;

    _eventBatchTimer?.cancel();
    _profileBatchTimer?.cancel();
    _interactionBatchTimer?.cancel();

    _flushEventBatch();
    _flushProfileBatch();
    _flushInteractionBatch();

    clearQueues();
  }
}
