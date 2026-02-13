import 'dart:convert';
import '../../src/rust/api/nip17.dart' as nip17;
import '../../src/rust/api/events.dart' as rust_events;
import '../../src/rust/api/database.dart' as rust_db;

class EncryptedBookmarkService {
  static final EncryptedBookmarkService _instance =
      EncryptedBookmarkService._internal();
  static EncryptedBookmarkService get instance => _instance;

  EncryptedBookmarkService._internal();

  List<String> _bookmarkedEventIds = [];
  bool _initialized = false;

  List<String> get bookmarkedEventIds =>
      List.unmodifiable(_bookmarkedEventIds);
  bool get isInitialized => _initialized;

  bool isBookmarked(String eventId) =>
      _bookmarkedEventIds.contains(eventId);

  Future<void> loadFromDatabase({
    required String userPubkeyHex,
    required String privateKeyHex,
  }) async {
    try {
      final filterJson = jsonEncode({
        'kinds': [30001],
        'authors': [userPubkeyHex],
        '#d': ['bookmark'],
      });
      final eventsJson =
          await rust_db.dbQueryEvents(filterJson: filterJson, limit: 1);
      final events = jsonDecode(eventsJson) as List<dynamic>;

      if (events.isEmpty) {
        _bookmarkedEventIds = [];
        _initialized = true;
        return;
      }

      final event = events.first as Map<String, dynamic>;
      final content = event['content'] as String? ?? '';
      final publicIds = _extractEventIdsFromTags(event);

      if (content.isNotEmpty) {
        try {
          final decrypted = nip17.nip44Decrypt(
            payload: content,
            receiverSkHex: privateKeyHex,
            senderPkHex: userPubkeyHex,
          );
          final privateIds = _extractEventIdsFromJson(decrypted);
          _bookmarkedEventIds = [...publicIds, ...privateIds];
        } catch (_) {
          _bookmarkedEventIds = publicIds;
        }
      } else {
        _bookmarkedEventIds = publicIds;
      }
      _initialized = true;
    } catch (_) {
      _initialized = true;
    }
  }

  List<String> _extractEventIdsFromTags(Map<String, dynamic> event) {
    final tags = event['tags'] as List<dynamic>? ?? [];
    return tags
        .where((tag) =>
            tag is List &&
            tag.isNotEmpty &&
            tag[0] == 'e' &&
            tag.length > 1)
        .map((tag) => (tag as List)[1] as String)
        .toList();
  }

  List<String> _extractEventIdsFromJson(String decryptedJson) {
    final privateTags = jsonDecode(decryptedJson) as List<dynamic>;
    return privateTags
        .where((tag) =>
            tag is List &&
            tag.isNotEmpty &&
            tag[0] == 'e' &&
            tag.length > 1)
        .map((tag) => (tag as List)[1] as String)
        .toList();
  }

  Map<String, dynamic> createEncryptedBookmarkEvent({
    required List<String> bookmarkedEventIds,
    required String privateKeyHex,
    required String publicKeyHex,
  }) {
    final privateTags = <List<String>>[
      ...bookmarkedEventIds.map((id) => ['e', id]),
    ];

    final tagsJson = jsonEncode(privateTags);
    final encrypted = nip17.nip44Encrypt(
      content: tagsJson,
      senderSkHex: privateKeyHex,
      receiverPkHex: publicKeyHex,
    );

    final eventJson = rust_events.createSignedEvent(
      kind: 30001,
      content: encrypted,
      tags: [
        ['d', 'bookmark'],
        ['alt', 'List of bookmarks'],
      ],
      privateKeyHex: privateKeyHex,
    );

    _bookmarkedEventIds = List.from(bookmarkedEventIds);
    _initialized = true;

    return jsonDecode(eventJson) as Map<String, dynamic>;
  }

  void addBookmark(String eventId) {
    if (!_bookmarkedEventIds.contains(eventId)) {
      _bookmarkedEventIds = [..._bookmarkedEventIds, eventId];
    }
  }

  void removeBookmark(String eventId) {
    _bookmarkedEventIds =
        _bookmarkedEventIds.where((id) => id != eventId).toList();
  }

  void updateCache({List<String>? eventIds}) {
    if (eventIds != null) _bookmarkedEventIds = List.from(eventIds);
    _initialized = true;
  }

  void clear() {
    _bookmarkedEventIds = [];
    _initialized = false;
  }
}
