import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

typedef EventProcessor<T> = T? Function(Map<String, dynamic> eventData, String relayUrl);
typedef EventValidator = bool Function(Map<String, dynamic> eventData);

class RelayQueryResult<T> {
  final Map<String, T> results;
  final int totalEvents;
  final Map<String, int> relayEventCounts;

  RelayQueryResult({
    required this.results,
    required this.totalEvents,
    required this.relayEventCounts,
  });
}

class RelayQueryHelper {
  static Future<RelayQueryResult<T>> queryRelaysParallel<T>({
    required List<String> relayUrls,
    required String request,
    required String subscriptionId,
    required EventProcessor<T> eventProcessor,
    EventValidator? eventValidator,
    Duration timeout = const Duration(seconds: 4),
    Duration connectTimeout = const Duration(seconds: 3),
    bool Function()? shouldStop,
    String debugPrefix = 'RELAY',
  }) async {
    final results = <String, T>{};
    final relayEventCounts = <String, int>{};
    int totalEvents = 0;

    await Future.wait(relayUrls.map((relayUrl) async {
      WebSocket? ws;
      StreamSubscription? sub;
      try {
        debugPrint('[$debugPrefix] Connecting to relay: $relayUrl');
        ws = await WebSocket.connect(relayUrl).timeout(connectTimeout);
        
        if (shouldStop != null && shouldStop()) {
          await ws.close();
          return;
        }

        final completer = Completer<void>();
        int eventCount = 0;

        sub = ws.listen(
          (event) {
            try {
              final decoded = jsonDecode(event) as List<dynamic>;

              if (decoded[0] == 'EVENT' && decoded[1] == subscriptionId) {
                final eventData = decoded[2] as Map<String, dynamic>;
                final eventId = eventData['id'] as String? ?? '';

                if (eventValidator == null || eventValidator(eventData)) {
                  final processed = eventProcessor(eventData, relayUrl);
                  if (processed != null && !results.containsKey(eventId)) {
                    results[eventId] = processed;
                    eventCount++;
                    totalEvents++;
                  }
                }
              } else if (decoded[0] == 'EOSE' && decoded[1] == subscriptionId) {
                debugPrint('[$debugPrefix] EOSE from $relayUrl (received $eventCount events)');
                if (!completer.isCompleted) completer.complete();
              }
            } catch (e) {
              debugPrint('[$debugPrefix] Error processing event from $relayUrl: $e');
            }
          },
          onDone: () {
            debugPrint('[$debugPrefix] Connection closed: $relayUrl');
            if (!completer.isCompleted) completer.complete();
          },
          onError: (error) {
            debugPrint('[$debugPrefix] Connection error: $relayUrl - $error');
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );

        if (ws.readyState == WebSocket.open) {
          ws.add(request);
          debugPrint('[$debugPrefix] Request sent to $relayUrl');
        }

        await completer.future.timeout(timeout, onTimeout: () {
          debugPrint('[$debugPrefix] Timeout for $relayUrl (received $eventCount events)');
        });

        relayEventCounts[relayUrl] = eventCount;
        await sub.cancel();
        await ws.close();
      } catch (e) {
        debugPrint('[$debugPrefix] Exception with relay $relayUrl: $e');
        await sub?.cancel();
        await ws?.close();
      }
    }));

    debugPrint('[$debugPrefix] Fetched ${results.length} unique results from ${relayUrls.length} relays (total events: $totalEvents)');

    return RelayQueryResult<T>(
      results: results,
      totalEvents: totalEvents,
      relayEventCounts: relayEventCounts,
    );
  }

  static Future<List<String>> queryStringListFromRelays({
    required List<String> relayUrls,
    required String request,
    required String Function(Map<String, dynamic> eventData) extractor,
    EventValidator? eventValidator,
    Duration timeout = const Duration(seconds: 5),
    Duration connectTimeout = const Duration(seconds: 3),
    bool Function()? shouldStop,
    String debugPrefix = 'RELAY',
  }) async {
    final results = <String>{};

    await Future.wait(relayUrls.map((relayUrl) async {
      WebSocket? ws;
      StreamSubscription? sub;
      try {
        debugPrint('[$debugPrefix] Connecting to relay: $relayUrl');
        ws = await WebSocket.connect(relayUrl).timeout(connectTimeout);
        
        if (shouldStop != null && shouldStop()) {
          await ws.close();
          return;
        }

        final completer = Completer<void>();

        sub = ws.listen(
          (event) {
            try {
              final decoded = jsonDecode(event) as List<dynamic>;

              if (decoded[0] == 'EVENT') {
                final eventData = decoded[2] as Map<String, dynamic>;

                if (eventValidator == null || eventValidator(eventData)) {
                  final extracted = extractor(eventData);
                  if (extracted.isNotEmpty) {
                    results.add(extracted);
                  }
                }
              } else if (decoded[0] == 'EOSE') {
                if (!completer.isCompleted) completer.complete();
              }
            } catch (e) {
              debugPrint('[$debugPrefix] Error processing event from $relayUrl: $e');
            }
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (error) {
            debugPrint('[$debugPrefix] Connection error: $relayUrl - $error');
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );

        if (ws.readyState == WebSocket.open) {
          ws.add(request);
        }

        await completer.future.timeout(timeout, onTimeout: () {
          debugPrint('[$debugPrefix] Timeout for $relayUrl');
        });

        await sub.cancel();
        await ws.close();
      } catch (e) {
        debugPrint('[$debugPrefix] Exception with relay $relayUrl: $e');
        await sub?.cancel();
        await ws?.close();
      }
    }));

    return results.toList();
  }
}

