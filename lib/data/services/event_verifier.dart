import 'dart:convert';
import 'rust_database_service.dart';
import 'rust_nostr_bridge.dart';

class EventVerifier {
  static final EventVerifier _instance = EventVerifier._internal();
  factory EventVerifier() => _instance;
  EventVerifier._internal();

  static EventVerifier get instance => _instance;

  Future<bool> verifyNote(Map<String, dynamic> note) async {
    final noteId = note['id'] as String? ?? '';
    if (noteId.isEmpty) return false;

    try {
      final eventData =
          await RustDatabaseService.instance.getEventModel(noteId);
      if (eventData == null) return false;

      final rawEvent = jsonEncode(eventData);
      if (rawEvent.isEmpty) return false;

      return EventVerifierBridge.verify(rawEvent);
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyProfile(String pubkeyHex) async {
    if (pubkeyHex.isEmpty) return false;

    try {
      final profile =
          await RustDatabaseService.instance.getUserProfile(pubkeyHex);
      if (profile == null) return false;

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyEventJson(Map<String, dynamic> eventJson) async {
    try {
      return EventVerifierBridge.verify(jsonEncode(eventJson));
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyEventString(String eventJsonString) async {
    try {
      return EventVerifierBridge.verify(eventJsonString);
    } catch (_) {
      return false;
    }
  }
}
