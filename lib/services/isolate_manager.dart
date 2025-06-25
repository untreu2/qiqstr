import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:collection';
import '../models/note_model.dart';
import '../services/data_service.dart';

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

    // Event processing queue with priority
    final Queue<EventBatch> _processingQueue = Queue();
    bool _isProcessing = false;

    void _processQueue() async {
      if (_isProcessing || _processingQueue.isEmpty) return;
      
      _isProcessing = true;
      
      while (_processingQueue.isNotEmpty) {
        final batch = _processingQueue.removeFirst();
        final results = <Map<String, dynamic>>[];
        
        // Process events in batch with optimized parsing
        for (final event in batch.events) {
          try {
            final eventRaw = event['eventRaw'];
            if (eventRaw == null) continue;
            
            // Fast JSON parsing with minimal validation
            final decodedEvent = _fastJsonDecode(eventRaw);
            if (decodedEvent == null) continue;

            final eventData = decodedEvent[2] as Map<String, dynamic>?;
            if (eventData == null) continue;

            // Extract essential fields efficiently
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
            // Minimize error logging in isolate
            results.add({'error': 'Parse error'});
          }
        }
        
        // Send results in batch
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
        // Determine batch priority based on event types
        int maxPriority = 1;
        for (final event in message) {
          final priority = event['priority'] as int? ?? 2;
          if (priority > maxPriority) maxPriority = priority;
        }
        
        _processingQueue.add(EventBatch(
          List<Map<String, dynamic>>.from(message),
          maxPriority
        ));
        
        // Process immediately for high priority events
        if (maxPriority > 2) {
          _processQueue();
        } else {
          // Batch process for normal priority
          Future.microtask(_processQueue);
        }
      }
    });
  }

  static void fetchProcessorEntryPoint(SendPort sendPort) {
    final ReceivePort port = ReceivePort();
    sendPort.send(port.sendPort);

    // Batch similar requests together
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
            'eventIds': eventIds.toSet().toList(), // Remove duplicates
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
            // Batch requests by type
            _batchedRequests.putIfAbsent(type, () => []);
            _batchedRequests[type]!.addAll(List<String>.from(eventIds));
            
            // Flush immediately for high priority
            if (priority > 2) {
              _flushBatches();
            } else {
              // Batch for efficiency
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

    // Processing queues for different data types
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
      if (message is IsolateMessage) {
        switch (message.type) {
          case MessageType.cacheload:
            _cacheLoadQueue.add(message.data);
            Future.microtask(_processCacheQueue);
            break;
          case MessageType.newnotes:
            _newNotesQueue.add(message.data);
            Future.microtask(_processNotesQueue);
            break;
          case MessageType.close:
            isolateReceivePort.close();
            return;
          case MessageType.error:
            sendPort.send(IsolateMessage(MessageType.error, message.data));
            break;
        }
      } else if (message == 'close') {
        isolateReceivePort.close();
      }
    });
  }

  // Optimized JSON parsing with minimal validation
  static List<dynamic>? _fastJsonDecode(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is List &&
          decoded.length > 2 &&
          decoded[0] != 'EOSE') {
        return decoded;
      }
    } catch (e) {
      // Silent fail for performance
    }
    return null;
  }

  static void _processCacheLoad(String data, SendPort sendPort) {
    try {
      final jsonData = jsonDecode(data) as List<dynamic>;
      
      // Process in chunks to avoid memory spikes
      const chunkSize = 50;
      final chunks = <List<NoteModel>>[];
      
      for (int i = 0; i < jsonData.length; i += chunkSize) {
        final endIndex = (i + chunkSize > jsonData.length) ? jsonData.length : i + chunkSize;
        final chunk = jsonData.sublist(i, endIndex);
        
        final parsedChunk = chunk
            .map((json) => NoteModel.fromJson(json as Map<String, dynamic>))
            .toList();
        chunks.add(parsedChunk);
      }
      
      // Send chunks separately to avoid large message passing
      for (final chunk in chunks) {
        sendPort.send(IsolateMessage(MessageType.cacheload, chunk));
      }
    } catch (e) {
      sendPort.send(IsolateMessage(MessageType.error, e.toString()));
    }
  }

  static void _processNewNotes(String data, SendPort sendPort) {
    try {
      final jsonData = jsonDecode(data) as List<dynamic>;
      
      // Process in smaller batches for better responsiveness
      const batchSize = 20;
      for (int i = 0; i < jsonData.length; i += batchSize) {
        final endIndex = (i + batchSize > jsonData.length) ? jsonData.length : i + batchSize;
        final batch = jsonData.sublist(i, endIndex);
        
        final parsedNotes = batch
            .map((json) => NoteModel.fromJson(json as Map<String, dynamic>))
            .toList();
        
        sendPort.send(IsolateMessage(MessageType.newnotes, parsedNotes));
      }
    } catch (e) {
      sendPort.send(IsolateMessage(MessageType.error, e.toString()));
    }
  }
}
