import 'dart:convert';
import '../../src/rust/api/nip17.dart' as nip17;
import '../../src/rust/api/events.dart' as rust_events;
import '../../src/rust/api/database.dart' as rust_db;

class EncryptedMuteService {
  static final EncryptedMuteService _instance =
      EncryptedMuteService._internal();
  static EncryptedMuteService get instance => _instance;

  EncryptedMuteService._internal();

  List<String> _mutedPubkeys = [];
  Set<String> _mutedPubkeySet = {};
  List<String> _mutedWords = [];
  bool _initialized = false;

  List<String> get mutedPubkeys => List.unmodifiable(_mutedPubkeys);
  List<String> get mutedWords => List.unmodifiable(_mutedWords);
  bool get isInitialized => _initialized;

  bool isUserMuted(String pubkey) => _mutedPubkeySet.contains(pubkey);

  bool containsMutedWord(String content) {
    if (_mutedWords.isEmpty) return false;
    final lowerContent = content.toLowerCase();
    return _mutedWords.any((word) => lowerContent.contains(word));
  }

  bool shouldFilterEvent(Map<String, dynamic> event) {
    final pubkey = event['pubkey'] as String? ?? '';
    if (isUserMuted(pubkey)) return true;

    final content = event['content'] as String? ?? '';
    if (containsMutedWord(content)) return true;

    final kind = event['kind'] as int? ?? 0;
    if (kind == 6) {
      final tags = event['tags'] as List<dynamic>? ?? [];
      for (final tag in tags) {
        if (tag is List &&
            tag.isNotEmpty &&
            tag[0] == 'p' &&
            tag.length > 1) {
          final originalAuthor = tag[1] as String?;
          if (originalAuthor != null && isUserMuted(originalAuthor)) {
            return true;
          }
        }
      }
    }

    return false;
  }

  Future<void> loadFromDatabase({
    required String userPubkeyHex,
    required String privateKeyHex,
  }) async {
    try {
      final filterJson = jsonEncode({
        'kinds': [10000],
        'authors': [userPubkeyHex],
      });
      final eventsJson =
          await rust_db.dbQueryEvents(filterJson: filterJson, limit: 1);
      final events = jsonDecode(eventsJson) as List<dynamic>;

      if (events.isEmpty) {
        _mutedPubkeys = [];
        _mutedPubkeySet = {};
        _mutedWords = [];
        _initialized = true;
        return;
      }

      final event = events.first as Map<String, dynamic>;
      final content = event['content'] as String? ?? '';

      if (content.isEmpty) {
        _extractFromPublicTags(event);
      } else {
        try {
          final decrypted = nip17.nip44Decrypt(
            payload: content,
            receiverSkHex: privateKeyHex,
            senderPkHex: userPubkeyHex,
          );
          _extractFromPrivateTags(decrypted);
        } catch (_) {
          _extractFromPublicTags(event);
        }
      }
      _mutedPubkeySet = _mutedPubkeys.toSet();
      _initialized = true;
    } catch (_) {
      _initialized = true;
    }
  }

  void _extractFromPublicTags(Map<String, dynamic> event) {
    final tags = event['tags'] as List<dynamic>? ?? [];
    _mutedPubkeys = tags
        .where(
            (tag) => tag is List && tag.isNotEmpty && tag[0] == 'p' && tag.length > 1)
        .map((tag) => (tag as List)[1] as String)
        .toList();
    _mutedWords = tags
        .where((tag) =>
            tag is List && tag.isNotEmpty && tag[0] == 'word' && tag.length > 1)
        .map((tag) => ((tag as List)[1] as String).toLowerCase())
        .toList();
  }

  void _extractFromPrivateTags(String decryptedJson) {
    final privateTags = jsonDecode(decryptedJson) as List<dynamic>;
    _mutedPubkeys = privateTags
        .where(
            (tag) => tag is List && tag.isNotEmpty && tag[0] == 'p' && tag.length > 1)
        .map((tag) => (tag as List)[1] as String)
        .toList();
    _mutedWords = privateTags
        .where((tag) =>
            tag is List && tag.isNotEmpty && tag[0] == 'word' && tag.length > 1)
        .map((tag) => ((tag as List)[1] as String).toLowerCase())
        .toList();
  }

  Future<Map<String, dynamic>> createEncryptedMuteEvent({
    required List<String> mutedPubkeys,
    required List<String> mutedWords,
    required String privateKeyHex,
    required String publicKeyHex,
  }) async {
    final privateTags = <List<String>>[
      ...mutedPubkeys.map((pk) => ['p', pk]),
      ...mutedWords.map((word) => ['word', word]),
    ];

    final tagsJson = jsonEncode(privateTags);
    final encrypted = nip17.nip44Encrypt(
      content: tagsJson,
      senderSkHex: privateKeyHex,
      receiverPkHex: publicKeyHex,
    );

    final eventJson = await rust_events.signEventWithSigner(
      kind: 10000,
      content: encrypted,
      tags: [],
    );

    _mutedPubkeys = List.from(mutedPubkeys);
    _mutedPubkeySet = _mutedPubkeys.toSet();
    _mutedWords = List.from(mutedWords);
    _initialized = true;

    return jsonDecode(eventJson) as Map<String, dynamic>;
  }

  void addMutedPubkey(String pubkey) {
    if (_mutedPubkeySet.add(pubkey)) {
      _mutedPubkeys = [..._mutedPubkeys, pubkey];
    }
  }

  void removeMutedPubkey(String pubkey) {
    _mutedPubkeys = _mutedPubkeys.where((p) => p != pubkey).toList();
    _mutedPubkeySet = _mutedPubkeys.toSet();
  }

  void addMutedWord(String word) {
    final trimmed = word.trim().toLowerCase();
    if (trimmed.isNotEmpty && !_mutedWords.contains(trimmed)) {
      _mutedWords = [..._mutedWords, trimmed];
    }
  }

  void removeMutedWord(String word) {
    final trimmed = word.trim().toLowerCase();
    _mutedWords = _mutedWords.where((w) => w != trimmed).toList();
  }

  void updateCache({
    List<String>? pubkeys,
    List<String>? words,
  }) {
    if (pubkeys != null) {
      _mutedPubkeys = List.from(pubkeys);
      _mutedPubkeySet = _mutedPubkeys.toSet();
    }
    if (words != null) _mutedWords = List.from(words);
    _initialized = true;
  }

  void clear() {
    _mutedPubkeys = [];
    _mutedPubkeySet = {};
    _mutedWords = [];
    _initialized = false;
  }
}
