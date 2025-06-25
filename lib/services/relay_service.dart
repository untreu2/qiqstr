import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:qiqstr/constants/relays.dart';

class WebSocketManager {
  final List<String> relayUrls;
  final Map<String, WebSocket> _webSockets = {};
  final Map<String, Timer> _reconnectTimers = {};
  final Duration connectionTimeout;
  bool _isClosed = false;

  WebSocketManager({
    required this.relayUrls,
    this.connectionTimeout = const Duration(seconds: 2),
  });

  List<WebSocket> get activeSockets =>
      _webSockets.values.where((ws) => ws.readyState == WebSocket.open).toList();
  
  bool get isConnected => activeSockets.isNotEmpty;

  Future<void> connectRelays(
    List<String> targetNpubs, {
    Function(dynamic event, String relayUrl)? onEvent,
    Function(String relayUrl)? onDisconnected,
  }) async {
    final connectionFutures = relayUrls.map((relayUrl) =>
        _connectSingleRelay(relayUrl, onEvent, onDisconnected));
    
    await Future.wait(connectionFutures, eagerError: false);
  }

  Future<void> _connectSingleRelay(
    String relayUrl,
    Function(dynamic event, String relayUrl)? onEvent,
    Function(String relayUrl)? onDisconnected,
  ) async {
    if (_isClosed || _webSockets.containsKey(relayUrl)) return;

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
      
      ws.listen(
        (event) {
          try {
            if (!_isClosed && _webSockets.containsKey(relayUrl)) {
              onEvent?.call(event, relayUrl);
            }
          } catch (e) {}
        },
        onDone: () {
          try {
            _handleDisconnection(relayUrl, onDisconnected);
          } catch (e) {}
        },
        onError: (error) {
          try {
            _handleDisconnection(relayUrl, onDisconnected);
          } catch (e) {}
        },
        cancelOnError: true,
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
    onDisconnected?.call(relayUrl);
  }

  Future<void> executeOnActiveSockets(
      FutureOr<void> Function(WebSocket ws) action) async {
    final activeWs = activeSockets;
    if (activeWs.isEmpty) return;

    final futures = activeWs.map((ws) async {
      try {
        await action(ws);
      } catch (e) {}
    });
    
    await Future.wait(futures, eagerError: false);
  }

  Future<void> broadcast(String message) async {
    await executeOnActiveSockets((ws) => ws.add(message));
  }

  void reconnectRelay(
    String relayUrl,
    List<String> targetNpubs, {
    int attempt = 1,
    Function(String relayUrl)? onReconnected,
  }) {
    if (_isClosed || attempt > 3) return;

    _reconnectTimers[relayUrl]?.cancel();
    
    final delay = _calculateBackoffDelay(attempt);
    _reconnectTimers[relayUrl] = Timer(Duration(seconds: delay), () async {
      if (_isClosed) return;
      
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
        
        ws.listen(
          (_) {},
          onDone: () {
            if (!_isClosed) {
              reconnectRelay(relayUrl, targetNpubs, attempt: attempt + 1);
            }
          },
          onError: (_) {
            if (!_isClosed) {
              reconnectRelay(relayUrl, targetNpubs, attempt: attempt + 1);
            }
          },
          cancelOnError: true,
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
    const maxDelay = 16;
    final delay = (baseDelay * pow(2, attempt - 1)).toInt().clamp(1, maxDelay);
    final jitter = Random().nextInt((delay ~/ 2).clamp(1, 5));
    return delay + jitter;
  }

  Future<void> closeConnections() async {
    _isClosed = true;
    
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();

    final closeFutures = _webSockets.values.map((ws) async {
      try {
        await ws.close();
      } catch (e) {}
    });
    
    await Future.wait(closeFutures, eagerError: false);
    _webSockets.clear();
  }
}

class PrimalCacheClient {
  static const Duration _timeout = Duration(seconds: 3);
  static final Map<String, Map<String, String>> _profileCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheTTL = Duration(minutes: 15);

  Future<Map<String, String>?> fetchUserProfile(String pubkey) async {
    final now = DateTime.now();
    final cached = _profileCache[pubkey];
    final timestamp = _cacheTimestamps[pubkey];
    
    if (cached != null &&
        timestamp != null &&
        now.difference(timestamp) < _cacheTTL) {
      return cached;
    }

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
      
      if (_profileCache.length > 1000) {
        _cleanupCache();
      }
    }

    return result;
  }

  Future<Map<String, dynamic>?> fetchEvent(String eventId) async {
    return _sendRequest([
      "REQ",
      _generateId(),
      {
        "cache": [
          "events",
          {"event_ids": [eventId]}
        ]
      }
    ]);
  }

  void _cleanupCache() {
    final now = DateTime.now();
    final expiredKeys = <String>[];
    
    for (final entry in _cacheTimestamps.entries) {
      if (now.difference(entry.value) > _cacheTTL) {
        expiredKeys.add(entry.key);
      }
    }
    
    for (final key in expiredKeys) {
      _profileCache.remove(key);
      _cacheTimestamps.remove(key);
    }
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
        onError: (_) {
          if (!completer.isCompleted) completer.complete(null);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(null);
        },
        cancelOnError: true,
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
