import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../constants/relays.dart';

const int userFollowerCounts = 10000133;

class PrimalCacheService {
  static PrimalCacheService? _instance;
  static PrimalCacheService get instance {
    _instance ??= PrimalCacheService._internal();
    return _instance!;
  }

  PrimalCacheService._internal();

  WebSocket? _ws;
  bool _connecting = false;
  final Map<String, Completer<Map<String, int>>> _pendingCountRequests = {};
  int _subscriptionCounter = 0;
  StreamSubscription? _subscription; // ignore: unused_field

  Future<WebSocket?> _ensureConnection() async {
    if (_ws != null && _ws!.readyState == WebSocket.open) return _ws;
    if (_connecting) {
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_ws != null && _ws!.readyState == WebSocket.open) return _ws;
      }
      return null;
    }

    _connecting = true;
    try {
      _ws = await WebSocket.connect(primalCacheUrl)
          .timeout(const Duration(seconds: 5));
      _subscription = _ws!.listen(
        (data) {
          try {
            final decoded = jsonDecode(data as String) as List<dynamic>;
            _handleMessage(decoded);
          } catch (_) {}
        },
        onDone: () {
          _ws = null;
          _subscription = null;
        },
        onError: (_) {
          _ws = null;
          _subscription = null;
        },
      );
      return _ws;
    } catch (e) {
      if (kDebugMode) {
        print('[PrimalCacheService] Connection error: $e');
      }
      return null;
    } finally {
      _connecting = false;
    }
  }

  void _handleMessage(List<dynamic> decoded) {
    try {
      if (decoded.length < 2) return;
      final messageType = decoded[0] as String;
      final subscriptionId = decoded[1] as String;

      if (messageType == 'EVENT' && decoded.length >= 3) {
        final event = decoded[2] as Map<String, dynamic>;
        final kind = event['kind'] as int?;

        if (kind == userFollowerCounts &&
            _pendingCountRequests.containsKey(subscriptionId)) {
          final completer = _pendingCountRequests.remove(subscriptionId);
          if (completer != null && !completer.isCompleted) {
            try {
              final content = jsonDecode(event['content'] as String)
                  as Map<String, dynamic>;
              final followerCounts = <String, int>{};
              content.forEach((key, value) {
                if (value is int) {
                  followerCounts[key] = value;
                }
              });
              completer.complete(followerCounts);
            } catch (e) {
              if (kDebugMode) {
                print('[PrimalCacheService] Parse error: $e');
              }
              completer.complete({});
            }
          }
        }
      } else if (messageType == 'EOSE') {
        final countCompleter = _pendingCountRequests.remove(subscriptionId);
        countCompleter?.complete({});
      }
    } catch (e) {
      if (kDebugMode) {
        print('[PrimalCacheService] Message handling error: $e');
      }
    }
  }

  Future<bool> _send(String message) async {
    try {
      final ws = await _ensureConnection();
      if (ws == null || ws.readyState != WebSocket.open) return false;
      ws.add(message);
      return true;
    } catch (e) {
      return false;
    }
  }

  void _closeSubscription(String subscriptionId) {
    try {
      final closeRequest = ['CLOSE', subscriptionId];
      _send(jsonEncode(closeRequest));
    } catch (e) {
      if (kDebugMode) {
        print('[PrimalCacheService] Close subscription error: $e');
      }
    }
  }

  Future<Map<String, int>> fetchFollowerCounts(List<String> pubkeyHexes) async {
    if (pubkeyHexes.isEmpty) return {};

    final subscriptionId =
        'primal_${++_subscriptionCounter}_${DateTime.now().millisecondsSinceEpoch}';
    final completer = Completer<Map<String, int>>();
    _pendingCountRequests[subscriptionId] = completer;

    try {
      final request = [
        'REQ',
        subscriptionId,
        {
          'cache': [
            'user_infos',
            {'pubkeys': pubkeyHexes}
          ]
        }
      ];

      final sent = await _send(jsonEncode(request));
      if (!sent) {
        _pendingCountRequests.remove(subscriptionId);
        return {};
      }

      final result = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _pendingCountRequests.remove(subscriptionId);
          return <String, int>{};
        },
      );

      _closeSubscription(subscriptionId);
      return result;
    } catch (e) {
      _pendingCountRequests.remove(subscriptionId);
      _closeSubscription(subscriptionId);
      if (kDebugMode) {
        print('[PrimalCacheService] Request error: $e');
      }
      return {};
    }
  }

  Future<int> fetchFollowerCount(String pubkeyHex) async {
    final counts = await fetchFollowerCounts([pubkeyHex]);
    return counts[pubkeyHex] ?? 0;
  }
}
