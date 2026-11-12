import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../constants/relays.dart';
import '../../core/base/result.dart';

const int userFollowerCounts = 10000133;

class PrimalCacheService {
  static final PrimalCacheService instance = PrimalCacheService();

  PrimalCacheService({
    Future<WebSocket> Function()? socketFactory,
    this._connectionTimeout = const Duration(seconds: 5),
    this._requestTimeout = const Duration(seconds: 8),
  }) : _socketFactory =
           socketFactory ?? (() => WebSocket.connect(primalCacheUrl));

  static const Duration _followerCountTtl = Duration(minutes: 5);

  final Future<WebSocket> Function() _socketFactory;
  final Duration _connectionTimeout;
  final Duration _requestTimeout;
  WebSocket? _ws;
  Future<WebSocket?>? _connection;
  bool _disposed = false;
  final Map<String, _FollowerCountRequest> _pendingCountRequests = {};
  int _subscriptionCounter = 0;
  final Map<String, int> _followerCountCache = {};
  final Map<String, DateTime> _followerCountCacheTime = {};

  Future<WebSocket?> _ensureConnection() {
    if (_disposed) return Future.value();
    final socket = _ws;
    if (socket != null) {
      if (socket.readyState == WebSocket.open) return Future.value(socket);
      _onDisconnected(socket);
    }
    return _connection ??= _connect();
  }

  Future<WebSocket?> _connect() async {
    var abandoned = false;
    try {
      final socket = await Future.sync(_socketFactory)
          .then((socket) {
            if (abandoned || _disposed) {
              unawaited(_closeSocket(socket));
              return null;
            }
            return socket;
          })
          .timeout(
            _connectionTimeout,
            onTimeout: () {
              abandoned = true;
              return null;
            },
          );
      if (socket == null) return null;
      if (_disposed) {
        unawaited(_closeSocket(socket));
        return null;
      }
      _ws = socket;
      socket.listen(
        (data) => _handleMessage(socket, data),
        onDone: () => _onDisconnected(socket),
        onError: (_) => _onDisconnected(socket),
      );
      return socket;
    } catch (_) {
      return null;
    } finally {
      _connection = null;
    }
  }

  void _onDisconnected(WebSocket socket) {
    if (identical(_ws, socket)) _ws = null;
    final subscriptions = _pendingCountRequests.entries
        .where((entry) => identical(entry.value.socket, socket))
        .map((entry) => entry.key)
        .toList();
    for (final subscriptionId in subscriptions) {
      _completeRequest(
        subscriptionId,
        Result.error('Primal connection closed'),
      );
    }
    unawaited(_closeSocket(socket));
  }

  void _handleMessage(WebSocket socket, dynamic data) {
    if (data is! String) return;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! List || decoded.length < 2) return;
      final subscriptionId = decoded[1];
      if (subscriptionId is! String) return;
      final request = _pendingCountRequests[subscriptionId];
      if (request == null || !identical(request.socket, socket)) return;

      switch (decoded[0]) {
        case 'EVENT':
          if (decoded.length < 3) return;
          final event = decoded[2];
          if (event is! Map || event['kind'] != userFollowerCounts) return;
          if (!event.containsKey('content')) return;
          final content = event['content'];
          if (content != null && content is! String) return;
          final counts = content == null ? null : jsonDecode(content as String);
          if (counts != null && counts is! Map<String, dynamic>) return;
          final parsed = <String, int>{};
          if (counts is Map<String, dynamic>) {
            for (final entry in counts.entries) {
              if (!request.pubkeys.contains(entry.key)) continue;
              final count = entry.value;
              if (count is! int || count < 0) return;
              parsed[entry.key] = count;
            }
          }
          request.counts.addAll(parsed);
          request.receivedCounts = true;
        case 'EOSE':
          _completeRequest(
            subscriptionId,
            Result.success(
              request.receivedCounts
                  ? {
                      for (final pubkey in request.pubkeys)
                        pubkey: request.counts[pubkey] ?? 0,
                    }
                  : {},
            ),
          );
        case 'NOTICE':
        case 'CLOSED':
          _completeRequest(
            subscriptionId,
            Result.error('Primal request rejected'),
          );
      }
    } on FormatException {
      return;
    }
  }

  void _completeRequest(
    String subscriptionId,
    Result<Map<String, int>> result,
  ) {
    final request = _pendingCountRequests.remove(subscriptionId);
    if (request != null && !request.completer.isCompleted) {
      request.completer.complete(result);
    }
  }

  void _closeSubscription(WebSocket socket, String subscriptionId) {
    if (socket.readyState != WebSocket.open) return;
    try {
      socket.add(jsonEncode(['CLOSE', subscriptionId]));
    } catch (_) {}
  }

  Future<void> _closeSocket(WebSocket socket) async {
    try {
      await socket.close();
    } catch (_) {}
  }

  Future<int> fetchFollowerCount(String pubkeyHex) async {
    final result = await fetchFollowerCounts([pubkeyHex]);
    return result[pubkeyHex] ?? 0;
  }

  Future<Map<String, int>> fetchFollowerCounts(List<String> pubkeyHexes) async {
    if (_disposed || pubkeyHexes.isEmpty) return {};

    final now = DateTime.now();
    final result = <String, int>{};
    final uncached = <String>{};
    for (final pubkey in pubkeyHexes) {
      final cachedAt = _followerCountCacheTime[pubkey];
      if (cachedAt != null && now.difference(cachedAt) < _followerCountTtl) {
        result[pubkey] = _followerCountCache[pubkey] ?? 0;
      } else {
        uncached.add(pubkey);
      }
    }
    if (uncached.isEmpty) return result;

    final socket = await _ensureConnection();
    if (_disposed || socket == null || socket.readyState != WebSocket.open) {
      return result;
    }
    final subscriptionId = 'primal_${++_subscriptionCounter}';
    final request = _FollowerCountRequest(socket, uncached);
    _pendingCountRequests[subscriptionId] = request;
    try {
      socket.add(
        jsonEncode([
          'REQ',
          subscriptionId,
          {
            'cache': [
              'user_infos',
              {'pubkeys': uncached.toList()},
            ],
          },
        ]),
      );
      final response = await request.completer.future.timeout(
        _requestTimeout,
        onTimeout: () => Result.error('Primal request timed out'),
      );
      if (_disposed) return result;
      response.whenSuccess((counts) {
        final fetchedAt = DateTime.now();
        for (final entry in counts.entries) {
          _followerCountCache[entry.key] = entry.value;
          _followerCountCacheTime[entry.key] = fetchedAt;
          result[entry.key] = entry.value;
        }
      });
      return result;
    } catch (_) {
      return result;
    } finally {
      _pendingCountRequests.remove(subscriptionId);
      _closeSubscription(socket, subscriptionId);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    final socket = _ws;
    _ws = null;
    for (final subscriptionId in _pendingCountRequests.keys.toList()) {
      _completeRequest(subscriptionId, Result.error('Primal service disposed'));
    }
    _followerCountCache.clear();
    _followerCountCacheTime.clear();
    if (socket != null) await _closeSocket(socket);
  }
}

class _FollowerCountRequest {
  _FollowerCountRequest(this.socket, this.pubkeys);

  final WebSocket socket;
  final Set<String> pubkeys;
  final Completer<Result<Map<String, int>>> completer = Completer();
  final Map<String, int> counts = {};
  bool receivedCounts = false;
}
