import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:collection';
import 'dart:math';
import '../models/note_model.dart';
import 'base/isolate_types.dart';
import 'base/service_base.dart';

class EventBatch {
  final List<Map<String, dynamic>> events;
  final DateTime timestamp;
  final int priority;

  EventBatch(this.events, this.priority) : timestamp = DateTime.now();
}

class OptimizedIsolateManager extends LifecycleService {
  // Event processing isolate
  Isolate? _eventProcessorIsolate;
  SendPort? _eventProcessorSendPort;
  final Completer<void> _eventProcessorReady = Completer<void>();

  // Fetch processing isolate
  Isolate? _fetchProcessorIsolate;
  SendPort? _fetchProcessorSendPort;
  final Completer<void> _fetchProcessorReady = Completer<void>();

  // Data processing isolate
  Isolate? _dataProcessorIsolate;
  SendPort? _dataProcessorSendPort;
  final Completer<void> _dataProcessorReady = Completer<void>();

  @override
  Future<void> onInitialize() async {
    await Future.wait([
      _initializeEventProcessorIsolate(),
      _initializeFetchProcessorIsolate(),
      _initializeDataProcessorIsolate(),
    ]);
  }

  @override
  Future<void> onClose() async {
    _eventProcessorIsolate?.kill(priority: Isolate.immediate);
    _fetchProcessorIsolate?.kill(priority: Isolate.immediate);
    _dataProcessorIsolate?.kill(priority: Isolate.immediate);
  }

  Future<void> _initializeEventProcessorIsolate() async {
    final ReceivePort receivePort = ReceivePort();

    _eventProcessorIsolate = await Isolate.spawn(
      _eventProcessorEntryPoint,
      receivePort.sendPort,
    );

    addSubscription(receivePort.listen((dynamic message) {
      if (message is SendPort) {
        _eventProcessorSendPort = message;
        if (!_eventProcessorReady.isCompleted) {
          _eventProcessorReady.complete();
        }
      } else if (message is Map<String, dynamic>) {
        _handleEventProcessorMessage(message);
      }
    }));
  }

  Future<void> _initializeFetchProcessorIsolate() async {
    final ReceivePort receivePort = ReceivePort();

    _fetchProcessorIsolate = await Isolate.spawn(
      _fetchProcessorEntryPoint,
      receivePort.sendPort,
    );

    addSubscription(receivePort.listen((dynamic message) {
      if (message is SendPort) {
        _fetchProcessorSendPort = message;
        if (!_fetchProcessorReady.isCompleted) {
          _fetchProcessorReady.complete();
        }
      } else if (message is Map<String, dynamic>) {
        _handleFetchProcessorMessage(message);
      }
    }));
  }

  Future<void> _initializeDataProcessorIsolate() async {
    final ReceivePort receivePort = ReceivePort();

    _dataProcessorIsolate = await Isolate.spawn(
      _dataProcessorEntryPoint,
      receivePort.sendPort,
    );

    addSubscription(receivePort.listen((dynamic message) {
      if (message is SendPort) {
        _dataProcessorSendPort = message;
        if (!_dataProcessorReady.isCompleted) {
          _dataProcessorReady.complete();
        }
      } else {
        _handleDataProcessorMessage(message);
      }
    }));
  }

  void _handleEventProcessorMessage(Map<String, dynamic> message) {
    // Handle processed events
    if (message.containsKey('error')) {
      print('[Event Isolate ERROR] ${message['error']}');
    } else if (message.containsKey('type') && message['type'] == 'batch_results') {
      final results = message['results'] as List<dynamic>? ?? [];
      for (final result in results) {
        if (result is Map<String, dynamic> && !result.containsKey('error')) {
          // Process the parsed event
          _notifyEventProcessed(result);
        }
      }
    }
  }

  void _handleFetchProcessorMessage(Map<String, dynamic> message) {
    // Handle fetch results
    if (message.containsKey('error')) {
      print('[Fetch Isolate ERROR] ${message['error']}');
    } else {
      _notifyFetchCompleted(message);
    }
  }

  void _handleDataProcessorMessage(dynamic message) {
    // Handle data processing results
    if (message is Map<String, dynamic> && message.containsKey('error')) {
      print('[Data Isolate ERROR] ${message['error']}');
    }
  }

  // Public API methods
  Future<void> processEventBatch(List<Map<String, dynamic>> events) async {
    ensureInitialized();
    await _eventProcessorReady.future;

    if (_eventProcessorSendPort != null) {
      _eventProcessorSendPort!.send(events);
    }
  }

  Future<void> processFetchRequest(Map<String, dynamic> request) async {
    ensureInitialized();
    await _fetchProcessorReady.future;

    if (_fetchProcessorSendPort != null) {
      _fetchProcessorSendPort!.send(request);
    }
  }

  Future<void> processDataTask(String data, String type) async {
    ensureInitialized();
    await _dataProcessorReady.future;

    if (_dataProcessorSendPort != null) {
      final task = DataProcessingTask(data, type, DateTime.now());
      _dataProcessorSendPort!.send({
        'data': task.data,
        'type': task.type,
        'timestamp': task.timestamp.millisecondsSinceEpoch,
      });
    }
  }

  // Callback methods (to be overridden by users)
  void _notifyEventProcessed(Map<String, dynamic> result) {
    // Override this method to handle processed events
  }

  void _notifyFetchCompleted(Map<String, dynamic> result) {
    // Override this method to handle fetch results
  }

  // Static isolate entry points
  static void _eventProcessorEntryPoint(SendPort sendPort) {
    final ReceivePort port = ReceivePort();
    sendPort.send(port.sendPort);

    final Queue<EventBatch> _processingQueue = Queue();
    bool _isProcessing = false;

    void _processQueue() async {
      if (_isProcessing || _processingQueue.isEmpty) return;

      _isProcessing = true;

      while (_processingQueue.isNotEmpty) {
        final batch = _processingQueue.removeFirst();
        final results = <Map<String, dynamic>>[];

        for (final event in batch.events) {
          try {
            final eventRaw = event['eventRaw'];
            if (eventRaw == null) continue;

            final decodedEvent = _fastJsonDecode(eventRaw);
            if (decodedEvent == null) continue;

            final eventData = decodedEvent[2] as Map<String, dynamic>?;
            if (eventData == null) continue;

            final kind = eventData['kind'] as int?;
            final eventId = eventData['id'] as String?;
            final author = eventData['pubkey'] as String?;

            if (kind == null || eventId == null || author == null) continue;

            results.add({
              'kind': kind,
              'eventId': eventId,
              'author': author,
              'eventData': eventData,
              'targetNpubs': event['targetNpubs'] ?? [],
              'priority': event['priority'] ?? 2,
            });
          } catch (e) {
            results.add({'error': 'Parse error: $e'});
          }
        }

        if (results.isNotEmpty) {
          sendPort.send({
            'type': 'batch_results',
            'results': results,
            'processed_count': results.length,
          });
        }
      }

      _isProcessing = false;
    }

    port.listen((dynamic message) {
      if (message is List && message.isNotEmpty) {
        int maxPriority = 1;
        for (final event in message) {
          final priority = event['priority'] as int? ?? 2;
          if (priority > maxPriority) maxPriority = priority;
        }

        _processingQueue.add(EventBatch(List<Map<String, dynamic>>.from(message), maxPriority));

        if (maxPriority > 2) {
          _processQueue();
        } else {
          Future.microtask(_processQueue);
        }
      }
    });
  }

  static void _fetchProcessorEntryPoint(SendPort sendPort) {
    final ReceivePort port = ReceivePort();
    sendPort.send(port.sendPort);

    final Map<String, List<String>> _batchedRequests = {};
    Timer? _batchTimer;

    void _flushBatches() {
      if (_batchedRequests.isEmpty) return;

      for (final entry in _batchedRequests.entries) {
        final type = entry.key;
        final eventIds = entry.value;

        if (eventIds.isNotEmpty) {
          sendPort.send({
            'type': type,
            'eventIds': eventIds.toSet().toList(),
            'priority': 2,
            'batch_size': eventIds.length,
          });
        }
      }

      _batchedRequests.clear();
      _batchTimer?.cancel();
      _batchTimer = null;
    }

    port.listen((dynamic message) {
      if (message is Map<String, dynamic>) {
        try {
          final type = message['type'] as String?;
          final eventIds = message['eventIds'] as List?;
          final priority = message['priority'] as int? ?? 2;

          if (type != null && eventIds != null) {
            _batchedRequests.putIfAbsent(type, () => []);
            _batchedRequests[type]!.addAll(List<String>.from(eventIds));

            if (priority > 2) {
              _flushBatches();
            } else {
              _batchTimer?.cancel();
              _batchTimer = Timer(const Duration(milliseconds: 100), _flushBatches);
            }
          }
        } catch (e) {
          sendPort.send({'error': 'Fetch processor error: $e'});
        }
      }
    });
  }

  static void _dataProcessorEntryPoint(SendPort sendPort) {
    final ReceivePort port = ReceivePort();
    sendPort.send(port.sendPort);

    final Queue<DataProcessingTask> _taskQueue = Queue();
    bool _isProcessing = false;

    void _processQueue() async {
      if (_isProcessing || _taskQueue.isEmpty) return;

      _isProcessing = true;

      while (_taskQueue.isNotEmpty) {
        final task = _taskQueue.removeFirst();

        try {
          await _processTask(task, sendPort);
        } catch (e) {
          sendPort.send({'error': 'Task processing error: $e'});
        }
      }

      _isProcessing = false;
    }

    port.listen((dynamic message) {
      if (message is Map<String, dynamic>) {
        try {
          final data = message['data'] as String?;
          final type = message['type'] as String?;
          final timestamp = message['timestamp'] as int?;

          if (data != null && type != null && timestamp != null) {
            final task = DataProcessingTask(
              data,
              type,
              DateTime.fromMillisecondsSinceEpoch(timestamp),
            );

            _taskQueue.add(task);
            Future.microtask(_processQueue);
          }
        } catch (e) {
          sendPort.send({'error': 'Message parsing error: $e'});
        }
      }
    });
  }

  static Future<void> _processTask(DataProcessingTask task, SendPort sendPort) async {
    try {
      switch (task.type) {
        case 'cache_load':
          await _processCacheLoad(task.data, sendPort);
          break;
        case 'new_notes':
          await _processNewNotes(task.data, sendPort);
          break;
        default:
          sendPort.send({'error': 'Unknown task type: ${task.type}'});
      }
    } catch (e) {
      sendPort.send({'error': 'Task execution error: $e'});
    }
  }

  static Future<void> _processCacheLoad(String data, SendPort sendPort) async {
    try {
      final jsonData = jsonDecode(data) as List<dynamic>;

      const chunkSize = 50;
      for (int i = 0; i < jsonData.length; i += chunkSize) {
        final endIndex = min(i + chunkSize, jsonData.length);
        final chunk = jsonData.sublist(i, endIndex);

        final parsedChunk = chunk.map((json) => NoteModel.fromJson(json as Map<String, dynamic>)).toList();

        sendPort.send({
          'type': 'cache_load_result',
          'data': parsedChunk.map((note) => note.toJson()).toList(),
        });
      }
    } catch (e) {
      sendPort.send({'error': 'Cache load processing error: $e'});
    }
  }

  static Future<void> _processNewNotes(String data, SendPort sendPort) async {
    try {
      final jsonData = jsonDecode(data) as List<dynamic>;

      const batchSize = 20;
      for (int i = 0; i < jsonData.length; i += batchSize) {
        final endIndex = min(i + batchSize, jsonData.length);
        final batch = jsonData.sublist(i, endIndex);

        final parsedNotes = batch.map((json) => NoteModel.fromJson(json as Map<String, dynamic>)).toList();

        sendPort.send({
          'type': 'new_notes_result',
          'data': parsedNotes.map((note) => note.toJson()).toList(),
        });
      }
    } catch (e) {
      sendPort.send({'error': 'New notes processing error: $e'});
    }
  }

  static List<dynamic>? _fastJsonDecode(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is List && decoded.length > 2 && decoded[0] != 'EOSE') {
        return decoded;
      }
    } catch (e) {
      // Silent fail for performance
    }
    return null;
  }
}
