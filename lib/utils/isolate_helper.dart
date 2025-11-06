import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

class IsolateHelper {
  static Future<T> compute<T, P>(T Function(P) callback, P param) async {
    if (kDebugMode && kIsWeb) {
      return callback(param);
    }
    
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      _isolateEntry<T, P>,
      _IsolateParams<T, P>(
        callback: callback,
        param: param,
        sendPort: receivePort.sendPort,
      ),
    );
    
    final completer = Completer<T>();
    receivePort.listen((message) {
      if (message is T) {
        completer.complete(message);
      } else if (message is _IsolateError) {
        completer.completeError(message.error, message.stackTrace);
      }
      receivePort.close();
      isolate.kill();
    });
    
    return completer.future;
  }

  static void _isolateEntry<T, P>(_IsolateParams<T, P> params) {
    try {
      final result = params.callback(params.param);
      params.sendPort.send(result);
    } catch (e, stack) {
      params.sendPort.send(_IsolateError(e, stack));
    }
  }
}

class _IsolateParams<T, P> {
  final T Function(P) callback;
  final P param;
  final SendPort sendPort;

  const _IsolateParams({
    required this.callback,
    required this.param,
    required this.sendPort,
  });
}

class _IsolateError {
  final Object error;
  final StackTrace stackTrace;

  const _IsolateError(this.error, this.stackTrace);
}

