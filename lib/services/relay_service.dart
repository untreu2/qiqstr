import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:collection';
import 'package:qiqstr/constants/relays.dart';

class RelayConnectionStats {
  int connectAttempts = 0;
  int successfulConnections = 0;
  int disconnections = 0;
  int messagesSent = 0;
  int messagesReceived = 0;
  DateTime? lastConnected;
  DateTime? lastDisconnected;
  Duration totalUptime = Duration.zero;
  DateTime? connectionStartTime;

  double get successRate => connectAttempts > 0 ? successfulConnections / connectAttempts : 0.0;
  bool get isHealthy => successRate > 0.7 && disconnections < 5;
}

class WebSocketManager {
  final List<String> relayUrls;
  final Map<String, WebSocket> _webSockets = {};
  final Map<String, Timer> _reconnectTimers = {};
  final Map<String, RelayConnectionStats> _connectionStats = {};
  final Duration connectionTimeout;
  final int maxReconnectAttempts;
  final Duration maxBackoffDelay;
  bool _isClosed = false;

  // Connection pooling and load balancing
  final Queue<String> _messageQueue = Queue();
  Timer? _messageProcessingTimer;
  bool _isProcessingMessages = false;

  // Health monitoring
  Timer? _healthCheckTimer;
  final Duration healthCheckInterval;

  WebSocketManager({
    required this.relayUrls,
    this.connectionTimeout = const Duration(seconds: 3),
    this.maxReconnectAttempts = 5,
    this.maxBackoffDelay = const Duration(minutes: 2),
    this.healthCheckInterval = const Duration(minutes: 1),
  }) {
    _initializeStats();
    _startMessageProcessing();
    _startHealthMonitoring();
  }

  void _initializeStats() {
    for (final url in relayUrls) {
      _connectionStats[url] = RelayConnectionStats();
    }
  }

  void _startMessageProcessing() {
    _messageProcessingTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _processMessageQueue();
    });
  }

  void _startHealthMonitoring() {
    _healthCheckTimer = Timer.periodic(healthCheckInterval, (_) {
      _performHealthCheck();
    });
  }

  void _performHealthCheck() {
    final now = DateTime.now();
    for (final entry in _connectionStats.entries) {
      final url = entry.key;
      final stats = entry.value;

      // Check if relay is unhealthy and needs attention
      if (!stats.isHealthy && !_webSockets.containsKey(url)) {
        // Attempt to reconnect unhealthy relays
        unawaited(_attemptReconnection(url));
      }

      // Update uptime for connected relays
      if (_webSockets.containsKey(url) && stats.connectionStartTime != null) {
        final uptime = now.difference(stats.connectionStartTime!);
        stats.totalUptime = stats.totalUptime + uptime;
        stats.connectionStartTime = now;
      }
    }
  }

  Future<void> _attemptReconnection(String url) async {
    final stats = _connectionStats[url]!;
    if (stats.connectAttempts >= maxReconnectAttempts) return;

    try {
      await _connectSingleRelay(url, null, null);
    } catch (e) {
      // Reconnection failed, will be retried in next health check
    }
  }

  List<WebSocket> get activeSockets => _webSockets.values.where((ws) => ws.readyState == WebSocket.open).toList();

  bool get isConnected => activeSockets.isNotEmpty;

  // Get healthy relays for load balancing
  List<String> get healthyRelays {
    return relayUrls.where((url) {
      final stats = _connectionStats[url];
      return stats != null && stats.isHealthy && _webSockets.containsKey(url);
    }).toList();
  }

  Future<void> connectRelays(
    List<String> targetNpubs, {
    Function(dynamic event, String relayUrl)? onEvent,
    Function(String relayUrl)? onDisconnected,
  }) async {
    final connectionFutures = relayUrls.map((relayUrl) => _connectSingleRelay(relayUrl, onEvent, onDisconnected));

    await Future.wait(connectionFutures, eagerError: false);
  }

  Future<void> _connectSingleRelay(
    String relayUrl,
    Function(dynamic event, String relayUrl)? onEvent,
    Function(String relayUrl)? onDisconnected,
  ) async {
    if (_isClosed || _webSockets.containsKey(relayUrl)) return;

    final stats = _connectionStats[relayUrl]!;
    stats.connectAttempts++;

    WebSocket? ws;
    try {
      ws = await WebSocket.connect(relayUrl).timeout(connectionTimeout);
      if (_isClosed) {
        try {
          await ws.close();
        } catch (_) {}
        return;
      }

      _webSockets[relayUrl] = ws;
      stats.successfulConnections++;
      stats.lastConnected = DateTime.now();
      stats.connectionStartTime = DateTime.now();

      ws.listen(
        (event) {
          try {
            if (!_isClosed && _webSockets.containsKey(relayUrl)) {
              stats.messagesReceived++;
              onEvent?.call(event, relayUrl);
            }
          } catch (e) {
            // Silently handle event processing errors
          }
        },
        onDone: () {
          try {
            _handleDisconnection(relayUrl, onDisconnected);
          } catch (e) {
            // Silently handle disconnection errors
          }
        },
        onError: (error) {
          try {
            // Handle specific socket errors
            if (error is SocketException) {
              // Socket closed or connection lost - handle gracefully
              _handleDisconnection(relayUrl, onDisconnected);
            } else {
              _handleDisconnection(relayUrl, onDisconnected);
            }
          } catch (e) {
            // Silently handle error handling errors
          }
        },
        cancelOnError: false, // Don't cancel on error to prevent cascade failures
      );
    } catch (e) {
      try {
        await ws?.close();
      } catch (_) {}
      _handleDisconnection(relayUrl, onDisconnected);
    }
  }

  void _handleDisconnection(
    String relayUrl,
    Function(String relayUrl)? onDisconnected,
  ) {
    _webSockets.remove(relayUrl);

    final stats = _connectionStats[relayUrl]!;
    stats.disconnections++;
    stats.lastDisconnected = DateTime.now();

    // Update uptime if we were tracking connection time
    if (stats.connectionStartTime != null) {
      final uptime = DateTime.now().difference(stats.connectionStartTime!);
      stats.totalUptime = stats.totalUptime + uptime;
      stats.connectionStartTime = null;
    }

    onDisconnected?.call(relayUrl);
  }

  Future<void> executeOnActiveSockets(FutureOr<void> Function(WebSocket ws) action) async {
    final activeWs = activeSockets;
    if (activeWs.isEmpty) return;

    final futures = activeWs.map((ws) async {
      try {
        // Check if socket is still open before executing action
        if (ws.readyState == WebSocket.open) {
          await action(ws);
        }
      } catch (e) {
        // Handle socket errors during broadcast
        if (e is SocketException) {
          // Socket closed - remove from active sockets
          _webSockets.removeWhere((key, value) => value == ws);
        }
        // Silently handle other errors
      }
    });

    await Future.wait(futures, eagerError: false);
  }

  Future<void> broadcast(String message) async {
    // Add to queue for load balancing
    _messageQueue.add(message);

    // Process immediately if queue is getting large
    if (_messageQueue.length >= 10) {
      _processMessageQueue();
    }
  }

  Future<void> instantBroadcast(String message) async {
    await _broadcastMessage(message);
  }

  Future<void> instantBroadcastToAll(String message) async {
    final activeWs = activeSockets;
    if (activeWs.isEmpty) return;

    final futures = activeWs.map((ws) async {
      try {
        if (ws.readyState == WebSocket.open) {
          _updateMessageStats(ws, message);
          ws.add(message);
        }
      } catch (e) {
        if (e is SocketException) {
          _webSockets.removeWhere((key, value) => value == ws);
        }
      }
    });

    await Future.wait(futures, eagerError: false);
  }

  void _processMessageQueue() {
    if (_isProcessingMessages || _messageQueue.isEmpty) return;

    _isProcessingMessages = true;

    Future.microtask(() async {
      try {
        final messagesToSend = <String>[];
        while (_messageQueue.isNotEmpty && messagesToSend.length < 5) {
          messagesToSend.add(_messageQueue.removeFirst());
        }

        for (final message in messagesToSend) {
          await _broadcastMessage(message);
        }
      } finally {
        _isProcessingMessages = false;
      }
    });
  }

  Future<void> _broadcastMessage(String message) async {
    final healthyRelayUrls = healthyRelays;

    if (healthyRelayUrls.isEmpty) {
      // Fallback to all active sockets if no healthy relays
      await executeOnActiveSockets((ws) {
        _updateMessageStats(ws, message);
        return ws.add(message);
      });
      return;
    }

    // Use load balancing for healthy relays
    final futures = healthyRelayUrls.map((url) async {
      final ws = _webSockets[url];
      if (ws != null && ws.readyState == WebSocket.open) {
        try {
          _updateMessageStats(ws, message);
          ws.add(message);
        } catch (e) {
          // Handle send errors
          if (e is SocketException) {
            _webSockets.remove(url);
          }
        }
      }
    });

    await Future.wait(futures, eagerError: false);
  }

  void _updateMessageStats(WebSocket ws, String message) {
    // Find which relay this socket belongs to
    for (final entry in _webSockets.entries) {
      if (entry.value == ws) {
        final stats = _connectionStats[entry.key];
        if (stats != null) {
          stats.messagesSent++;
        }
        break;
      }
    }
  }

  void reconnectRelay(
    String relayUrl,
    List<String> targetNpubs, {
    int attempt = 1,
    Function(String relayUrl)? onReconnected,
  }) {
    if (_isClosed || attempt > maxReconnectAttempts) return;

    _reconnectTimers[relayUrl]?.cancel();

    final delay = _calculateBackoffDelay(attempt);
    _reconnectTimers[relayUrl] = Timer(Duration(seconds: delay), () async {
      if (_isClosed) return;

      final stats = _connectionStats[relayUrl]!;
      stats.connectAttempts++;

      WebSocket? ws;
      try {
        ws = await WebSocket.connect(relayUrl).timeout(connectionTimeout);
        if (_isClosed) {
          try {
            await ws.close();
          } catch (_) {}
          return;
        }

        _webSockets[relayUrl] = ws;
        _reconnectTimers.remove(relayUrl);
        stats.successfulConnections++;
        stats.lastConnected = DateTime.now();
        stats.connectionStartTime = DateTime.now();

        ws.listen(
          (event) {
            // Handle events during reconnection if needed
            try {
              stats.messagesReceived++;
              // Process events silently during reconnection
            } catch (e) {
              // Silently handle event processing errors
            }
          },
          onDone: () {
            try {
              if (!_isClosed) {
                _handleDisconnection(relayUrl, null);
                reconnectRelay(relayUrl, targetNpubs, attempt: attempt + 1);
              }
            } catch (e) {
              // Silently handle reconnection errors
            }
          },
          onError: (error) {
            try {
              if (!_isClosed) {
                _handleDisconnection(relayUrl, null);
                // Handle specific socket errors during reconnection
                if (error is SocketException) {
                  // Socket closed - attempt reconnection
                  reconnectRelay(relayUrl, targetNpubs, attempt: attempt + 1);
                } else {
                  reconnectRelay(relayUrl, targetNpubs, attempt: attempt + 1);
                }
              }
            } catch (e) {
              // Silently handle error handling errors
            }
          },
          cancelOnError: false, // Don't cancel on error to prevent cascade failures
        );

        onReconnected?.call(relayUrl);
      } catch (e) {
        try {
          await ws?.close();
        } catch (_) {}
        if (!_isClosed) {
          reconnectRelay(relayUrl, targetNpubs, attempt: attempt + 1);
        }
      }
    });
  }

  int _calculateBackoffDelay(int attempt) {
    const baseDelay = 1;
    final maxDelaySeconds = maxBackoffDelay.inSeconds;
    final delay = (baseDelay * pow(2, attempt - 1)).toInt().clamp(1, maxDelaySeconds);
    final jitter = Random().nextInt((delay ~/ 2).clamp(1, 5));
    return delay + jitter;
  }

  Future<void> closeConnections() async {
    _isClosed = true;

    // Cancel all timers
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();

    _messageProcessingTimer?.cancel();
    _healthCheckTimer?.cancel();

    final closeFutures = _webSockets.values.map((ws) async {
      try {
        if (ws.readyState == WebSocket.open || ws.readyState == WebSocket.connecting) {
          await ws.close();
        }
      } catch (e) {
        // Silently handle close errors - socket might already be closed
      }
    });

    await Future.wait(closeFutures, eagerError: false);
    _webSockets.clear();
    _messageQueue.clear();
  }

  // Enhanced statistics and monitoring
  Map<String, dynamic> getConnectionStats() {
    final totalStats = {
      'totalRelays': relayUrls.length,
      'connectedRelays': _webSockets.length,
      'healthyRelays': healthyRelays.length,
      'queuedMessages': _messageQueue.length,
      'isProcessingMessages': _isProcessingMessages,
    };

    final relayStats = <String, Map<String, dynamic>>{};
    for (final entry in _connectionStats.entries) {
      final url = entry.key;
      final stats = entry.value;
      relayStats[url] = {
        'connectAttempts': stats.connectAttempts,
        'successfulConnections': stats.successfulConnections,
        'disconnections': stats.disconnections,
        'messagesSent': stats.messagesSent,
        'messagesReceived': stats.messagesReceived,
        'successRate': (stats.successRate * 100).toStringAsFixed(1) + '%',
        'isHealthy': stats.isHealthy,
        'isConnected': _webSockets.containsKey(url),
        'totalUptime': stats.totalUptime.inSeconds,
        'lastConnected': stats.lastConnected?.toIso8601String(),
        'lastDisconnected': stats.lastDisconnected?.toIso8601String(),
      };
    }

    return {
      'summary': totalStats,
      'relays': relayStats,
    };
  }

  // Force process pending messages
  void flushMessageQueue() {
    _processMessageQueue();
  }
}

class PrimalCacheClient {
  static const Duration _timeout = Duration(seconds: 5);
  static final Map<String, Map<String, String>> _profileCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheTTL = Duration(minutes: 20);
  static const int _maxCacheSize = 2000;

  // Performance metrics
  static int _cacheHits = 0;
  static int _cacheMisses = 0;
  static int _requestsSent = 0;
  static int _requestsFailed = 0;

  Future<Map<String, String>?> fetchUserProfile(String pubkey) async {
    final now = DateTime.now();
    final cached = _profileCache[pubkey];
    final timestamp = _cacheTimestamps[pubkey];

    if (cached != null && timestamp != null && now.difference(timestamp) < _cacheTTL) {
      _cacheHits++;
      return cached;
    }

    _cacheMisses++;
    _requestsSent++;

    try {
      final result = await _sendRequest([
        "REQ",
        _generateId(),
        {
          "cache": [
            "user_profile",
            {"pubkey": pubkey}
          ]
        }
      ]).then(_decodeUserProfile);

      if (result != null) {
        _profileCache[pubkey] = result;
        _cacheTimestamps[pubkey] = now;

        if (_profileCache.length > _maxCacheSize) {
          _cleanupCache();
        }
      }

      return result;
    } catch (e) {
      _requestsFailed++;
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchEvent(String eventId) async {
    _requestsSent++;

    try {
      final result = await _sendRequest([
        "REQ",
        _generateId(),
        {
          "cache": [
            "events",
            {
              "event_ids": [eventId]
            }
          ]
        }
      ]);

      return result;
    } catch (e) {
      _requestsFailed++;
      return null;
    }
  }

  static void _cleanupCache() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    // Remove expired entries
    for (final entry in _cacheTimestamps.entries) {
      if (now.difference(entry.value) > _cacheTTL) {
        expiredKeys.add(entry.key);
      }
    }

    // If still too large, remove oldest entries (LRU)
    if (_profileCache.length - expiredKeys.length > _maxCacheSize * 0.8) {
      final sortedEntries = _cacheTimestamps.entries.toList()..sort((a, b) => a.value.compareTo(b.value));

      final toRemove = (_profileCache.length - (_maxCacheSize * 0.7).toInt()).clamp(0, sortedEntries.length);
      for (int i = 0; i < toRemove; i++) {
        expiredKeys.add(sortedEntries[i].key);
      }
    }

    for (final key in expiredKeys) {
      _profileCache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }

  // Enhanced statistics
  static Map<String, dynamic> getCacheStats() {
    final hitRate = _cacheHits + _cacheMisses > 0 ? (_cacheHits / (_cacheHits + _cacheMisses) * 100).toStringAsFixed(1) : '0.0';

    final successRate = _requestsSent > 0 ? ((_requestsSent - _requestsFailed) / _requestsSent * 100).toStringAsFixed(1) : '0.0';

    return {
      'cacheSize': _profileCache.length,
      'maxCacheSize': _maxCacheSize,
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'hitRate': '$hitRate%',
      'requestsSent': _requestsSent,
      'requestsFailed': _requestsFailed,
      'successRate': '$successRate%',
    };
  }

  Future<Map<String, dynamic>?> _sendRequest(List<dynamic> request) async {
    WebSocket? ws;
    final subscriptionId = request[1];

    try {
      ws = await WebSocket.connect(cachingServerUrl).timeout(_timeout);
      final completer = Completer<Map<String, dynamic>?>();

      late StreamSubscription sub;
      sub = ws.listen(
        (message) {
          try {
            final decoded = jsonDecode(message);
            if (decoded is List && decoded.length >= 3) {
              if (decoded[0] == 'EVENT' && decoded[1] == subscriptionId) {
                if (!completer.isCompleted) {
                  completer.complete(decoded[2]);
                }
              } else if (decoded[0] == 'EOSE' && decoded[1] == subscriptionId) {
                if (!completer.isCompleted) {
                  completer.complete(null);
                }
              }
            }
          } catch (e) {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          }
        },
        onError: (error) {
          try {
            // Handle specific socket errors in cache client
            if (error is SocketException) {
              // Socket closed - complete with null
              if (!completer.isCompleted) completer.complete(null);
            } else {
              if (!completer.isCompleted) completer.complete(null);
            }
          } catch (e) {
            if (!completer.isCompleted) completer.complete(null);
          }
        },
        onDone: () {
          try {
            if (!completer.isCompleted) completer.complete(null);
          } catch (e) {
            // Silently handle completion errors
          }
        },
        cancelOnError: false, // Don't cancel on error to prevent cascade failures
      );

      ws.add(jsonEncode(request));
      final result = await completer.future.timeout(_timeout, onTimeout: () => null);

      await sub.cancel();
      await ws.close();
      return result;
    } catch (e) {
      try {
        await ws?.close();
      } catch (_) {}
      return null;
    }
  }

  Map<String, String>? _decodeUserProfile(Map<String, dynamic>? event) {
    if (event == null) return null;

    try {
      final contentRaw = event['content'];
      Map<String, dynamic> profile = {};

      if (contentRaw is String && contentRaw.isNotEmpty) {
        try {
          profile = jsonDecode(contentRaw) as Map<String, dynamic>;
        } catch (_) {}
      }

      return {
        'name': profile['name']?.toString() ?? 'Anonymous',
        'profileImage': profile['picture']?.toString() ?? '',
        'about': profile['about']?.toString() ?? '',
        'nip05': profile['nip05']?.toString() ?? '',
        'banner': profile['banner']?.toString() ?? '',
        'lud16': profile['lud16']?.toString() ?? '',
        'website': profile['website']?.toString() ?? '',
      };
    } catch (e) {
      return null;
    }
  }

  String _generateId() => DateTime.now().millisecondsSinceEpoch.toString();
}

// Helper function for fire-and-forget operations
void unawaited(Future<void> future) {
  future.catchError((error) {
    print('[RelayService] Background operation failed: $error');
  });
}
