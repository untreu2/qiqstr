import 'dart:async';
import 'dart:collection';
import 'dart:math';
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

  // Enhanced queues with priority support
  final Queue<BatchItem<Map<String, dynamic>>> _eventQueue = Queue();
  final Queue<BatchItem<String>> _profileQueue = Queue();
  final Queue<BatchItem<List<String>>> _interactionQueue = Queue();

  // Priority queues for high-priority items
  final Queue<BatchItem<Map<String, dynamic>>> _priorityEventQueue = Queue();
  final Queue<BatchItem<String>> _priorityProfileQueue = Queue();
  final Queue<BatchItem<List<String>>> _priorityInteractionQueue = Queue();

  // Adaptive batch configuration
  static const int _maxBatchSize = 50;
  static const int _maxEventBatchSize = 10;
  static const Duration _batchTimeout = Duration(milliseconds: 100);
  static const Duration _profileBatchTimeout = Duration(milliseconds: 200);

  // Adaptive sizing based on performance
  int _currentEventBatchSize = 5;
  int _currentProfileBatchSize = 20;

  // Timers with better management
  Timer? _eventBatchTimer;
  Timer? _profileBatchTimer;
  Timer? _interactionBatchTimer;
  Timer? _performanceTimer;

  // Processing state with metrics
  bool _isProcessingEvents = false;
  bool _isProcessingProfiles = false;
  bool _isProcessingInteractions = false;
  bool _isClosed = false;

  // Performance metrics
  final Map<String, List<Duration>> _processingTimes = {};
  final Map<String, int> _successCounts = {};
  final Map<String, int> _errorCounts = {};

  BatchProcessingService({required NetworkService networkService}) : _networkService = networkService {
    _startPerformanceMonitoring();
  }

  void _startPerformanceMonitoring() {
    _performanceTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _adjustBatchSizes();
      _cleanupMetrics();
    });
  }

  void _adjustBatchSizes() {
    // Adjust event batch size based on performance
    final eventTimes = _processingTimes['events'] ?? [];
    if (eventTimes.isNotEmpty) {
      final avgTime = eventTimes.fold<int>(0, (sum, d) => sum + d.inMilliseconds) / eventTimes.length;
      if (avgTime > 200) {
        _currentEventBatchSize = max(3, _currentEventBatchSize - 1);
      } else if (avgTime < 50) {
        _currentEventBatchSize = min(_maxEventBatchSize, _currentEventBatchSize + 1);
      }
    }

    // Adjust profile batch size based on performance
    final profileTimes = _processingTimes['profiles'] ?? [];
    if (profileTimes.isNotEmpty) {
      final avgTime = profileTimes.fold<int>(0, (sum, d) => sum + d.inMilliseconds) / profileTimes.length;
      if (avgTime > 500) {
        _currentProfileBatchSize = max(10, _currentProfileBatchSize - 5);
      } else if (avgTime < 100) {
        _currentProfileBatchSize = min(_maxBatchSize, _currentProfileBatchSize + 5);
      }
    }
  }

  void _cleanupMetrics() {
    // Keep only last 20 measurements per operation
    for (final key in _processingTimes.keys) {
      final times = _processingTimes[key]!;
      if (times.length > 20) {
        _processingTimes[key] = times.sublist(times.length - 20);
      }
    }
  }

  void _recordPerformance(String operation, Duration duration, bool success) {
    _processingTimes.putIfAbsent(operation, () => []);
    _processingTimes[operation]!.add(duration);

    if (success) {
      _successCounts[operation] = (_successCounts[operation] ?? 0) + 1;
    } else {
      _errorCounts[operation] = (_errorCounts[operation] ?? 0) + 1;
    }
  }

  // Event batching
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

  Future<void> processUserReactionInstantly(String targetEventId, String reactionContent, String privateKey) async {
    if (_isClosed) return;

    try {
      final reactionFilter = NostrService.createReactionFilter(eventIds: [targetEventId], limit: 1);
      final request = NostrService.serializeRequest(NostrService.createRequest(reactionFilter));
      await _networkService.broadcastRequest(request);
    } catch (e) {
      print('[BatchProcessingService] Error processing instant reaction: $e');
    }
  }

  Future<void> processUserReplyInstantly(String parentEventId, String replyContent, String privateKey) async {
    if (_isClosed) return;

    try {
      final replyFilter = NostrService.createReplyFilter(eventIds: [parentEventId], limit: 1);
      final request = NostrService.serializeRequest(NostrService.createRequest(replyFilter));
      await _networkService.broadcastRequest(request);
    } catch (e) {
      print('[BatchProcessingService] Error processing instant reply: $e');
    }
  }

  Future<void> processUserRepostInstantly(String noteId, String noteAuthor, String privateKey) async {
    if (_isClosed) return;

    try {
      final repostFilter = NostrService.createRepostFilter(eventIds: [noteId], limit: 1);
      final request = NostrService.serializeRequest(NostrService.createRequest(repostFilter));
      await _networkService.broadcastRequest(request);
    } catch (e) {
      print('[BatchProcessingService] Error processing instant repost: $e');
    }
  }

  Future<void> processUserNoteInstantly(String noteContent, String privateKey) async {
    if (_isClosed) return;

    try {
      print('[BatchProcessingService] User note processed instantly');
    } catch (e) {
      print('[BatchProcessingService] Error processing instant note: $e');
    }
  }

  // Process user interactions with maximum priority (bypasses all queues)
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

      // Execute all requests immediately without any delays
      if (futures.isNotEmpty) {
        await Future.wait(futures);
      }

      print('[BatchProcessingService] User $interactionType processed instantly for ${eventIds.length} events');
    } catch (e) {
      print('[BatchProcessingService] Error processing instant user interaction: $e');
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
      final stopwatch = Stopwatch()..start();
      _processEventBatch(batch).then((_) {
        stopwatch.stop();
        _recordPerformance('events', stopwatch.elapsed, true);
      }).catchError((error) {
        stopwatch.stop();
        _recordPerformance('events', stopwatch.elapsed, false);
      });
    }

    _isProcessingEvents = false;

    // Process remaining events if any
    if (_eventQueue.isNotEmpty || _priorityEventQueue.isNotEmpty) {
      Future.microtask(_flushEventBatch);
    }
  }

  Future<void> _processEventBatch(List<Map<String, dynamic>> events) async {
    // This would be handled by the main service
    // Just a placeholder for batch processing logic
  }

  // Profile batching
  void addProfileToBatch(String npub, {int priority = 2}) {
    if (_isClosed) return;

    // Avoid duplicates in both queues
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
      final stopwatch = Stopwatch()..start();
      _processProfileBatch(batch).then((_) {
        stopwatch.stop();
        _recordPerformance('profiles', stopwatch.elapsed, true);
      }).catchError((error) {
        stopwatch.stop();
        _recordPerformance('profiles', stopwatch.elapsed, false);
      });
    }

    _isProcessingProfiles = false;

    // Process remaining profiles if any
    if (_profileQueue.isNotEmpty || _priorityProfileQueue.isNotEmpty) {
      Future.microtask(_flushProfileBatch);
    }
  }

  Future<void> _processProfileBatch(List<String> npubs) async {
    // This would be handled by the profile service
    // Just a placeholder for batch processing logic
  }

  // Interaction batching (reactions, replies, reposts)
  void addInteractionBatch(List<String> eventIds, {int priority = 2}) {
    if (_isClosed || eventIds.isEmpty) return;

    final item = BatchItem(eventIds, priority);
    if (priority > 2) {
      _priorityInteractionQueue.add(item);
    } else {
      _interactionQueue.add(item);
    }

    final totalLength = _interactionQueue.length + _priorityInteractionQueue.length;
    if (totalLength >= 3) {
      _flushInteractionBatch();
    } else {
      _interactionBatchTimer?.cancel();
      _interactionBatchTimer = Timer(_batchTimeout, _flushInteractionBatch);
    }
  }

  void _flushInteractionBatch() {
    if ((_interactionQueue.isEmpty && _priorityInteractionQueue.isEmpty) || _isProcessingInteractions) return;

    _isProcessingInteractions = true;
    _interactionBatchTimer?.cancel();

    final allEventIds = <String>{};

    // Process priority items first
    while (_priorityInteractionQueue.isNotEmpty) {
      final batch = _priorityInteractionQueue.removeFirst();
      allEventIds.addAll(batch.data);
    }

    // Then process normal items
    while (_interactionQueue.isNotEmpty) {
      final batch = _interactionQueue.removeFirst();
      allEventIds.addAll(batch.data);
    }

    if (allEventIds.isNotEmpty) {
      final stopwatch = Stopwatch()..start();
      _processInteractionBatch(allEventIds.toList()).then((_) {
        stopwatch.stop();
        _recordPerformance('interactions', stopwatch.elapsed, true);
      }).catchError((error) {
        stopwatch.stop();
        _recordPerformance('interactions', stopwatch.elapsed, false);
      });
    }

    _isProcessingInteractions = false;
  }

  Future<void> _processInteractionBatch(List<String> eventIds) async {
    const batchSize = 50;
    final futures = <Future>[];

    for (int i = 0; i < eventIds.length; i += batchSize) {
      final endIndex = (i + batchSize > eventIds.length) ? eventIds.length : i + batchSize;
      final batch = eventIds.sublist(i, endIndex);

      if (batch.isNotEmpty) {
        // Create requests for different interaction types
        final reactionFilter = NostrService.createReactionFilter(eventIds: batch, limit: 500);
        final replyFilter = NostrService.createReplyFilter(eventIds: batch, limit: 500);
        final repostFilter = NostrService.createRepostFilter(eventIds: batch, limit: 500);
        final zapFilter = NostrService.createZapFilter(eventIds: batch, limit: 500);

        futures.addAll([
          _networkService.broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(reactionFilter))),
          _networkService.broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(replyFilter))),
          _networkService.broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(repostFilter))),
          _networkService.broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(zapFilter))),
        ]);
      }

      // Limit concurrent requests
      if (futures.length >= 12) {
        await Future.wait(futures);
        futures.clear();
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  // Subscription batching for better relay management
  Future<void> batchSubscribeToInteractions(List<String> eventIds) async {
    if (_isClosed || eventIds.isEmpty) return;

    const batchSize = 50;
    final futures = <Future>[];

    for (int i = 0; i < eventIds.length; i += batchSize) {
      final endIndex = (i + batchSize > eventIds.length) ? eventIds.length : i + batchSize;
      final batch = eventIds.sublist(i, endIndex);

      if (batch.isNotEmpty) {
        final filter = NostrService.createCombinedInteractionFilter(eventIds: batch, limit: 1000);
        futures.add(_networkService.broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(filter))));
      }

      if (futures.length >= 3) {
        await Future.wait(futures);
        futures.clear();
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  // Priority processing for urgent events
  void processPriorityEvent(Map<String, dynamic> eventData) {
    if (_isClosed) return;

    // Process immediately without batching for high priority events
    _processEventBatch([eventData]);
  }

  // Cleanup and resource management
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
    _performanceTimer?.cancel();

    // Flush remaining batches
    _flushEventBatch();
    _flushProfileBatch();
    _flushInteractionBatch();

    clearQueues();
  }

  // Enhanced statistics for monitoring
  Map<String, dynamic> getQueueStats() {
    return {
      'eventQueue': _eventQueue.length,
      'priorityEventQueue': _priorityEventQueue.length,
      'profileQueue': _profileQueue.length,
      'priorityProfileQueue': _priorityProfileQueue.length,
      'interactionQueue': _interactionQueue.length,
      'priorityInteractionQueue': _priorityInteractionQueue.length,
      'currentEventBatchSize': _currentEventBatchSize,
      'currentProfileBatchSize': _currentProfileBatchSize,
      'processingStates': {
        'events': _isProcessingEvents,
        'profiles': _isProcessingProfiles,
        'interactions': _isProcessingInteractions,
      },
      'performance': {
        'successCounts': _successCounts,
        'errorCounts': _errorCounts,
        'avgProcessingTimes': {
          for (final entry in _processingTimes.entries)
            entry.key: entry.value.isNotEmpty ? entry.value.fold<int>(0, (sum, d) => sum + d.inMilliseconds) / entry.value.length : 0,
        },
      },
    };
  }
}
