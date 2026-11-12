import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../lib/data/services/primal_cache_service.dart';

void main() {
  late _PrimalServer server;
  late PrimalCacheService service;

  setUp(() async {
    server = await _PrimalServer.start();
    service = PrimalCacheService(socketFactory: server.connect);
  });

  tearDown(() async {
    await service.dispose();
    await server.close();
  });

  test(
    'null aggregate from user_infos is cached as zero without parse errors',
    () async {
      final pending = service.fetchFollowerCounts(['unknown', 'unknown']);
      final request = await server.nextRequest();
      expect(request.$2[2], {
        'cache': [
          'user_infos',
          {
            'pubkeys': ['unknown'],
          },
        ],
      });
      server.counts(request, null);
      server.end(request);

      expect(await pending, {'unknown': 0});
      expect(await service.fetchFollowerCount('unknown'), 0);
      expect(server.requestCount, 1);
      expect(await server.nextClose(), request.$2[1]);
    },
  );

  test(
    'aggregates all count frames through EOSE and fills missing users',
    () async {
      final pending = service.fetchFollowerCounts(['alice', 'bob', 'unknown']);
      final request = await server.nextRequest();
      server.counts(request, 'null');
      server.counts(request, jsonEncode({'alice': 5}));
      server.counts(request, jsonEncode({'bob': 8, 'unrequested': 99}));
      server.end(request);

      expect(await pending, {'alice': 5, 'bob': 8, 'unknown': 0});
      final unrequested = service.fetchFollowerCount('unrequested');
      final secondRequest = await server.nextRequest();
      server.counts(secondRequest, jsonEncode({'unrequested': 7}));
      server.end(secondRequest);
      expect(await unrequested, 7);
    },
  );

  test(
    'malformed and unrelated frames do not consume a pending request',
    () async {
      final pending = service.fetchFollowerCount('alice');
      final request = await server.nextRequest();
      final socket = request.$1;
      final id = request.$2[1];
      socket.add('invalid json');
      socket.add(jsonEncode({'not': 'a frame'}));
      socket.add(jsonEncode(['EVENT', null, {}]));
      socket.add(jsonEncode(['EVENT', id, null]));
      socket.add(
        jsonEncode([
          'EVENT',
          id,
          {'kind': userFollowerCounts},
        ]),
      );
      socket.add(
        jsonEncode([
          'EVENT',
          'other',
          {'kind': userFollowerCounts},
        ]),
      );
      socket.add(
        jsonEncode([
          'EVENT',
          id,
          {'kind': 0, 'content': '{}'},
        ]),
      );
      for (final content in [
        [],
        9,
        '{invalid',
        '[]',
        '{"alice":-1}',
        '{"alice":"8"}',
      ]) {
        server.counts(request, content);
      }
      server.counts(request, '{"alice":12}');
      server.end(request);

      expect(await pending, 12);
    },
  );

  test(
    'EOSE without a valid count event does not cache a fabricated zero',
    () async {
      final pending = service.fetchFollowerCounts(['alice']);
      final request = await server.nextRequest();
      server.counts(request, '{"alice":"bad"}');
      server.end(request);
      expect(await pending, isEmpty);

      final retry = service.fetchFollowerCount('alice');
      final retryRequest = await server.nextRequest();
      server.counts(retryRequest, '{"alice":4}');
      server.end(retryRequest);
      expect(await retry, 4);
    },
  );

  test('concurrent callers share the full connection attempt', () async {
    final gate = Completer<void>();
    var attempts = 0;
    service = PrimalCacheService(
      socketFactory: () async {
        attempts++;
        await gate.future;
        return server.connect();
      },
    );
    final alice = service.fetchFollowerCount('alice');
    final bob = service.fetchFollowerCount('bob');
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    expect(attempts, 1);
    gate.complete();

    for (var i = 0; i < 2; i++) {
      final request = await server.nextRequest();
      final key = request.$2[2]['cache'][1]['pubkeys'][0] as String;
      server.counts(request, jsonEncode({key: key == 'alice' ? 3 : 6}));
      server.end(request);
    }
    expect(await alice, 3);
    expect(await bob, 6);
    expect(attempts, 1);
  });

  test(
    'disconnect completes all pending requests and reconnects on demand',
    () async {
      final alice = service.fetchFollowerCounts(['alice']);
      final bob = service.fetchFollowerCounts(['bob']);
      final first = await server.nextRequest();
      await server.nextRequest();
      await first.$1.close();

      expect(await alice.timeout(const Duration(seconds: 1)), isEmpty);
      expect(await bob.timeout(const Duration(seconds: 1)), isEmpty);
      expect(server.connectionCount, 1);

      final retry = service.fetchFollowerCount('alice');
      final request = await server.nextRequest();
      server.counts(request, '{"alice":5}');
      server.end(request);
      expect(await retry, 5);
      expect(server.connectionCount, 2);
    },
  );

  test('timeout closes once on the same socket and permits retry', () async {
    service = PrimalCacheService(
      socketFactory: server.connect,
      requestTimeout: const Duration(milliseconds: 50),
    );
    final pending = service.fetchFollowerCounts(['alice']);
    final request = await server.nextRequest();
    server.counts(request, '{"alice":100}');
    expect(await pending, isEmpty);
    expect(await server.nextClose(), request.$2[1]);

    final retry = service.fetchFollowerCount('alice');
    final retryRequest = await server.nextRequest();
    server.end(request);
    server.counts(retryRequest, '{"alice":9}');
    server.end(retryRequest);
    expect(await retry, 9);
    expect(await server.nextClose(), retryRequest.$2[1]);
    expect(server.closedSubscriptions, [request.$2[1], retryRequest.$2[1]]);
    expect(server.connectionCount, 1);
  });

  for (final type in ['NOTICE', 'CLOSED']) {
    test(
      '$type completes only its request without poisoning the cache',
      () async {
        final alice = service.fetchFollowerCounts(['alice']);
        final first = await server.nextRequest();
        final bob = service.fetchFollowerCount('bob');
        final second = await server.nextRequest();
        first.$1.add(jsonEncode([type, first.$2[1], 'unavailable']));
        expect(await alice.timeout(const Duration(seconds: 1)), isEmpty);
        server.counts(second, '{"bob":11}');
        server.end(second);
        expect(await bob, 11);
      },
    );
  }

  test(
    'failed connection returns safely and next call can reconnect',
    () async {
      var attempts = 0;
      service = PrimalCacheService(
        socketFactory: () {
          if (attempts++ == 0) throw const SocketException('unavailable');
          return server.connect();
        },
      );
      expect(await service.fetchFollowerCounts(['alice']), isEmpty);
      final retry = service.fetchFollowerCount('alice');
      final request = await server.nextRequest();
      server.counts(request, '{"alice":2}');
      server.end(request);
      expect(await retry, 2);
    },
  );

  test(
    'late timed-out connection is closed without replacing its successor',
    () async {
      final gate = Completer<WebSocket>();
      var attempts = 0;
      service = PrimalCacheService(
        socketFactory: () => attempts++ == 0 ? gate.future : server.connect(),
        connectionTimeout: const Duration(milliseconds: 50),
      );
      expect(await service.fetchFollowerCounts(['alice']), isEmpty);
      final retry = service.fetchFollowerCount('alice');
      final request = await server.nextRequest();
      final lateSocket = await server.connect();
      gate.complete(lateSocket);
      await server.lastConnectionClosed.timeout(const Duration(seconds: 1));
      server.counts(request, '{"alice":10}');
      server.end(request);
      expect(await retry, 10);
    },
  );

  test('dispose releases requests and prevents further connections', () async {
    final pending = service.fetchFollowerCounts(['alice']);
    await server.nextRequest();
    await service.dispose();
    expect(await pending.timeout(const Duration(seconds: 1)), isEmpty);
    expect(await service.fetchFollowerCounts(['alice']), isEmpty);
    expect(server.connectionCount, 1);
  });

  test('dispose closes a connection that arrives after disposal', () async {
    final gate = Completer<WebSocket>();
    service = PrimalCacheService(socketFactory: () => gate.future);
    final pending = service.fetchFollowerCounts(['alice']);
    await service.dispose();
    final socket = await server.connect();
    gate.complete(socket);
    expect(await pending, isEmpty);
    await server.lastConnectionClosed.timeout(const Duration(seconds: 1));
    expect(server.requestCount, 0);
  });

  test('empty requests do not open a socket', () async {
    expect(await service.fetchFollowerCounts([]), isEmpty);
    expect(server.connectionCount, 0);
  });
}

class _PrimalServer {
  _PrimalServer(this._server) {
    _requests = StreamIterator(_requestStream.stream);
    _closes = StreamIterator(_closeStream.stream);
    _server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      _sockets.add(socket);
      final closed = Completer<void>();
      _socketClosures.add(closed);
      _socketSubscriptions.add(
        socket.listen((data) {
          final frame = jsonDecode(data as String) as List<dynamic>;
          if (frame[0] == 'REQ') {
            requestCount++;
            _requestStream.add((socket, frame));
          } else if (frame[0] == 'CLOSE') {
            closedSubscriptions.add(frame[1] as String);
            _closeStream.add(frame[1] as String);
          }
        }, onDone: closed.complete),
      );
    });
  }

  static Future<_PrimalServer> start() async =>
      _PrimalServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final _sockets = <WebSocket>[];
  final _socketClosures = <Completer<void>>[];
  Future<void> get lastConnectionClosed => _socketClosures.last.future;
  final _socketSubscriptions = <StreamSubscription<dynamic>>[];
  final _requestStream = StreamController<(WebSocket, List<dynamic>)>();
  final _closeStream = StreamController<String>();
  late final StreamIterator<(WebSocket, List<dynamic>)> _requests;
  late final StreamIterator<String> _closes;
  final closedSubscriptions = <String>[];
  int requestCount = 0;
  int get connectionCount => _sockets.length;

  Future<WebSocket> connect() =>
      WebSocket.connect('ws://127.0.0.1:${_server.port}');

  Future<(WebSocket, List<dynamic>)> nextRequest() async {
    expect(
      await _requests.moveNext().timeout(const Duration(seconds: 2)),
      isTrue,
    );
    return _requests.current;
  }

  Future<String> nextClose() async {
    expect(
      await _closes.moveNext().timeout(const Duration(seconds: 2)),
      isTrue,
    );
    return _closes.current;
  }

  void counts((WebSocket, List<dynamic>) request, Object? content) {
    request.$1.add(
      jsonEncode([
        'EVENT',
        request.$2[1],
        {'kind': userFollowerCounts, 'content': content},
      ]),
    );
  }

  void end((WebSocket, List<dynamic>) request) =>
      request.$1.add(jsonEncode(['EOSE', request.$2[1]]));

  Future<void> close() async {
    for (final socket in _sockets) {
      await socket.close();
    }
    await _server.close(force: true);
    for (final subscription in _socketSubscriptions) {
      await subscription.cancel();
    }
    await _requests.cancel();
    await _closes.cancel();
    unawaited(_requestStream.close());
    unawaited(_closeStream.close());
  }
}
