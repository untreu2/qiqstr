import 'dart:async';
import 'dart:io';
import 'dart:collection';
import '../services/time_service.dart';

class NetworkBatchProcessor {
  static const int _maxBatchSize = 50;
  static const Duration _batchDelay = Duration(milliseconds: 20);

  final Queue<String> _messageQueue = Queue<String>();
  final List<WebSocket> _targetSockets;
  Timer? _batchTimer;
  bool _isProcessing = false;

  NetworkBatchProcessor(this._targetSockets);

  void queueMessage(String message) {
    _messageQueue.add(message);
    _scheduleBatchProcess();
  }

  void _scheduleBatchProcess() {
    if (_batchTimer?.isActive == true) return;

    _batchTimer = Timer(_batchDelay, () {
      if (!_isProcessing && _messageQueue.isNotEmpty) {
        _processBatch();
      }
    });
  }

  Future<void> _processBatch() async {
    if (_isProcessing || _messageQueue.isEmpty) return;

    _isProcessing = true;
    final batch = <String>[];

    while (_messageQueue.isNotEmpty && batch.length < _maxBatchSize) {
      batch.add(_messageQueue.removeFirst());
    }

    final activeSockets = _targetSockets.where((ws) => ws.readyState == WebSocket.open).toList();

    if (activeSockets.isNotEmpty && batch.isNotEmpty) {
      await _sendBatchOptimized(activeSockets, batch);
    }

    _isProcessing = false;

    if (_messageQueue.isNotEmpty) {
      _scheduleBatchProcess();
    }
  }

  Future<void> _sendBatchOptimized(List<WebSocket> sockets, List<String> messages) async {
    final futures = <Future>[];

    for (final socket in sockets) {
      for (final message in messages) {
        futures.add(_sendSafeOptimized(socket, message));

        if (futures.length % 10 == 0) {
          await Future.delayed(Duration.zero);
        }
      }
    }

    await Future.wait(futures, eagerError: false);
  }

  Future<void> _sendSafeOptimized(WebSocket socket, String message) async {
    try {
      if (socket.readyState == WebSocket.open) {
        socket.add(message);
      }
    } catch (e) {}
  }

  void dispose() {
    _batchTimer?.cancel();
    _messageQueue.clear();
  }
}

class OptimizedConnectionPool {
  static const int _maxPoolSize = 20;
  static const Duration _connectionTTL = Duration(minutes: 10);

  final Map<String, _PooledConnection> _connections = {};
  final Queue<String> _connectionQueue = Queue<String>();
  Timer? _cleanupTimer;

  OptimizedConnectionPool() {
    _startCleanupTimer();
  }

  Future<WebSocket?> getConnection(String url) async {
    final existing = _connections[url];

    if (existing != null && existing.isValid) {
      existing.updateLastUsed();
      return existing.socket;
    }

    if (existing != null) {
      _connections.remove(url);
      _connectionQueue.remove(url);
    }

    if (_connections.length < _maxPoolSize) {
      return await _createOptimizedConnection(url);
    }

    final oldestUrl = _connectionQueue.removeFirst();
    final oldConnection = _connections.remove(oldestUrl);
    oldConnection?.dispose();

    return await _createOptimizedConnection(url);
  }

  Future<WebSocket?> _createOptimizedConnection(String url) async {
    try {
      final socket = await WebSocket.connect(
        url,
        protocols: ['nostr'],
      ).timeout(const Duration(seconds: 5));

      final pooledConnection = _PooledConnection(socket);
      _connections[url] = pooledConnection;
      _connectionQueue.add(url);

      return socket;
    } catch (e) {
      return null;
    }
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(Duration(minutes: 2), (_) {
      _performCleanup();
    });
  }

  void _performCleanup() {
    final now = timeService.now;
    final expiredUrls = <String>[];

    for (final entry in _connections.entries) {
      if (now.difference(entry.value.lastUsed) > _connectionTTL) {
        expiredUrls.add(entry.key);
      }
    }

    for (final url in expiredUrls) {
      final connection = _connections.remove(url);
      connection?.dispose();
      _connectionQueue.remove(url);
    }
  }

  void dispose() {
    _cleanupTimer?.cancel();
    for (final connection in _connections.values) {
      connection.dispose();
    }
    _connections.clear();
    _connectionQueue.clear();
  }
}

class _PooledConnection {
  final WebSocket socket;
  DateTime lastUsed;

  _PooledConnection(this.socket) : lastUsed = timeService.now;

  bool get isValid => socket.readyState == WebSocket.open;

  void updateLastUsed() {
    lastUsed = timeService.now;
  }

  void dispose() {
    try {
      socket.close();
    } catch (e) {}
  }
}

class RequestDeduplicator {
  static const Duration _cacheDuration = Duration(seconds: 5);

  final Map<String, DateTime> _recentRequests = {};
  final Map<String, Completer> _pendingRequests = {};

  bool shouldSkipRequest(String requestKey) {
    final lastRequest = _recentRequests[requestKey];

    if (lastRequest != null && timeService.difference(lastRequest) < _cacheDuration) {
      return true;
    }

    return false;
  }

  void registerRequest(String requestKey) {
    _recentRequests[requestKey] = timeService.now;
  }

  Future<T>? getPendingRequest<T>(String requestKey) {
    final pending = _pendingRequests[requestKey];
    return pending?.future as Future<T>?;
  }

  void registerPending(String requestKey, Completer completer) {
    _pendingRequests[requestKey] = completer;
  }

  void completePending(String requestKey, dynamic result) {
    final pending = _pendingRequests.remove(requestKey);
    pending?.complete(result);
  }

  void cleanup() {
    final now = timeService.now;
    final expiredKeys = <String>[];

    for (final entry in _recentRequests.entries) {
      if (now.difference(entry.value) > _cacheDuration) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _recentRequests.remove(key);
    }
  }
}

final networkBatchProcessor = NetworkBatchProcessor([]);
final connectionPool = OptimizedConnectionPool();
final requestDeduplicator = RequestDeduplicator();
