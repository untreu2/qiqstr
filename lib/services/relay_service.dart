import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:qiqstr/constants/relays.dart';
import 'time_service.dart';

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
  static WebSocketManager? _instance;
  static WebSocketManager get instance {
    _instance ??= WebSocketManager._internal();
    return _instance!;
  }

  final List<String> relayUrls = [];
  final Map<String, WebSocket> _webSockets = {};
  final Map<String, Timer> _reconnectTimers = {};
  final Map<String, RelayConnectionStats> _connectionStats = {};
  final Duration connectionTimeout = const Duration(seconds: 3);
  final int maxReconnectAttempts = 5;
  final Duration maxBackoffDelay = const Duration(minutes: 2);
  bool _isClosed = false;
  bool _isInitialized = false;

  final Queue<String> _messageQueue = Queue();
  Timer? _messageProcessingTimer;
  bool _isProcessingMessages = false;

  Timer? _healthCheckTimer;
  final Duration healthCheckInterval = const Duration(minutes: 1);

  WebSocketManager._internal() {
    _startMessageProcessing();
    _startHealthMonitoring();
    
    _ensureInitialized();
  }

  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;
    
    try {
      if (kDebugMode) {
        print('[WebSocketManager] Initializing relay list...');
      }
      
      
      final customRelays = await getRelaySetMainSockets();
      
      if (relayUrls.isEmpty) {
        relayUrls.addAll(customRelays);
        _initializeStats();
        
        if (kDebugMode) {
          print('[WebSocketManager] Initialized with ${customRelays.length} relays: $customRelays');
        }
      }
      
      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) {
        print('[WebSocketManager] Error initializing relays: $e');
      }
      
      if (relayUrls.isEmpty) {
        relayUrls.addAll(relaySetMainSockets);
        _initializeStats();
      }
      _isInitialized = true;
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _initializeStats() {
    for (final url in relayUrls) {
      _connectionStats[url] = RelayConnectionStats();
    }
  }

  void _startMessageProcessing() {
    _messageProcessingTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      Future.microtask(() => _processMessageQueue());
    });
  }

  void _startHealthMonitoring() {
    _healthCheckTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      Future.microtask(() => _performHealthCheck());
    });
  }

  void _performHealthCheck() {
    Future.microtask(() async {
      final now = timeService.now;

      final entries = _connectionStats.entries.toList();
      const batchSize = 3;

      for (int i = 0; i < entries.length; i += batchSize) {
        final end = (i + batchSize > entries.length) ? entries.length : i + batchSize;
        final batch = entries.sublist(i, end);

        for (final entry in batch) {
          final url = entry.key;
          final stats = entry.value;

          if (!stats.isHealthy && !_webSockets.containsKey(url)) {
            unawaited(_attemptReconnection(url));
          }

          if (_webSockets.containsKey(url) && stats.connectionStartTime != null) {
            final uptime = now.difference(stats.connectionStartTime!);
            stats.totalUptime = stats.totalUptime + uptime;
            stats.connectionStartTime = now;
          }
        }

        await Future.delayed(Duration.zero);
      }
    });
  }

  Future<void> _attemptReconnection(String url) async {
    final stats = _connectionStats[url]!;
    if (stats.connectAttempts >= maxReconnectAttempts) return;

    try {
      await _connectSingleRelay(url, null, null);
    } catch (e) {
      
    }
  }

  List<WebSocket> get activeSockets => _webSockets.values.where((ws) => ws.readyState == WebSocket.open).toList();

  bool get isConnected => activeSockets.isNotEmpty;

  List<String> get healthyRelays {
    return relayUrls.where((url) {
      final stats = _connectionStats[url];
      return stats != null && stats.isHealthy && _webSockets.containsKey(url);
    }).toList();
  }

  final Map<String, Function(dynamic event, String relayUrl)?> _eventHandlers = {};
  final Map<String, Function(String relayUrl)?> _disconnectHandlers = {};

  Future<void> connectRelays(
    List<String> targetNpubs, {
    Function(dynamic event, String relayUrl)? onEvent,
    Function(String relayUrl)? onDisconnected,
    String? serviceId,
  }) async {
    
    await _ensureInitialized();
    
    if (serviceId != null) {
      _eventHandlers[serviceId] = onEvent;
      _disconnectHandlers[serviceId] = onDisconnected;
    }

    if (_webSockets.isNotEmpty) {
      return;
    }

    if (kDebugMode) {
      print('[WebSocketManager] Connecting to ${relayUrls.length} relays: $relayUrls');
    }

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

              for (final handler in _eventHandlers.values) {
                if (handler != null) {
                  try {
                    handler(event, relayUrl);
                  } catch (e) {
                    if (kDebugMode) {
                      print('[WebSocketManager] Error in event handler: $e');
                    }
                  }
                }
              }

              onEvent?.call(event, relayUrl);
            }
          } catch (e) {
            
          }
        },
        onDone: () {
          try {
            _handleDisconnection(relayUrl, onDisconnected);
          } catch (e) {
            
          }
        },
        onError: (error) {
          try {
            if (error is SocketException) {
              _handleDisconnection(relayUrl, onDisconnected);
            } else {
              _handleDisconnection(relayUrl, onDisconnected);
            }
          } catch (e) {
            
          }
        },
        cancelOnError: false,
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

    if (stats.connectionStartTime != null) {
      final uptime = DateTime.now().difference(stats.connectionStartTime!);
      stats.totalUptime = stats.totalUptime + uptime;
      stats.connectionStartTime = null;
    }

    for (final handler in _disconnectHandlers.values) {
      if (handler != null) {
        try {
          handler(relayUrl);
        } catch (e) {
          if (kDebugMode) {
            print('[WebSocketManager] Error in disconnect handler: $e');
          }
        }
      }
    }

    onDisconnected?.call(relayUrl);
  }

  void unregisterService(String serviceId) {
    _eventHandlers.remove(serviceId);
    _disconnectHandlers.remove(serviceId);
  }

  Future<void> executeOnActiveSockets(FutureOr<void> Function(WebSocket ws) action) async {
    final activeWs = activeSockets;
    if (activeWs.isEmpty) return;

    final futures = activeWs.map((ws) async {
      try {
        if (ws.readyState == WebSocket.open) {
          await action(ws);
        }
      } catch (e) {
        if (e is SocketException) {
          _webSockets.removeWhere((key, value) => value == ws);
        }
      }
    });

    await Future.wait(futures, eagerError: false);
  }

  Future<void> broadcast(String message) async {
    _messageQueue.add(message);

    if (_messageQueue.length >= 5) {
      _processMessageQueue();
    }
  }

  Future<void> priorityBroadcast(String message) async {
    await _broadcastMessage(message);
  }

  Future<void> priorityBroadcastToAll(String message) async {
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
        while (_messageQueue.isNotEmpty && messagesToSend.length < 10) {
          messagesToSend.add(_messageQueue.removeFirst());
        }

        for (int i = 0; i < messagesToSend.length; i++) {
          await _broadcastMessage(messagesToSend[i]);

          if (i % 2 == 0) {
            await Future.delayed(Duration.zero);
          }
        }
      } finally {
        _isProcessingMessages = false;
      }
    });
  }

  Future<void> _broadcastMessage(String message) async {
    final healthyRelayUrls = healthyRelays;

    if (healthyRelayUrls.isEmpty) {
      await executeOnActiveSockets((ws) {
        _updateMessageStats(ws, message);
        return ws.add(message);
      });
      return;
    }

    final futures = healthyRelayUrls.map((url) async {
      final ws = _webSockets[url];
      if (ws != null && ws.readyState == WebSocket.open) {
        try {
          _updateMessageStats(ws, message);
          ws.add(message);
        } catch (e) {
          if (e is SocketException) {
            _webSockets.remove(url);
          }
        }
      }
    });

    await Future.wait(futures, eagerError: false);
  }

  void _updateMessageStats(WebSocket ws, String message) {
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
            try {
              stats.messagesReceived++;

              for (final handler in _eventHandlers.values) {
                if (handler != null) {
                  try {
                    handler(event, relayUrl);
                  } catch (e) {
                    if (kDebugMode) {
                      print('[WebSocketManager] Error in reconnection event handler: $e');
                    }
                  }
                }
              }
            } catch (e) {
              
            }
          },
          onDone: () {
            try {
              if (!_isClosed) {
                _handleDisconnection(relayUrl, null);
                reconnectRelay(relayUrl, targetNpubs, attempt: attempt + 1);
              }
            } catch (e) {
              
            }
          },
          onError: (error) {
            try {
              if (!_isClosed) {
                _handleDisconnection(relayUrl, null);

                if (error is SocketException) {
                  reconnectRelay(relayUrl, targetNpubs, attempt: attempt + 1);
                } else {
                  reconnectRelay(relayUrl, targetNpubs, attempt: attempt + 1);
                }
              }
            } catch (e) {
              
            }
          },
          cancelOnError: false,
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

    final maxJitter = (delay ~/ 2).clamp(1, 5);
    final jitter = (DateTime.now().millisecondsSinceEpoch % maxJitter);
    return delay + jitter;
  }

  Future<void> closeConnections() async {}

  Future<void> forceCloseConnections() async {
    _isClosed = true;

    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();

    _messageProcessingTimer?.cancel();
    _healthCheckTimer?.cancel();

    for (final ws in _webSockets.values) {
      try {
        if (ws.readyState == WebSocket.open || ws.readyState == WebSocket.connecting) {
          await ws.close();
        }
      } catch (e) {
        
      }
    }

    _webSockets.clear();
    _messageQueue.clear();
  }

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
        'successRate': '${(stats.successRate * 100).toStringAsFixed(1)}%',
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

  void flushMessageQueue() {
    _processMessageQueue();
  }

  Future<void> reloadCustomRelays() async {
    await Future.microtask(() async {
      try {
        final customRelays = await getRelaySetMainSockets();
        
        if (kDebugMode) {
          print('[WebSocketManager] Reloading custom relays...');
          print('[WebSocketManager] Current relays: ${relayUrls.length} - $relayUrls');
          print('[WebSocketManager] New relays: ${customRelays.length} - $customRelays');
        }
        
        if (!_listEquals(relayUrls, customRelays)) {
          if (kDebugMode) {
            print('[WebSocketManager] Relay list changed, updating...');
          }
          
          
          final activeConnections = _webSockets.length;
          final closeFutures = _webSockets.values.map((ws) async {
            try {
              if (ws.readyState == WebSocket.open || ws.readyState == WebSocket.connecting) {
                await ws.close();
              }
            } catch (e) {
              
            }
          });
          await Future.wait(closeFutures, eagerError: false);

          await Future.delayed(Duration.zero);

          
          _webSockets.clear();
          relayUrls.clear();
          _connectionStats.clear();

          
          relayUrls.addAll(customRelays);
          _initializeStats();

          if (kDebugMode) {
            print('[WebSocketManager] Updated to ${customRelays.length} relays');
          }

          
          if (activeConnections > 0) {
            if (kDebugMode) {
              print('[WebSocketManager] Reconnecting to ${relayUrls.length} new relays...');
            }
            final connectionFutures = relayUrls.map((relayUrl) => 
              _connectSingleRelay(relayUrl, null, null)
            );
            await Future.wait(connectionFutures, eagerError: false);
            
            if (kDebugMode) {
              print('[WebSocketManager] Reconnection complete: ${_webSockets.length} active connections');
            }
          } else {
            if (kDebugMode) {
              print('[WebSocketManager] No active connections, will connect on next connectRelays() call');
            }
          }
        } else {
          if (kDebugMode) {
            print('[WebSocketManager] Relay list unchanged, no update needed');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[WebSocketManager] Error during relay reload: $e');
        }
      }
    });
  }
}

class PrimalCacheClient {
  static PrimalCacheClient? _instance;
  static PrimalCacheClient get instance => _instance ??= PrimalCacheClient._internal();

  PrimalCacheClient._internal();

  static const Duration _timeout = Duration(seconds: 5);
  final Map<String, Map<String, String>> _profileCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheTTL = Duration(minutes: 20);
  static const int _maxCacheSize = 2000;

  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _requestsSent = 0;
  int _requestsFailed = 0;

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

  void _cleanupCache() {
    Future.microtask(() async {
      final now = DateTime.now();
      final expiredKeys = <String>[];

      final entries = _cacheTimestamps.entries.toList();
      const batchSize = 50;

      for (int i = 0; i < entries.length; i += batchSize) {
        final end = (i + batchSize > entries.length) ? entries.length : i + batchSize;
        final batch = entries.sublist(i, end);

        for (final entry in batch) {
          if (now.difference(entry.value) > _cacheTTL) {
            expiredKeys.add(entry.key);
          }
        }

        await Future.delayed(Duration.zero);
      }

      if (_profileCache.length - expiredKeys.length > _maxCacheSize * 0.8) {
        final sortedEntries = _cacheTimestamps.entries.toList()..sort((a, b) => a.value.compareTo(b.value));

        final toRemove = (_profileCache.length - (_maxCacheSize * 0.7).toInt()).clamp(0, sortedEntries.length);
        for (int i = 0; i < toRemove; i++) {
          expiredKeys.add(sortedEntries[i].key);
        }
      }

      for (int i = 0; i < expiredKeys.length; i += batchSize) {
        final end = (i + batchSize > expiredKeys.length) ? expiredKeys.length : i + batchSize;
        final batch = expiredKeys.sublist(i, end);

        for (final key in batch) {
          _profileCache.remove(key);
          _cacheTimestamps.remove(key);
        }

        await Future.delayed(Duration.zero);
      }
    });
  }

  Map<String, dynamic> getCacheStats() {
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
            if (error is SocketException) {
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
            
          }
        },
        cancelOnError: false,
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

void unawaited(Future<void> future) {
  future.catchError((error) {});
}
