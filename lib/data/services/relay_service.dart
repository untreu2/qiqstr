import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:collection';
import 'package:flutter/foundation.dart';
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

class RelayConnectionState {
  WebSocket? socket;
  bool isConnecting = false;
  DateTime? lastConnectAttempt;
  StreamSubscription? subscription;
  final List<Function(dynamic, String)> eventHandlers = [];
  final List<Function(String)> disconnectHandlers = [];
  
  bool get isConnected => socket != null && socket!.readyState == WebSocket.open;
  bool get isConnectingOrConnected => isConnecting || isConnected;
}

class WebSocketManager {
  static WebSocketManager? _instance;
  static WebSocketManager get instance {
    _instance ??= WebSocketManager._internal();
    return _instance!;
  }

  final List<String> relayUrls = [];
  final Map<String, RelayConnectionState> _connections = {};
  final Map<String, DateTime> _reconnectTimers = {};
  final Map<String, RelayConnectionStats> _connectionStats = {};
  final Duration connectionTimeout = const Duration(seconds: 3);
  final int maxReconnectAttempts = 5;
  final Duration maxBackoffDelay = const Duration(minutes: 2);
  bool _isClosed = false;
  bool _isInitialized = false;

  final Queue<String> _messageQueue = Queue();
  bool _isProcessingMessages = false;
  
  final Map<String, Function(dynamic event, String relayUrl)?> _globalEventHandlers = {};
  final Map<String, Function(String relayUrl)?> _globalDisconnectHandlers = {};

  WebSocketManager._internal() {
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
        if (!relayUrls.contains(countRelayUrl)) {
          relayUrls.add(countRelayUrl);
        }
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

  List<WebSocket> get activeSockets => _connections.values
      .where((state) => state.isConnected)
      .map((state) => state.socket!)
      .toList();

  Map<String, WebSocket> get webSockets => Map.fromEntries(
      _connections.entries
          .where((e) => e.value.isConnected)
          .map((e) => MapEntry(e.key, e.value.socket!)));

  bool get isConnected => activeSockets.isNotEmpty;

  List<String> get healthyRelays {
    return relayUrls.where((url) {
      final stats = _connectionStats[url];
      final state = _connections[url];
      return stats != null && stats.isHealthy && state != null && state.isConnected;
    }).toList();
  }
  
  bool isRelayConnected(String url) {
    final state = _connections[url];
    return state != null && state.isConnected;
  }
  
  bool isRelayConnecting(String url) {
    final state = _connections[url];
    return state != null && state.isConnecting;
  }
  
  Future<WebSocket?> getOrCreateConnection(String relayUrl, {
    Function(dynamic event, String relayUrl)? onEvent,
    Function(String relayUrl)? onDisconnected,
  }) async {
    await _ensureInitialized();
    
    if (_isClosed) return null;
    
    final state = _connections[relayUrl];
    
    if (state != null && state.isConnected) {
      if (onEvent != null && !state.eventHandlers.contains(onEvent)) {
        state.eventHandlers.add(onEvent);
      }
      if (onDisconnected != null && !state.disconnectHandlers.contains(onDisconnected)) {
        state.disconnectHandlers.add(onDisconnected);
      }
      return state.socket;
    }
    
    if (state != null && state.isConnecting) {
      if (onEvent != null && !state.eventHandlers.contains(onEvent)) {
        state.eventHandlers.add(onEvent);
      }
      if (onDisconnected != null && !state.disconnectHandlers.contains(onDisconnected)) {
        state.disconnectHandlers.add(onDisconnected);
      }
      while (state.isConnecting) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (state.isConnected) {
        return state.socket;
      }
    }
    
    return await _connectSingleRelay(relayUrl, onEvent, onDisconnected);
  }

  Future<void> connectRelays(
    List<String> targetNpubs, {
    Function(dynamic event, String relayUrl)? onEvent,
    Function(String relayUrl)? onDisconnected,
    String? serviceId,
  }) async {
    await _ensureInitialized();
    
    if (serviceId != null) {
      _globalEventHandlers[serviceId] = onEvent;
      _globalDisconnectHandlers[serviceId] = onDisconnected;
    }

    if (_connections.values.any((state) => state.isConnected || state.isConnecting)) {
      return;
    }

    if (kDebugMode) {
      print('[WebSocketManager] Connecting to ${relayUrls.length} relays: $relayUrls');
    }

    final connectionFutures = relayUrls.map((relayUrl) => 
      getOrCreateConnection(relayUrl, onEvent: onEvent, onDisconnected: onDisconnected)
    );

    await Future.wait(connectionFutures, eagerError: false);
  }

  Future<WebSocket?> _connectSingleRelay(
    String relayUrl,
    Function(dynamic event, String relayUrl)? onEvent,
    Function(String relayUrl)? onDisconnected,
  ) async {
    if (_isClosed) return null;
    
    var state = _connections[relayUrl];
    if (state == null) {
      state = RelayConnectionState();
      _connections[relayUrl] = state;
      if (!_connectionStats.containsKey(relayUrl)) {
        _connectionStats[relayUrl] = RelayConnectionStats();
      }
    }
    
    if (state.isConnected) {
      if (onEvent != null && !state.eventHandlers.contains(onEvent)) {
        state.eventHandlers.add(onEvent);
      }
      if (onDisconnected != null && !state.disconnectHandlers.contains(onDisconnected)) {
        state.disconnectHandlers.add(onDisconnected);
      }
      return state.socket;
    }
    
    if (state.isConnecting) {
      if (onEvent != null && !state.eventHandlers.contains(onEvent)) {
        state.eventHandlers.add(onEvent);
      }
      if (onDisconnected != null && !state.disconnectHandlers.contains(onDisconnected)) {
        state.disconnectHandlers.add(onDisconnected);
      }
      while (state.isConnecting) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (state.isConnected) {
        return state.socket;
      }
      return null;
    }

    state.isConnecting = true;
    state.lastConnectAttempt = DateTime.now();
    final stats = _connectionStats[relayUrl]!;
    stats.connectAttempts++;

    WebSocket? ws;
    try {
      ws = await WebSocket.connect(relayUrl).timeout(connectionTimeout);
      if (_isClosed) {
        try {
          await ws.close();
        } catch (_) {}
        state.isConnecting = false;
        return null;
      }

      state.socket = ws;
      state.isConnecting = false;
      stats.successfulConnections++;
      stats.lastConnected = DateTime.now();
      stats.connectionStartTime = DateTime.now();

      if (onEvent != null && !state.eventHandlers.contains(onEvent)) {
        state.eventHandlers.add(onEvent);
      }
      if (onDisconnected != null && !state.disconnectHandlers.contains(onDisconnected)) {
        state.disconnectHandlers.add(onDisconnected);
      }

      state.subscription = ws.listen(
        (event) {
          try {
            final currentState = _connections[relayUrl];
            if (!_isClosed && currentState != null && currentState.isConnected) {
              stats.messagesReceived++;

              try {
                final decoded = jsonDecode(event) as List<dynamic>;
                if (decoded.length >= 2 && decoded[0] == 'EVENT') {
                  final subscriptionId = decoded[1] as String;
                  final subscriptionHandlers = _subscriptionHandlers[relayUrl];
                  if (subscriptionHandlers != null && subscriptionHandlers.containsKey(subscriptionId)) {
                    try {
                      subscriptionHandlers[subscriptionId]!(event, relayUrl);
                    } catch (e) {
                      if (kDebugMode) {
                        print('[WebSocketManager] Error in subscription handler: $e');
                      }
                    }
                  }
                } else if (decoded.length >= 2 && (decoded[0] == 'EOSE' || decoded[0] == 'CLOSED')) {
                  final subscriptionId = decoded[1] as String;
                  final subscriptionHandlers = _subscriptionHandlers[relayUrl];
                  if (subscriptionHandlers != null && subscriptionHandlers.containsKey(subscriptionId)) {
                    try {
                      subscriptionHandlers[subscriptionId]!(event, relayUrl);
                    } catch (e) {
                      if (kDebugMode) {
                        print('[WebSocketManager] Error in subscription handler: $e');
                      }
                    }
                  }
                }
              } catch (_) {}

              for (final handler in _globalEventHandlers.values) {
                if (handler != null) {
                  try {
                    handler(event, relayUrl);
                  } catch (e) {
                    if (kDebugMode) {
                      print('[WebSocketManager] Error in global event handler: $e');
                    }
                  }
                }
              }

              final currentState = _connections[relayUrl];
              if (currentState != null) {
                for (final handler in currentState.eventHandlers) {
                  try {
                    handler(event, relayUrl);
                  } catch (e) {
                    if (kDebugMode) {
                      print('[WebSocketManager] Error in event handler: $e');
                    }
                  }
                }
              }
            }
          } catch (e) {
            
          }
        },
        onDone: () {
          try {
            _handleDisconnection(relayUrl);
          } catch (e) {
            
          }
        },
        onError: (error) {
          try {
            _handleDisconnection(relayUrl);
          } catch (e) {
            
          }
        },
        cancelOnError: false,
      );
      
      return ws;
    } catch (e) {
      try {
        await ws?.close();
      } catch (_) {}
      state.isConnecting = false;
      _handleDisconnection(relayUrl);
      return null;
    }
  }

  void _handleDisconnection(String relayUrl) {
    final state = _connections[relayUrl];
    if (state == null) return;
    
    try {
      state.subscription?.cancel();
    } catch (_) {}
    
    state.socket = null;
    state.isConnecting = false;

    final stats = _connectionStats[relayUrl];
    if (stats != null) {
      stats.disconnections++;
      stats.lastDisconnected = DateTime.now();

      if (stats.connectionStartTime != null) {
        final uptime = DateTime.now().difference(stats.connectionStartTime!);
        stats.totalUptime = stats.totalUptime + uptime;
        stats.connectionStartTime = null;
      }
    }

    for (final handler in _globalDisconnectHandlers.values) {
      if (handler != null) {
        try {
          handler(relayUrl);
        } catch (e) {
          if (kDebugMode) {
            print('[WebSocketManager] Error in global disconnect handler: $e');
          }
        }
      }
    }

    for (final handler in state.disconnectHandlers) {
      try {
        handler(relayUrl);
      } catch (e) {
        if (kDebugMode) {
          print('[WebSocketManager] Error in disconnect handler: $e');
        }
      }
    }
    
    state.eventHandlers.clear();
    state.disconnectHandlers.clear();
  }

  void unregisterService(String serviceId) {
    _globalEventHandlers.remove(serviceId);
    _globalDisconnectHandlers.remove(serviceId);
  }
  
  Future<bool> sendMessage(String relayUrl, String message) async {
    final state = _connections[relayUrl];
    if (state == null || !state.isConnected) {
      return false;
    }
    
    try {
      if (state.socket!.readyState == WebSocket.open) {
        state.socket!.add(message);
        final stats = _connectionStats[relayUrl];
        if (stats != null) {
          stats.messagesSent++;
        }
        return true;
      }
    } catch (e) {
      if (e is SocketException) {
        _handleDisconnection(relayUrl);
      }
    }
    return false;
  }
  
  final Map<String, Map<String, Function(dynamic, String)>> _subscriptionHandlers = {};
  
  void registerSubscriptionHandler(String relayUrl, String subscriptionId, Function(dynamic, String) handler) {
    if (!_subscriptionHandlers.containsKey(relayUrl)) {
      _subscriptionHandlers[relayUrl] = {};
    }
    _subscriptionHandlers[relayUrl]![subscriptionId] = handler;
  }
  
  void unregisterSubscriptionHandler(String relayUrl, String subscriptionId) {
    _subscriptionHandlers[relayUrl]?.remove(subscriptionId);
    if (_subscriptionHandlers[relayUrl]?.isEmpty ?? false) {
      _subscriptionHandlers.remove(relayUrl);
    }
  }
  
  Future<Completer<void>> sendQuery(String relayUrl, String request, String subscriptionId, {
    required Function(dynamic, String) onEvent,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final completer = Completer<void>();
    Timer? timeoutTimer;
    bool eoseReceived = false;
    
    final ws = await getOrCreateConnection(relayUrl);
    if (ws == null || ws.readyState != WebSocket.open) {
      completer.complete();
      return completer;
    }
    
    final handler = (dynamic event, String url) {
      try {
        final eventStr = event is String ? event : event.toString();
        final decoded = jsonDecode(eventStr) as List<dynamic>;
        if (decoded.length >= 2 && decoded[1] == subscriptionId) {
          if (decoded[0] == 'EVENT') {
            onEvent(decoded[2], url);
          } else if (decoded[0] == 'EOSE') {
            if (!eoseReceived && !completer.isCompleted) {
              eoseReceived = true;
              timeoutTimer?.cancel();
              completer.complete();
              unregisterSubscriptionHandler(relayUrl, subscriptionId);
            }
          }
        }
      } catch (e) {
        if (!completer.isCompleted) {
          timeoutTimer?.cancel();
          completer.complete();
          unregisterSubscriptionHandler(relayUrl, subscriptionId);
        }
      }
    };
    
    registerSubscriptionHandler(relayUrl, subscriptionId, handler);
    
    final sent = await sendMessage(relayUrl, request);
    if (!sent) {
      if (!completer.isCompleted) {
        completer.complete();
        unregisterSubscriptionHandler(relayUrl, subscriptionId);
      }
      return completer;
    }
    
    timeoutTimer = Timer(timeout, () {
      if (!eoseReceived && !completer.isCompleted) {
        completer.complete();
        unregisterSubscriptionHandler(relayUrl, subscriptionId);
      }
    });
    
    return completer;
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
          _connections.removeWhere((key, value) => value.socket == ws);
        }
      }
    });

    await Future.wait(futures, eagerError: false);
  }

  Future<void> broadcast(String message) async {
    _messageQueue.add(message);

    if (_messageQueue.length >= 5 || _messageQueue.length == 1) {
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
          for (final entry in _connections.entries) {
            if (entry.value.socket == ws) {
              final stats = _connectionStats[entry.key];
              if (stats != null) {
                stats.messagesSent++;
              }
              break;
            }
          }
          ws.add(message);
        }
      } catch (e) {
        if (e is SocketException) {
          _connections.removeWhere((key, value) => value.socket == ws);
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
        for (final entry in _connections.entries) {
          if (entry.value.socket == ws && entry.value.isConnected) {
            final stats = _connectionStats[entry.key];
            if (stats != null) {
              stats.messagesSent++;
            }
            break;
          }
        }
        return ws.add(message);
      });
      return;
    }

    final futures = healthyRelayUrls.map((url) => sendMessage(url, message));
    await Future.wait(futures, eagerError: false);
  }

  void reconnectRelay(
    String relayUrl,
    List<String> targetNpubs, {
    int attempt = 1,
    Function(String relayUrl)? onReconnected,
  }) {
    if (_isClosed || attempt > maxReconnectAttempts) return;

    final delay = _calculateBackoffDelay(attempt);
    final reconnectTime = DateTime.now();
    _reconnectTimers[relayUrl] = reconnectTime;
    
    Future.delayed(Duration(seconds: delay), () async {
      if (_isClosed || _reconnectTimers[relayUrl] != reconnectTime) return;

      final ws = await getOrCreateConnection(relayUrl);
      if (ws != null && _reconnectTimers[relayUrl] == reconnectTime) {
        _reconnectTimers.remove(relayUrl);
        onReconnected?.call(relayUrl);
      } else if (!_isClosed) {
        reconnectRelay(relayUrl, targetNpubs, attempt: attempt + 1, onReconnected: onReconnected);
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

    _reconnectTimers.clear();

    for (final state in _connections.values) {
      try {
        state.subscription?.cancel();
        if (state.socket != null && 
            (state.socket!.readyState == WebSocket.open || 
             state.socket!.readyState == WebSocket.connecting)) {
          await state.socket!.close();
        }
      } catch (e) {
        
      }
    }

    _connections.clear();
    _messageQueue.clear();
  }

  Map<String, dynamic> getConnectionStats() {
    final connectedCount = _connections.values.where((s) => s.isConnected).length;
    final totalStats = {
      'totalRelays': relayUrls.length,
      'connectedRelays': connectedCount,
      'healthyRelays': healthyRelays.length,
      'queuedMessages': _messageQueue.length,
      'isProcessingMessages': _isProcessingMessages,
    };

    final relayStats = <String, Map<String, dynamic>>{};
    for (final entry in _connectionStats.entries) {
      final url = entry.key;
      final stats = entry.value;
      final state = _connections[url];
      relayStats[url] = {
        'connectAttempts': stats.connectAttempts,
        'successfulConnections': stats.successfulConnections,
        'disconnections': stats.disconnections,
        'messagesSent': stats.messagesSent,
        'messagesReceived': stats.messagesReceived,
        'successRate': '${(stats.successRate * 100).toStringAsFixed(1)}%',
        'isHealthy': stats.isHealthy,
        'isConnected': state != null && state.isConnected,
        'isConnecting': state != null && state.isConnecting,
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
          
          final activeConnections = _connections.values.where((s) => s.isConnected).length;
          final closeFutures = _connections.values.map((state) async {
            try {
              state.subscription?.cancel();
              if (state.socket != null && 
                  (state.socket!.readyState == WebSocket.open || 
                   state.socket!.readyState == WebSocket.connecting)) {
                await state.socket!.close();
              }
            } catch (e) {
              
            }
          });
          await Future.wait(closeFutures, eagerError: false);
          
          _connections.clear();
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
              getOrCreateConnection(relayUrl)
            );
            await Future.wait(connectionFutures, eagerError: false);
            
            final newConnected = _connections.values.where((s) => s.isConnected).length;
            if (kDebugMode) {
              print('[WebSocketManager] Reconnection complete: $newConnected active connections');
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

void unawaited(Future<void> future) {
  future.catchError((error) {});
}
