import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:qiqstr/constants/relays.dart';

class WebSocketManager {
  final List<String> relayUrls;
  final Map<String, WebSocket> _webSockets = {};
  final Duration connectionTimeout;
  bool _isClosed = false;

  WebSocketManager(
      {required this.relayUrls,
      this.connectionTimeout = const Duration(seconds: 3)});

  List<WebSocket> get activeSockets => _webSockets.values.toList();
  bool get isConnected => _webSockets.isNotEmpty;

  Future<void> connectRelays(List<String> targetNpubs,
      {Function(dynamic event, String relayUrl)? onEvent,
      Function(String relayUrl)? onDisconnected}) async {
    await Future.wait(relayUrls.map((relayUrl) async {
      if (_isClosed) return;
      if (!_webSockets.containsKey(relayUrl) ||
          _webSockets[relayUrl]?.readyState == WebSocket.closed) {
        try {
          final rawWs =
              await WebSocket.connect(relayUrl).timeout(connectionTimeout);
          final wsBroadcast = rawWs.asBroadcastStream();
          _webSockets[relayUrl] = rawWs;
          wsBroadcast.listen((event) => onEvent?.call(event, relayUrl),
              onDone: () {
            _webSockets.remove(relayUrl);
            onDisconnected?.call(relayUrl);
          }, onError: (error) {
            _webSockets.remove(relayUrl);
            onDisconnected?.call(relayUrl);
          });
        } catch (e) {
          print('Error connecting to relay $relayUrl: $e');
          _webSockets.remove(relayUrl);
        }
      }
    }));
  }

  Future<void> executeOnActiveSockets(
      FutureOr<void> Function(WebSocket ws) action) async {
    final futures = _webSockets.values.map((ws) async {
      if (ws.readyState == WebSocket.open) await action(ws);
    });
    await Future.wait(futures);
  }

  Future<void> broadcast(String message) async {
    await executeOnActiveSockets((ws) async => ws.add(message));
  }

  void reconnectRelay(String relayUrl, List<String> targetNpubs,
      {int attempt = 1, Function(String relayUrl)? onReconnected}) {
    if (_isClosed) return;
    const int maxAttempts = 5;
    if (attempt > maxAttempts) return;

    int delaySeconds = _calculateBackoffDelay(attempt);
    Timer(Duration(seconds: delaySeconds), () async {
      if (_isClosed) return;
      try {
        WebSocket? rawWs;
        try {
          rawWs = await WebSocket.connect(relayUrl).timeout(connectionTimeout);
        } catch (e) {
          print('[WebSocketManager] Connection error to $relayUrl: $e');
          return;
        }

        final wsBroadcast = rawWs.asBroadcastStream();
        if (_isClosed) {
          await rawWs.close();
          return;
        }
        _webSockets[relayUrl] = rawWs;
        wsBroadcast.listen((event) {}, onDone: () {
          _webSockets.remove(relayUrl);
          reconnectRelay(relayUrl, targetNpubs, attempt: attempt + 1);
        }, onError: (error) {
          _webSockets.remove(relayUrl);
          reconnectRelay(relayUrl, targetNpubs, attempt: attempt + 1);
        });
        onReconnected?.call(relayUrl);
        print('Reconnected to relay: $relayUrl');
      } catch (e) {
        print('Error reconnecting to relay $relayUrl (Attempt $attempt): $e');
        reconnectRelay(relayUrl, targetNpubs, attempt: attempt + 1);
      }
    });
  }

  int _calculateBackoffDelay(int attempt) {
    const int baseDelay = 2;
    const int maxDelay = 32;
    int delay = (baseDelay * pow(2, attempt - 1)).toInt().clamp(1, maxDelay);
    int jitter = Random().nextInt(2);
    return delay + jitter;
  }

  Future<void> closeConnections() async {
    _isClosed = true;
    await Future.wait(_webSockets.values.map((ws) async => await ws.close()));
    _webSockets.clear();
  }
}

class PrimalCacheClient {
  static const Duration _timeout = Duration(seconds: 5);

  Future<Map<String, String>?> fetchUserProfile(String pubkey) async {
    return _sendRequest([
      "REQ",
      _generateId(),
      {
        "cache": [
          "user_profile",
          {"pubkey": pubkey}
        ]
      }
    ]).then(_decodeUserProfile);
  }

  Future<Map<String, dynamic>?> fetchEvent(String eventId) async {
    return _sendRequest([
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
  }

  Future<Map<String, dynamic>?> _sendRequest(List<dynamic> request) async {
    WebSocket? ws;
    final subscriptionId = request[1];
    final encodedRequest = jsonEncode(request);

    try {
      ws = await WebSocket.connect(cachingServerUrl).timeout(_timeout);
      final completer = Completer<Map<String, dynamic>?>();
      late StreamSubscription sub;

      sub = ws.listen((message) {
        final decoded = jsonDecode(message);
        if (decoded is List &&
            decoded.length >= 3 &&
            decoded[0] == 'EVENT' &&
            decoded[1] == subscriptionId) {
          completer.complete(decoded[2]);
        } else if (decoded[0] == 'EOSE' && decoded[1] == subscriptionId) {
          if (!completer.isCompleted) completer.complete(null);
        }
      }, onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      });

      ws.add(encodedRequest);
      final result =
          await completer.future.timeout(_timeout, onTimeout: () => null);

      await sub.cancel();
      await ws.close();
      return result;
    } catch (e) {
      print('[PrimalCacheClient] Error: $e');
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
      final profile =
          (contentRaw is String) ? jsonDecode(contentRaw) : <String, dynamic>{};

      return {
        'name': profile['name'] ?? 'Anonymous',
        'profileImage': profile['picture'] ?? '',
        'about': profile['about'] ?? '',
        'nip05': profile['nip05'] ?? '',
        'banner': profile['banner'] ?? '',
        'lud16': profile['lud16'] ?? '',
        'website': profile['website'] ?? '',
      };
    } catch (e) {
      print('[PrimalCacheClient] Error decoding profile: $e');
      return null;
    }
  }

  String _generateId() => DateTime.now().millisecondsSinceEpoch.toString();
}
