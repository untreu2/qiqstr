import 'dart:async';
import 'dart:isolate';
import 'dart:collection';

class IsolateMessageBatcher {
  static const int _maxBatchSize = 20;
  static const Duration _batchDelay = Duration(milliseconds: 10);

  final SendPort _sendPort;
  final Queue<Map<String, dynamic>> _messageQueue = Queue<Map<String, dynamic>>();
  Timer? _batchTimer;
  bool _isProcessing = false;

  IsolateMessageBatcher(this._sendPort);

  void queueMessage(Map<String, dynamic> message) {
    _messageQueue.add(message);
    _scheduleBatchSend();
  }

  void sendImmediate(Map<String, dynamic> message) {
    _sendPort.send(message);
  }

  void _scheduleBatchSend() {
    if (_batchTimer?.isActive == true) return;

    _batchTimer = Timer(_batchDelay, () {
      if (!_isProcessing && _messageQueue.isNotEmpty) {
        _processBatch();
      }
    });
  }

  void _processBatch() {
    if (_isProcessing || _messageQueue.isEmpty) return;

    _isProcessing = true;
    final batch = <Map<String, dynamic>>[];

    while (_messageQueue.isNotEmpty && batch.length < _maxBatchSize) {
      batch.add(_messageQueue.removeFirst());
    }

    if (batch.isNotEmpty) {
      _sendPort.send({
        'type': 'batch',
        'messages': batch,
        'count': batch.length,
      });
    }

    _isProcessing = false;

    if (_messageQueue.isNotEmpty) {
      _scheduleBatchSend();
    }
  }

  void dispose() {
    _batchTimer?.cancel();

    if (_messageQueue.isNotEmpty) {
      final remaining = _messageQueue.toList();
      _messageQueue.clear();

      if (remaining.isNotEmpty) {
        _sendPort.send({
          'type': 'batch',
          'messages': remaining,
          'count': remaining.length,
        });
      }
    }
  }
}

class OptimizedSerializer {
  static Map<String, dynamic> serializeForIsolate(dynamic data) {
    if (data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(data);
    }

    if (data is List) {
      return {
        'type': 'list',
        'data': data.map((item) => serializeForIsolate(item)).toList(),
      };
    }

    return {
      'type': 'data',
      'value': data.toString(),
    };
  }

  static dynamic deserializeFromIsolate(Map<String, dynamic> serialized) {
    final type = serialized['type'];

    switch (type) {
      case 'list':
        final data = serialized['data'] as List;
        return data.map((item) => deserializeFromIsolate(item as Map<String, dynamic>)).toList();

      case 'data':
        return serialized['value'];

      default:
        return serialized;
    }
  }
}

class OptimizedIsolatePool {
  static const int _maxIsolates = 3;
  static const Duration _isolateIdleTimeout = Duration(minutes: 2);

  final List<_PooledIsolate> _availableIsolates = [];
  final List<_PooledIsolate> _busyIsolates = [];
  final Map<String, _PooledIsolate> _isolatesByType = {};

  Timer? _cleanupTimer;

  OptimizedIsolatePool() {
    _startCleanupTimer();
  }

  Future<SendPort?> getIsolate(String type, void Function(SendPort) entryPoint) async {
    final existing = _isolatesByType[type];
    if (existing != null && existing.isAlive) {
      existing.updateLastUsed();
      return existing.sendPort;
    }

    if (_availableIsolates.isNotEmpty) {
      final isolate = _availableIsolates.removeAt(0);
      _busyIsolates.add(isolate);
      _isolatesByType[type] = isolate;
      return isolate.sendPort;
    }

    if (_busyIsolates.length < _maxIsolates) {
      return await _createOptimizedIsolate(type, entryPoint);
    }

    return null;
  }

  Future<SendPort?> _createOptimizedIsolate(String type, void Function(SendPort) entryPoint) async {
    try {
      final receivePort = ReceivePort();
      final isolate = await Isolate.spawn(entryPoint, receivePort.sendPort);

      final completer = Completer<SendPort>();

      receivePort.listen((message) {
        if (message is SendPort && !completer.isCompleted) {
          completer.complete(message);
        }
      });

      final sendPort = await completer.future.timeout(Duration(seconds: 5));

      final pooledIsolate = _PooledIsolate(isolate, sendPort, receivePort);
      _busyIsolates.add(pooledIsolate);
      _isolatesByType[type] = pooledIsolate;

      return sendPort;
    } catch (e) {
      return null;
    }
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(Duration(minutes: 1), (_) {
      _performCleanup();
    });
  }

  void _performCleanup() {
    final now = DateTime.now();
    final toRemove = <_PooledIsolate>[];

    for (final isolate in _availableIsolates) {
      if (now.difference(isolate.lastUsed) > _isolateIdleTimeout) {
        toRemove.add(isolate);
      }
    }

    for (final isolate in toRemove) {
      _availableIsolates.remove(isolate);
      isolate.dispose();
    }
  }

  void dispose() {
    _cleanupTimer?.cancel();

    for (final isolate in [..._availableIsolates, ..._busyIsolates]) {
      isolate.dispose();
    }

    _availableIsolates.clear();
    _busyIsolates.clear();
    _isolatesByType.clear();
  }
}

class _PooledIsolate {
  final Isolate isolate;
  final SendPort sendPort;
  final ReceivePort receivePort;
  DateTime lastUsed;

  _PooledIsolate(this.isolate, this.sendPort, this.receivePort) : lastUsed = DateTime.now();

  bool get isAlive {
    try {
      return !receivePort.isBroadcast;
    } catch (e) {
      return false;
    }
  }

  void updateLastUsed() {
    lastUsed = DateTime.now();
  }

  void dispose() {
    try {
      receivePort.close();
      isolate.kill();
    } catch (e) {}
  }
}

class CommunicationThrottler {
  static const Duration _throttleInterval = Duration(milliseconds: 5);

  final Map<String, DateTime> _lastCommunication = {};

  bool shouldThrottle(String channel) {
    final last = _lastCommunication[channel];
    if (last == null) {
      _lastCommunication[channel] = DateTime.now();
      return false;
    }

    final now = DateTime.now();
    if (now.difference(last) < _throttleInterval) {
      return true;
    }

    _lastCommunication[channel] = now;
    return false;
  }

  void cleanup() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    for (final entry in _lastCommunication.entries) {
      if (now.difference(entry.value) > Duration(seconds: 10)) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _lastCommunication.remove(key);
    }
  }
}

final isolatePool = OptimizedIsolatePool();
final communicationThrottler = CommunicationThrottler();
