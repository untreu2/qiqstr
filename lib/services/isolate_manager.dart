import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:collection';
import '../models/note_model.dart';

class EventBatch {
  final List<Map<String, dynamic>> events;
  final DateTime timestamp;
  final int priority;

  EventBatch(this.events, this.priority) : timestamp = DateTime.now();
}

class IsolateManager {
  static void eventProcessorEntryPoint(SendPort sendPort) {
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
            results.add({'error': 'Parse error'});
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

  static void fetchProcessorEntryPoint(SendPort sendPort) {
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
          sendPort.send({'error': 'Fetch processor error'});
        }
      }
    });
  }

  static void dataProcessorEntryPoint(SendPort sendPort) {
    final ReceivePort isolateReceivePort = ReceivePort();
    sendPort.send(isolateReceivePort.sendPort);

    final Queue<String> _cacheLoadQueue = Queue();
    final Queue<String> _newNotesQueue = Queue();
    bool _isProcessingCache = false;
    bool _isProcessingNotes = false;

    void _processCacheQueue() async {
      if (_isProcessingCache || _cacheLoadQueue.isEmpty) return;

      _isProcessingCache = true;

      while (_cacheLoadQueue.isNotEmpty) {
        final data = _cacheLoadQueue.removeFirst();
        _processCacheLoad(data, sendPort);
      }

      _isProcessingCache = false;
    }

    void _processNotesQueue() async {
      if (_isProcessingNotes || _newNotesQueue.isEmpty) return;

      _isProcessingNotes = true;

      while (_newNotesQueue.isNotEmpty) {
        final data = _newNotesQueue.removeFirst();
        _processNewNotes(data, sendPort);
      }

      _isProcessingNotes = false;
    }

    isolateReceivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        final type = message['type'] as String?;
        final data = message['data'];

        switch (type) {
          case 'cacheload':
            _cacheLoadQueue.add(data.toString());
            Future.microtask(_processCacheQueue);
            break;
          case 'newnotes':
            _newNotesQueue.add(data.toString());
            Future.microtask(_processNotesQueue);
            break;
          case 'close':
            isolateReceivePort.close();
            return;
          case 'error':
            sendPort.send({'type': 'error', 'data': data});
            break;
        }
      } else if (message == 'close') {
        isolateReceivePort.close();
      }
    });
  }

  static List<dynamic>? _fastJsonDecode(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is List && decoded.length > 2 && decoded[0] != 'EOSE') {
        return decoded;
      }
    } catch (e) {}
    return null;
  }

  static void _processCacheLoad(String data, SendPort sendPort) {
    try {
      final jsonData = jsonDecode(data) as List<dynamic>;

      const chunkSize = 50;
      final chunks = <List<NoteModel>>[];

      for (int i = 0; i < jsonData.length; i += chunkSize) {
        final endIndex = (i + chunkSize > jsonData.length) ? jsonData.length : i + chunkSize;
        final chunk = jsonData.sublist(i, endIndex);

        final parsedChunk = chunk.map((json) => NoteModel.fromJson(json as Map<String, dynamic>)).toList();
        chunks.add(parsedChunk);
      }

      for (final chunk in chunks) {
        sendPort.send({'type': 'cacheload', 'data': chunk});
      }
    } catch (e) {
      sendPort.send({'type': 'error', 'data': e.toString()});
    }
  }

  static void _processNewNotes(String data, SendPort sendPort) {
    try {
      final jsonData = jsonDecode(data) as List<dynamic>;

      const batchSize = 20;
      for (int i = 0; i < jsonData.length; i += batchSize) {
        final endIndex = (i + batchSize > jsonData.length) ? jsonData.length : i + batchSize;
        final batch = jsonData.sublist(i, endIndex);

        final parsedNotes = batch.map((json) => NoteModel.fromJson(json as Map<String, dynamic>)).toList();

        sendPort.send({'type': 'newnotes', 'data': parsedNotes});
      }
    } catch (e) {
      sendPort.send({'type': 'error', 'data': e.toString()});
    }
  }
}
