import 'dart:async';
import 'dart:convert';
import '../../src/rust/api/events.dart' as rust_events;
import '../../src/rust/api/database.dart' as rust_db;

class PinnedNotesService {
  static final PinnedNotesService _instance = PinnedNotesService._internal();
  static PinnedNotesService get instance => _instance;

  PinnedNotesService._internal();

  String? _currentUserPubkey;
  List<String> _pinnedNoteIds = [];
  bool _initialized = false;

  final _controller = StreamController<List<String>>.broadcast();

  List<String> get pinnedNoteIds => List.unmodifiable(_pinnedNoteIds);
  bool get isInitialized => _initialized;
  Stream<List<String>> get pinnedNoteIdsStream => _controller.stream;

  bool isPinned(String noteId) => _pinnedNoteIds.contains(noteId);

  Future<void> loadFromDatabase({
    required String userPubkeyHex,
  }) async {
    if (_currentUserPubkey != null && _currentUserPubkey != userPubkeyHex) {
      _pinnedNoteIds = [];
      _initialized = false;
    }
    _currentUserPubkey = userPubkeyHex;

    try {
      final filterJson = jsonEncode({
        'kinds': [10001],
        'authors': [userPubkeyHex],
      });
      final eventsJson =
          await rust_db.dbQueryEvents(filterJson: filterJson, limit: 1);
      final events = jsonDecode(eventsJson) as List<dynamic>;

      if (events.isEmpty) {
        _pinnedNoteIds = [];
        _initialized = true;
        return;
      }

      final event = events.first as Map<String, dynamic>;
      _pinnedNoteIds = _extractEventIdsFromTags(event);
      _initialized = true;
    } catch (_) {
      _initialized = true;
    }
  }

  Future<List<String>> fetchPinnedNoteIdsForUser(String pubkeyHex) async {
    try {
      final filterJson = jsonEncode({
        'kinds': [10001],
        'authors': [pubkeyHex],
      });
      final eventsJson =
          await rust_db.dbQueryEvents(filterJson: filterJson, limit: 1);
      final events = jsonDecode(eventsJson) as List<dynamic>;

      if (events.isEmpty) return [];

      final event = events.first as Map<String, dynamic>;
      return _extractEventIdsFromTags(event);
    } catch (_) {
      return [];
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

  Map<String, dynamic> createPinnedNotesEvent({
    required List<String> pinnedNoteIds,
    required String privateKeyHex,
  }) {
    final tags = <List<String>>[
      ...pinnedNoteIds.map((id) => ['e', id]),
    ];

    final eventJson = rust_events.createSignedEvent(
      kind: 10001,
      content: '',
      tags: tags,
      privateKeyHex: privateKeyHex,
    );

    _pinnedNoteIds = List.from(pinnedNoteIds);
    _initialized = true;

    return jsonDecode(eventJson) as Map<String, dynamic>;
  }

  void pinNote(String noteId) {
    if (!_pinnedNoteIds.contains(noteId)) {
      _pinnedNoteIds = [..._pinnedNoteIds, noteId];
      _controller.add(List.unmodifiable(_pinnedNoteIds));
    }
  }

  void unpinNote(String noteId) {
    if (_pinnedNoteIds.contains(noteId)) {
      _pinnedNoteIds = _pinnedNoteIds.where((id) => id != noteId).toList();
      _controller.add(List.unmodifiable(_pinnedNoteIds));
    }
  }

  void clear() {
    _currentUserPubkey = null;
    _pinnedNoteIds = [];
    _initialized = false;
  }
}
