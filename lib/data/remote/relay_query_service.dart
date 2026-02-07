import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/relay_service.dart';
import '../services/nostr_service.dart';

class RelayQueryService {
  final WebSocketManager _wsManager;

  RelayQueryService({WebSocketManager? wsManager})
      : _wsManager = wsManager ?? WebSocketManager.instance;

  Future<List<Map<String, dynamic>>> fetchNotes({
    List<String>? authors,
    List<int>? kinds,
    int? limit,
    int? since,
    int? until,
  }) async {
    final filter = NostrService.createNotesFilter(
      authors: authors,
      kinds: kinds ?? [1, 6],
      limit: limit,
      since: since,
      until: until,
    );
    return await _executeQuery(filter);
  }

  Future<List<Map<String, dynamic>>> fetchProfiles(List<String> pubkeys) async {
    if (pubkeys.isEmpty) return [];
    final filter = NostrService.createProfileFilter(
      authors: pubkeys,
      limit: pubkeys.length,
    );
    return await _executeQuery(filter);
  }

  Future<Map<String, dynamic>?> fetchProfile(String pubkey) async {
    final results = await fetchProfiles([pubkey]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> fetchFollowingList(String pubkey) async {
    final filter = NostrService.createFollowingFilter(
      authors: [pubkey],
      limit: 1,
    );
    return await _executeQuery(filter);
  }

  Future<List<Map<String, dynamic>>> fetchMuteList(String pubkey) async {
    final filter = NostrService.createMuteFilter(
      authors: [pubkey],
      limit: 1,
    );
    return await _executeQuery(filter);
  }

  Future<List<Map<String, dynamic>>> fetchNotifications({
    required String userPubkey,
    List<int>? kinds,
    int? since,
    int? limit,
  }) async {
    final filter = NostrService.createNotificationFilter(
      pubkeys: [userPubkey],
      kinds: kinds ?? [1, 6, 7, 9735],
      since: since,
      limit: limit ?? 100,
    );
    return await _executeQuery(filter);
  }

  Future<List<Map<String, dynamic>>> fetchReplies({
    required String noteId,
    int? limit,
  }) async {
    final filter = NostrService.createThreadRepliesFilter(
      rootNoteId: noteId,
      limit: limit ?? 100,
    );
    return await _executeQuery(filter);
  }

  Future<List<Map<String, dynamic>>> fetchEventsByIds(
      List<String> eventIds) async {
    if (eventIds.isEmpty) return [];
    final filter = NostrService.createEventByIdFilter(eventIds: eventIds);
    return await _executeQuery(filter);
  }

  Future<Map<String, dynamic>?> fetchEventById(String eventId) async {
    final results = await fetchEventsByIds([eventId]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> fetchInteractions({
    required List<String> eventIds,
    List<int>? kinds,
    int? limit,
    int? since,
  }) async {
    if (eventIds.isEmpty) return [];
    final filter = NostrService.createInteractionFilter(
      kinds: kinds ?? [7, 1, 6, 9735],
      eventIds: eventIds,
      limit: limit,
      since: since,
    );
    return await _executeQuery(filter);
  }

  Future<List<Map<String, dynamic>>> _executeQuery(
      Map<String, dynamic> filter) async {
    final events = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    final request = NostrService.createRequest(filter);
    final requestJson = jsonDecode(request) as List<dynamic>;
    final subscriptionId = requestJson[1] as String;

    final activeRelays = _wsManager.healthyRelays.isNotEmpty
        ? _wsManager.healthyRelays
        : _wsManager.relayUrls;

    if (activeRelays.isEmpty) {
      if (kDebugMode) {
        print('[RelayQueryService] No active relays available');
      }
      return events;
    }

    final completers = <Future<void>>[];

    for (final relayUrl in activeRelays.take(5)) {
      final completer = _wsManager.sendQuery(
        relayUrl,
        request,
        subscriptionId,
        onEvent: (eventMap, url) {
          final eventId = eventMap['id'] as String?;
          if (eventId != null && !seenIds.contains(eventId)) {
            seenIds.add(eventId);
            events.add(eventMap);
          }
        },
        timeout: const Duration(seconds: 15),
      );
      completers.add(completer.then((c) => c.future));
    }

    try {
      await Future.wait(completers).timeout(
        const Duration(seconds: 20),
        onTimeout: () => [],
      );
    } catch (e) {
      if (kDebugMode) {
        print('[RelayQueryService] Query error: $e');
      }
    }

    return events;
  }

  Stream<Map<String, dynamic>> subscribeToFilter(Map<String, dynamic> filter,
      {Duration? timeout}) async* {
    final request = NostrService.createRequest(filter);
    final requestJson = jsonDecode(request) as List<dynamic>;
    final subscriptionId = requestJson[1] as String;

    final controller = StreamController<Map<String, dynamic>>();
    final seenIds = <String>{};

    final activeRelays = _wsManager.healthyRelays.isNotEmpty
        ? _wsManager.healthyRelays
        : _wsManager.relayUrls;

    if (activeRelays.isEmpty) {
      await controller.close();
      return;
    }

    int eoseCount = 0;
    final relayCount = activeRelays.take(5).length;

    for (final relayUrl in activeRelays.take(5)) {
      _wsManager.sendQuery(
        relayUrl,
        request,
        subscriptionId,
        onEvent: (eventMap, url) {
          final eventId = eventMap['id'] as String?;
          if (eventId != null && !seenIds.contains(eventId)) {
            seenIds.add(eventId);
            if (!controller.isClosed) {
              controller.add(eventMap);
            }
          }
        },
        timeout: timeout ?? const Duration(seconds: 30),
      ).then((completer) {
        completer.future.then((_) {
          eoseCount++;
          if (eoseCount >= relayCount && !controller.isClosed) {
            controller.close();
          }
        });
      });
    }

    yield* controller.stream;
  }
}
