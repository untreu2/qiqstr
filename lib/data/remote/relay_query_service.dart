import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/relay_service.dart';
import '../services/nostr_service.dart';

class RelayQueryService {
  final RustRelayService _relayService;

  RelayQueryService({RustRelayService? relayService})
      : _relayService = relayService ?? RustRelayService.instance;

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
    return await _relayService.fetchEvents(filter);
  }

  Future<List<Map<String, dynamic>>> fetchProfiles(List<String> pubkeys) async {
    if (pubkeys.isEmpty) return [];
    final filter = NostrService.createProfileFilter(
      authors: pubkeys,
      limit: pubkeys.length,
    );
    return await _relayService.fetchEvents(filter);
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
    return await _relayService.fetchEvents(filter);
  }

  Future<List<Map<String, dynamic>>> fetchMuteList(String pubkey) async {
    final filter = NostrService.createMuteFilter(
      authors: [pubkey],
      limit: 1,
    );
    return await _relayService.fetchEvents(filter);
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
    return await _relayService.fetchEvents(filter);
  }

  Future<List<Map<String, dynamic>>> fetchReplies({
    required String noteId,
    int? limit,
  }) async {
    final filter = NostrService.createThreadRepliesFilter(
      rootNoteId: noteId,
      limit: limit ?? 100,
    );
    return await _relayService.fetchEvents(filter);
  }

  Future<List<Map<String, dynamic>>> fetchEventsByIds(
      List<String> eventIds) async {
    if (eventIds.isEmpty) return [];
    final filter = NostrService.createEventByIdFilter(eventIds: eventIds);
    return await _relayService.fetchEvents(filter);
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
    return await _relayService.fetchEvents(filter);
  }
}
