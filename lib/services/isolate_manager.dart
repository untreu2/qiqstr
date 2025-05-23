import 'dart:convert';
import 'dart:isolate';
import '../models/note_model.dart';
import '../services/data_service.dart';

class IsolateManager {
  static void eventProcessorEntryPoint(SendPort sendPort) {
    final ReceivePort port = ReceivePort();
    sendPort.send(port.sendPort);

    port.listen((dynamic message) async {
      if (message is List) {
        for (final event in message) {
          try {
            final decodedEvent = jsonDecode(event['eventRaw']);
            if (decodedEvent is List &&
                decodedEvent.isNotEmpty &&
                decodedEvent[0] == 'EOSE') continue;

            final targetNpubs = List<String>.from(event['targetNpubs']);
            final int priority = event['priority'] ?? 2;

            if (decodedEvent is List && decodedEvent.length > 2) {
              final kind = decodedEvent[2]['kind'] as int;
              final eventId = decodedEvent[2]['id'] as String;
              final author = decodedEvent[2]['pubkey'] as String;

              sendPort.send({
                'kind': kind,
                'eventId': eventId,
                'author': author,
                'eventData': decodedEvent[2],
                'targetNpubs': targetNpubs,
                'priority': priority,
              });
            } else {
              sendPort
                  .send({'error': 'Unexpected event format: $decodedEvent'});
            }
          } catch (e) {
            sendPort.send({'error': e.toString()});
          }
        }
      } else {
        print(
            '[EventProcessor] Unexpected message type: ${message.runtimeType}');
      }
    });
  }

  static void fetchProcessorEntryPoint(SendPort sendPort) {
    final ReceivePort port = ReceivePort();
    sendPort.send(port.sendPort);

    port.listen((dynamic message) async {
      if (message is Map<String, dynamic>) {
        try {
          final String type = message['type'];
          final List<String> eventIds = List<String>.from(message['eventIds']);
          final int priority = message['priority'] ?? 2;

          sendPort.send({
            'type': type,
            'eventIds': eventIds,
            'priority': priority,
          });
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
            break;
          case MessageType.error:
            sendPort.send(IsolateMessage(MessageType.error, message.data));
            break;
        }
      } else if (message is String && message == 'close') {
        isolateReceivePort.close();
      }
    });
  }

  static void _processCacheLoad(String data, SendPort sendPort) {
    try {
      final List<dynamic> jsonData = json.decode(data);
      final List<NoteModel> parsedNotes =
          jsonData.map((json) => NoteModel.fromJson(json)).toList();
      sendPort.send(IsolateMessage(MessageType.cacheload, parsedNotes));
    } catch (e) {
      sendPort.send(IsolateMessage(MessageType.error, e.toString()));
    }
  }

  static void _processNewNotes(String data, SendPort sendPort) {
    try {
      final List<dynamic> jsonData = json.decode(data);
      final List<NoteModel> parsedNotes =
          jsonData.map((json) => NoteModel.fromJson(json)).toList();
      sendPort.send(IsolateMessage(MessageType.newnotes, parsedNotes));
    } catch (e) {
      sendPort.send(IsolateMessage(MessageType.error, e.toString()));
    }
  }
}
