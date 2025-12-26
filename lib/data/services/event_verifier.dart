import 'dart:convert';
import 'package:ndk/ndk.dart';
import 'package:ndk/entities.dart';
import '../../models/note_model.dart';

class EventVerifier {
  static final EventVerifier _instance = EventVerifier._internal();
  factory EventVerifier() => _instance;
  EventVerifier._internal();

  static EventVerifier get instance => _instance;

  Future<bool> verifyNote(NoteModel note) async {
    if (note.rawWs == null || note.rawWs!.isEmpty) {
      return false;
    }

    try {
      final eventJson = jsonDecode(note.rawWs!) as Map<String, dynamic>;
      final event = Nip01Event.fromJson(eventJson);
      
      final verifier = Bip340EventVerifier();
      return await verifier.verify(event);
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyEventJson(Map<String, dynamic> eventJson) async {
    try {
      final event = Nip01Event.fromJson(eventJson);
      final verifier = Bip340EventVerifier();
      return await verifier.verify(event);
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyEventString(String eventJsonString) async {
    try {
      final eventJson = jsonDecode(eventJsonString) as Map<String, dynamic>;
      return await verifyEventJson(eventJson);
    } catch (_) {
      return false;
    }
  }
}

