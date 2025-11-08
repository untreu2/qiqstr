import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

class EventParserIsolate {
  static EventParserIsolate? _instance;
  static EventParserIsolate get instance => _instance ??= EventParserIsolate._internal();

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  final Map<int, Completer<dynamic>> _pendingRequests = {};
  int _requestCounter = 0;
  bool _isInitialized = false;

  EventParserIsolate._internal();

  Future<void> initialize() async {
    if (_isInitialized) return;

    _receivePort = ReceivePort();
    
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _isInitialized = true;
        debugPrint('[EventParserIsolate] Isolate initialized and ready');
      } else if (message is Map) {
        final requestId = message['requestId'] as int;
        final result = message['result'];
        final error = message['error'];

        final completer = _pendingRequests.remove(requestId);
        if (completer != null) {
          if (error != null) {
            completer.completeError(error);
          } else {
            completer.complete(result);
          }
        }
      }
    });

    _isolate = await Isolate.spawn(_isolateEntry, _receivePort!.sendPort);
    
    await Future.delayed(const Duration(milliseconds: 100));
  }

  static void _isolateEntry(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      if (message is Map) {
        final requestId = message['requestId'] as int;
        final type = message['type'] as String;
        final data = message['data'];

        try {
          dynamic result;

          switch (type) {
            case 'parseJson':
              result = {'data': jsonDecode(data as String)};
              break;
            case 'parseJsonList':
              final list = data as List<String>;
              result = list.map((json) => jsonDecode(json)).toList();
              break;
            case 'encodeJson':
              result = jsonEncode(data);
              break;
            default:
              throw Exception('Unknown operation type: $type');
          }

          sendPort.send({
            'requestId': requestId,
            'result': result,
          });
        } catch (e) {
          sendPort.send({
            'requestId': requestId,
            'error': e.toString(),
          });
        }
      }
    });
  }

  Future<Map<String, dynamic>> parseJson(String jsonString) async {
    if (!_isInitialized || _sendPort == null) {
      await initialize();
    }

    final requestId = _requestCounter++;
    final completer = Completer<dynamic>();
    _pendingRequests[requestId] = completer;

    _sendPort!.send({
      'requestId': requestId,
      'type': 'parseJson',
      'data': jsonString,
    });

    return await completer.future as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> parseJsonList(List<String> jsonStrings) async {
    if (!_isInitialized || _sendPort == null) {
      await initialize();
    }

    final requestId = _requestCounter++;
    final completer = Completer<dynamic>();
    _pendingRequests[requestId] = completer;

    _sendPort!.send({
      'requestId': requestId,
      'type': 'parseJsonList',
      'data': jsonStrings,
    });

    final result = await completer.future as List;
    return result.cast<Map<String, dynamic>>();
  }

  Future<String> encodeJson(dynamic data) async {
    if (!_isInitialized || _sendPort == null) {
      await initialize();
    }

    final requestId = _requestCounter++;
    final completer = Completer<dynamic>();
    _pendingRequests[requestId] = completer;

    _sendPort!.send({
      'requestId': requestId,
      'type': 'encodeJson',
      'data': data,
    });

    return await completer.future as String;
  }

  void dispose() {
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _pendingRequests.clear();
    _isInitialized = false;
  }
}

