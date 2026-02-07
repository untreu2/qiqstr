import 'dart:convert';
import 'package:isar/isar.dart';
import '../../models/event_model.dart';
import 'isar_database_service.dart';
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
      final eventModel =
          await IsarDatabaseService.instance.getEventModel(noteId);
      if (eventModel == null) return false;

      final rawEvent = eventModel.rawEvent;
      if (rawEvent.isEmpty) return false;

      return EventVerifierBridge.verify(rawEvent);
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyProfile(String pubkeyHex) async {
    if (pubkeyHex.isEmpty) return false;

    try {
      final db = await IsarDatabaseService.instance.isar;
      final profileEvent = await db.eventModels
          .where()
          .kindEqualToAnyCreatedAt(0)
          .filter()
          .pubkeyEqualTo(pubkeyHex)
          .sortByCreatedAtDesc()
          .findFirst();

      if (profileEvent == null) return false;

      final rawEvent = profileEvent.rawEvent;
      if (rawEvent.isEmpty) return false;

      final parsed = jsonDecode(rawEvent) as Map<String, dynamic>;
      final sig = parsed['sig'] as String? ?? '';
      if (sig.isEmpty) return false;

      return EventVerifierBridge.verify(rawEvent);
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
