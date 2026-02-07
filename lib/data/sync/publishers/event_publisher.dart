import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../services/nostr_service.dart';
import '../../services/relay_service.dart';
import '../../services/auth_service.dart';
import '../../../models/event_model.dart';

class EventPublisher {
  final AuthService _authService;

  EventPublisher({required AuthService authService})
      : _authService = authService;

  Future<String> _getPrivateKey() async {
    final result = await _authService.getCurrentUserPrivateKey();
    if (result.isError || result.data == null) {
      throw Exception('Not authenticated');
    }
    return result.data!;
  }

  Future<EventModel> createNote({
    required String content,
    List<List<String>>? tags,
  }) async {
    final privateKey = await _getPrivateKey();

    final event = NostrService.createNoteEvent(
      content: content,
      privateKey: privateKey,
      tags: tags,
    );

    return _eventToModel(event);
  }

  Future<EventModel> createReply({
    required String content,
    required String rootId,
    String? replyToId,
    required String rootAuthor,
    String? replyAuthor,
  }) async {
    final privateKey = await _getPrivateKey();
    final relays = await RustRelayService.instance.getRelayList();
    final relayUrl = relays.isNotEmpty ? relays.first : null;

    final tags = NostrService.createReplyTags(
      rootId: rootId,
      replyId: replyToId,
      rootAuthor: rootAuthor,
      replyAuthor: replyAuthor,
      relayUrl: relayUrl,
    );

    final event = NostrService.createReplyEvent(
      content: content,
      privateKey: privateKey,
      tags: tags,
    );

    return _eventToModel(event);
  }

  Future<EventModel> createQuote({
    required String content,
    required String quotedNoteId,
    String? quotedAuthor,
  }) async {
    final privateKey = await _getPrivateKey();

    final event = NostrService.createQuoteEvent(
      content: content,
      quotedEventId: quotedNoteId,
      quotedEventPubkey: quotedAuthor,
      privateKey: privateKey,
    );

    return _eventToModel(event);
  }

  Future<EventModel> createReaction({
    required String targetEventId,
    required String targetAuthor,
    String content = '+',
  }) async {
    final privateKey = await _getPrivateKey();
    final relays = await RustRelayService.instance.getRelayList();
    final relayUrl = relays.isNotEmpty ? relays.first : null;

    final event = NostrService.createReactionEvent(
      targetEventId: targetEventId,
      targetAuthor: targetAuthor,
      content: content,
      privateKey: privateKey,
      relayUrl: relayUrl,
    );

    return _eventToModel(event);
  }

  Future<EventModel> createRepost({
    required String noteId,
    required String noteAuthor,
    required String originalContent,
  }) async {
    final privateKey = await _getPrivateKey();
    final relays = await RustRelayService.instance.getRelayList();
    final relayUrl = relays.isNotEmpty ? relays.first : null;

    final event = NostrService.createRepostEvent(
      noteId: noteId,
      noteAuthor: noteAuthor,
      content: originalContent,
      privateKey: privateKey,
      relayUrl: relayUrl,
    );

    return _eventToModel(event);
  }

  Future<EventModel> createDeletion({
    required List<String> eventIds,
    String? reason,
  }) async {
    final privateKey = await _getPrivateKey();

    final event = NostrService.createDeletionEvent(
      eventIds: eventIds,
      privateKey: privateKey,
      reason: reason,
    );

    return _eventToModel(event);
  }

  Future<EventModel> createFollow({
    required List<String> followingPubkeys,
  }) async {
    final privateKey = await _getPrivateKey();

    final event = NostrService.createFollowEvent(
      followingPubkeys: followingPubkeys,
      privateKey: privateKey,
    );

    return _eventToModel(event);
  }

  Future<EventModel> createMute({
    required List<String> mutedPubkeys,
  }) async {
    final privateKey = await _getPrivateKey();

    final event = NostrService.createMuteEvent(
      mutedPubkeys: mutedPubkeys,
      privateKey: privateKey,
    );

    return _eventToModel(event);
  }

  Future<EventModel> createProfileUpdate({
    required Map<String, dynamic> profileContent,
  }) async {
    final privateKey = await _getPrivateKey();

    final event = NostrService.createProfileEvent(
      profileContent: profileContent,
      privateKey: privateKey,
    );

    return _eventToModel(event);
  }

  Future<bool> broadcast(EventModel eventModel) async {
    try {
      final eventJson = eventModel.toEventData();
      return await RustRelayService.instance.broadcastEvent(eventJson);
    } catch (e) {
      if (kDebugMode) {
        print('[EventPublisher] Broadcast error: $e');
      }
      return false;
    }
  }

  Future<bool> broadcastRawEvent(Map<String, dynamic> event) async {
    try {
      return await RustRelayService.instance.broadcastEvent(event);
    } catch (e) {
      if (kDebugMode) {
        print('[EventPublisher] Broadcast raw event error: $e');
      }
      return false;
    }
  }

  EventModel _eventToModel(Map<String, dynamic> eventData) {
    return EventModel.fromEventData(eventData)..syncStatus = SyncStatus.pending;
  }

  Future<String?> uploadMedia(String filePath,
      {String blossomUrl = 'https://blossom.primal.net'}) async {
    try {
      final privateKey = await _getPrivateKey();
      final url = await NostrService.sendMedia(
        filePath: filePath,
        blossomUrl: blossomUrl,
        privateKey: privateKey,
      );
      return url;
    } catch (e) {
      if (kDebugMode) {
        print('[EventPublisher] Upload media error: $e');
      }
      return null;
    }
  }
}
