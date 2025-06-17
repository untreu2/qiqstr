import 'dart:convert';
import 'dart:isolate';
import '../models/note_model.dart';
import '../services/data_service.dart';

class IsolateManager {
  static void eventProcessorEntryPoint(SendPort sendPort) {
    final ReceivePort port = ReceivePort();
    sendPort.send(port.sendPort);

    port.listen((dynamic message) {
      if (message is List && message.isNotEmpty) {
        final results = <Map<String, dynamic>>[];
        
        for (final event in message) {
          try {
            final eventRaw = event['eventRaw'];
            if (eventRaw == null) continue;
            
            final decodedEvent = jsonDecode(eventRaw);
            if (decodedEvent is! List ||
                decodedEvent.length <= 2 ||
                decodedEvent[0] == 'EOSE') continue;

            final eventData = decodedEvent[2];
            if (eventData is! Map<String, dynamic>) continue;

            final kind = eventData['kind'];
            final eventId = eventData['id'];
            final author = eventData['pubkey'];
            
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
            results.add({'error': e.toString()});
          }
        }
        
        for (final result in results) {
          sendPort.send(result);
        }
      }
    });
  }

  static void fetchProcessorEntryPoint(SendPort sendPort) {
    final ReceivePort port = ReceivePort();
    sendPort.send(port.sendPort);

    port.listen((dynamic message) {
      if (message is Map<String, dynamic>) {
        try {
          final type = message['type'];
          final eventIds = message['eventIds'];
          final priority = message['priority'] ?? 2;

          if (type != null && eventIds is List) {
            sendPort.send({
              'type': type,
              'eventIds': List<String>.from(eventIds),
              'priority': priority,
            });
          }
        } catch (e) {
          sendPort.send({'error': e.toString()});
        }
      }
    });
  }

  static void dataProcessorEntryPoint(SendPort sendPort) {
    final ReceivePort isolateReceivePort = ReceivePort();
    sendPort.send(isolateReceivePort.sendPort);

    isolateReceivePort.listen((message) {
      if (message is IsolateMessage) {
        switch (message.type) {
          case MessageType.cacheload:
            _processCacheLoad(message.data, sendPort);
            break;
          case MessageType.newnotes:
            _processNewNotes(message.data, sendPort);
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

  static void _processCacheLoad(String data, SendPort sendPort) {
    try {
      final jsonData = jsonDecode(data) as List<dynamic>;
      final parsedNotes = jsonData
          .map((json) => NoteModel.fromJson(json as Map<String, dynamic>))
          .toList();
      sendPort.send(IsolateMessage(MessageType.cacheload, parsedNotes));
    } catch (e) {
      sendPort.send(IsolateMessage(MessageType.error, e.toString()));
    }
  }

  static void _processNewNotes(String data, SendPort sendPort) {
    try {
      final jsonData = jsonDecode(data) as List<dynamic>;
      final parsedNotes = jsonData
          .map((json) => NoteModel.fromJson(json as Map<String, dynamic>))
          .toList();
      sendPort.send(IsolateMessage(MessageType.newnotes, parsedNotes));
    } catch (e) {
      sendPort.send(IsolateMessage(MessageType.error, e.toString()));
    }
  }
}
