import 'dart:async';
import 'auth_service.dart';
import 'relay_service.dart';

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

      final filter = {
        'authors': [pubkeyHex],
      };

      final events = await RustRelayService.instance.fetchEvents(
        filter,
        timeoutSecs: 30,
      );

      final processedEventIds = <String>{};
      int totalCount = 0;
      final eventCountsByKind = <int, int>{};
      final allEvents = <Map<String, dynamic>>[];

      for (final data in events) {
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
      final result = await RustRelayService.instance.broadcastEvents(
        events,
        relayUrls: relayUrls,
      );
      return (result['totalSuccess'] as int? ?? 0) > 0;
    } catch (e) {
      return false;
    }
  }
}
