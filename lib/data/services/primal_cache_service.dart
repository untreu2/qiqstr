import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'relay_service.dart';
import '../../constants/relays.dart';

const int USER_FOLLOWER_COUNTS = 10000133;
const int NOTIFICATION = 10000110;

class PrimalCacheService {
  static PrimalCacheService? _instance;
  static PrimalCacheService get instance {
    _instance ??= PrimalCacheService._internal();
    return _instance!;
  }

  PrimalCacheService._internal();

  final WebSocketManager _webSocketManager = WebSocketManager.instance;
  final Map<String, Completer<Map<String, int>>> _pendingCountRequests = {};
  final Map<String, Completer<Map<String, Map<String, dynamic>>>>
      _pendingProfileRequests = {};
  final Map<String, Completer<List<Map<String, dynamic>>>>
      _pendingNotificationRequests = {};
  final Map<String, List<Map<String, dynamic>>> _notificationBuffers = {};
  int _subscriptionCounter = 0;

  void _handleMessage(List<dynamic> decoded, String relayUrl) {
    try {
      if (decoded.length < 2) return;
      final messageType = decoded[0] as String;
      final subscriptionId = decoded[1] as String;

      if (messageType == 'EVENT' && decoded.length >= 3) {
        final event = decoded[2] as Map<String, dynamic>;
        final kind = event['kind'] as int?;

        if (kind == NOTIFICATION &&
            _pendingNotificationRequests.containsKey(subscriptionId)) {
          try {
            final content = event['content'];
            Map<String, dynamic> notifData;
            if (content is String) {
              notifData = jsonDecode(content) as Map<String, dynamic>;
            } else if (content is Map) {
              notifData = Map<String, dynamic>.from(content);
            } else {
              return;
            }

            if (!_notificationBuffers.containsKey(subscriptionId)) {
              _notificationBuffers[subscriptionId] = [];
            }
            _notificationBuffers[subscriptionId]!.add(notifData);
          } catch (e) {
            if (kDebugMode) {
              print('[PrimalCacheService] Notification parse error: $e');
            }
          }
        } else if (kind == USER_FOLLOWER_COUNTS &&
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
        } else if (_pendingProfileRequests.containsKey(subscriptionId)) {
          final completer = _pendingProfileRequests.remove(subscriptionId);
          if (completer != null && !completer.isCompleted) {
            try {
              final content = jsonDecode(event['content'] as String)
                  as Map<String, dynamic>;
              final profiles = <String, Map<String, dynamic>>{};
              content.forEach((key, value) {
                if (value is Map<String, dynamic>) {
                  profiles[key] = value;
                } else if (value is Map) {
                  profiles[key] = Map<String, dynamic>.from(value);
                }
              });
              completer.complete(profiles);
            } catch (e) {
              if (kDebugMode) {
                print('[PrimalCacheService] Profile parse error: $e');
              }
              completer.complete({});
            }
          }
        }
      } else if (messageType == 'EOSE') {
        final countCompleter = _pendingCountRequests.remove(subscriptionId);
        countCompleter?.complete({});

        final profileCompleter = _pendingProfileRequests.remove(subscriptionId);
        profileCompleter?.complete({});

        final notificationCompleter =
            _pendingNotificationRequests.remove(subscriptionId);
        if (notificationCompleter != null &&
            !notificationCompleter.isCompleted) {
          final notifications =
              _notificationBuffers.remove(subscriptionId) ?? [];
          notificationCompleter.complete(notifications);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[PrimalCacheService] Message handling error: $e');
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
      final ws = await _webSocketManager.getOrCreateConnection(primalCacheUrl);
      if (ws == null) {
        _pendingCountRequests.remove(subscriptionId);
        return {};
      }

      _webSocketManager.registerSubscriptionHandler(
          primalCacheUrl, subscriptionId, _handleMessage);

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

      final sent = await _webSocketManager.sendMessage(
          primalCacheUrl, jsonEncode(request));
      if (!sent) {
        _pendingCountRequests.remove(subscriptionId);
        _webSocketManager.unregisterSubscriptionHandler(
            primalCacheUrl, subscriptionId);
        return {};
      }

      final result = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _pendingCountRequests.remove(subscriptionId);
          _webSocketManager.unregisterSubscriptionHandler(
              primalCacheUrl, subscriptionId);
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

  Future<Map<String, Map<String, dynamic>>> fetchUserInfos(
      List<String> pubkeyHexes) async {
    if (pubkeyHexes.isEmpty) return {};

    final subscriptionId =
        'primal_${++_subscriptionCounter}_${DateTime.now().millisecondsSinceEpoch}';
    final completer = Completer<Map<String, Map<String, dynamic>>>();
    _pendingProfileRequests[subscriptionId] = completer;

    try {
      final ws = await _webSocketManager.getOrCreateConnection(primalCacheUrl);
      if (ws == null) {
        _pendingProfileRequests.remove(subscriptionId);
        return {};
      }

      _webSocketManager.registerSubscriptionHandler(
          primalCacheUrl, subscriptionId, _handleMessage);

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

      final sent = await _webSocketManager.sendMessage(
          primalCacheUrl, jsonEncode(request));
      if (!sent) {
        _pendingProfileRequests.remove(subscriptionId);
        _webSocketManager.unregisterSubscriptionHandler(
            primalCacheUrl, subscriptionId);
        return {};
      }

      final result = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _pendingProfileRequests.remove(subscriptionId);
          _webSocketManager.unregisterSubscriptionHandler(
              primalCacheUrl, subscriptionId);
          return <String, Map<String, dynamic>>{};
        },
      );

      _closeSubscription(subscriptionId);
      return result;
    } catch (e) {
      _pendingProfileRequests.remove(subscriptionId);
      _closeSubscription(subscriptionId);
      if (kDebugMode) {
        print('[PrimalCacheService] User infos request error: $e');
      }
      return {};
    }
  }

  void _closeSubscription(String subscriptionId) {
    try {
      final closeRequest = ['CLOSE', subscriptionId];
      _webSocketManager.sendMessage(primalCacheUrl, jsonEncode(closeRequest));
      _webSocketManager.unregisterSubscriptionHandler(
          primalCacheUrl, subscriptionId);
    } catch (e) {
      if (kDebugMode) {
        print('[PrimalCacheService] Close subscription error: $e');
      }
    }
  }

  Future<int> fetchFollowerCount(String pubkeyHex) async {
    final counts = await fetchFollowerCounts([pubkeyHex]);
    return counts[pubkeyHex] ?? 0;
  }

  Future<List<Map<String, dynamic>>> fetchNotifications({
    required String pubkeyHex,
    int? since,
    int? until,
    int limit = 100,
  }) async {
    final subscriptionId =
        'primal_notif_${++_subscriptionCounter}_${DateTime.now().millisecondsSinceEpoch}';
    final completer = Completer<List<Map<String, dynamic>>>();
    _pendingNotificationRequests[subscriptionId] = completer;

    try {
      final ws = await _webSocketManager.getOrCreateConnection(primalCacheUrl);
      if (ws == null) {
        _pendingNotificationRequests.remove(subscriptionId);
        _notificationBuffers.remove(subscriptionId);
        return [];
      }

      _webSocketManager.registerSubscriptionHandler(
          primalCacheUrl, subscriptionId, _handleMessage);

      final requestParams = <String, dynamic>{
        'pubkey': pubkeyHex,
        'limit': limit,
      };
      if (since != null) {
        requestParams['since'] = since;
      }
      if (until != null) {
        requestParams['until'] = until;
      }

      final request = [
        'REQ',
        subscriptionId,
        {
          'cache': ['get_notifications', requestParams]
        }
      ];

      final sent = await _webSocketManager.sendMessage(
          primalCacheUrl, jsonEncode(request));
      if (!sent) {
        _pendingNotificationRequests.remove(subscriptionId);
        _notificationBuffers.remove(subscriptionId);
        _webSocketManager.unregisterSubscriptionHandler(
            primalCacheUrl, subscriptionId);
        return [];
      }

      _notificationBuffers[subscriptionId] = [];

      final result = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _pendingNotificationRequests.remove(subscriptionId);
          _notificationBuffers.remove(subscriptionId);
          _webSocketManager.unregisterSubscriptionHandler(
              primalCacheUrl, subscriptionId);
          return <Map<String, dynamic>>[];
        },
      );

      _closeSubscription(subscriptionId);
      _notificationBuffers.remove(subscriptionId);
      return result;
    } catch (e) {
      _pendingNotificationRequests.remove(subscriptionId);
      _notificationBuffers.remove(subscriptionId);
      _closeSubscription(subscriptionId);
      if (kDebugMode) {
        print('[PrimalCacheService] Notifications request error: $e');
      }
      return [];
    }
  }
}
