import 'dart:async';
import 'dart:convert';
import 'auth_service.dart';
import 'relay_service.dart';
import '../../../constants/relays.dart';

class EventCountsResult {
  final int totalCount;
  final Map<int, int> countsByKind;
  final List<Map<String, dynamic>> allEvents;

  EventCountsResult({
    required this.totalCount,
    required this.countsByKind,
    required this.allEvents,
  });
}

class EventCountsService {
  static final EventCountsService _instance = EventCountsService._internal();
  factory EventCountsService() => _instance;
  EventCountsService._internal();

  static EventCountsService get instance => _instance;

  Future<EventCountsResult?> fetchAllEventsForUser(
      String? targetPubkeyHex) async {
    try {
      String? pubkeyHex = targetPubkeyHex;
      if (pubkeyHex == null) {
        pubkeyHex = AuthService.instance.currentUserPubkeyHex;
        if (pubkeyHex == null) {
          return null;
        }
      }

      final manager = WebSocketManager.instance;
      final processedEventIds = <String>{};
      int totalCount = 0;
      final eventCountsByKind = <int, int>{};
      final allEvents = <Map<String, dynamic>>[];
      final subscriptionId = DateTime.now().millisecondsSinceEpoch.toString();

      for (final relayUrl in relaySetMainSockets.take(5)) {
        try {
          final filter = {
            'authors': [pubkeyHex],
          };

          final request = jsonEncode(['REQ', subscriptionId, filter]);

          final completer = await manager.sendQuery(
            relayUrl,
            request,
            subscriptionId,
            timeout: const Duration(seconds: 30),
            onEvent: (data, url) {
              try {
                final eventId = data['id'] as String?;
                final eventKind = data['kind'] as int?;

                if (eventId != null && !processedEventIds.contains(eventId)) {
                  processedEventIds.add(eventId);
                  totalCount++;

                  allEvents.add(data);

                  if (eventKind != null) {
                    eventCountsByKind[eventKind] =
                        (eventCountsByKind[eventKind] ?? 0) + 1;
                  }
                }
              } catch (_) {}
            },
          );

          await completer.future
              .timeout(const Duration(seconds: 30), onTimeout: () {});
        } catch (_) {}
      }

      return EventCountsResult(
        totalCount: totalCount,
        countsByKind: eventCountsByKind,
        allEvents: allEvents,
      );
    } catch (e) {
      return null;
    }
  }

  Future<bool> rebroadcastEvents(List<Map<String, dynamic>> events,
      {List<String>? relayUrls}) async {
    if (events.isEmpty) {
      return false;
    }

    try {
      final manager = WebSocketManager.instance;
      final allRelays = relayUrls ?? relaySetMainSockets;

      for (final event in events) {
        try {
          final serializedEvent = jsonEncode(['EVENT', event]);

          for (final relayUrl in allRelays) {
            try {
              await manager.sendMessage(relayUrl, serializedEvent);
            } catch (_) {}
          }
        } catch (_) {}
      }

      return true;
    } catch (e) {
      return false;
    }
  }
}
