import '../../src/rust/api/crypto.dart' as rust_crypto;

class EventVerifier {
  static final EventVerifier _instance = EventVerifier._internal();
  factory EventVerifier() => _instance;
  EventVerifier._internal();

  static EventVerifier get instance => _instance;

  Future<bool> verifyNote(Map<String, dynamic> note) async {
    final noteId = note['id'] as String? ?? '';
    if (noteId.isEmpty) return false;

    try {
      return await rust_crypto.verifyNoteById(eventIdHex: noteId);
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyProfile(String pubkeyHex) async {
    if (pubkeyHex.isEmpty) return false;

    try {
      return await rust_crypto.verifyProfileByPubkey(pubkeyHex: pubkeyHex);
    } catch (_) {
      return false;
    }
  }
}
