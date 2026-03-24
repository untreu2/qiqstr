import 'dart:convert';
import '../../domain/entities/follow_set.dart';
import '../../src/rust/api/events.dart' as rust_events;
import '../../src/rust/api/database.dart' as rust_db;

const _hiddenDTagsList = ['mute', 'Chat-Friends'];

class FollowSetService {
  static final FollowSetService _instance = FollowSetService._internal();
  static FollowSetService get instance => _instance;

  FollowSetService._internal();

  List<FollowSet> _ownSets = [];
  List<FollowSet> _followedUsersSets = [];
  bool _initialized = false;

  List<FollowSet> get followSets => List.unmodifiable(_ownSets);
  List<FollowSet> get followedUsersSets =>
      List.unmodifiable(_followedUsersSets);
  List<FollowSet> get allSets =>
      List.unmodifiable([..._ownSets, ..._followedUsersSets]);
  bool get isInitialized => _initialized;

  FollowSet? getByDTag(String dTag) {
    try {
      return _ownSets.firstWhere((s) => s.dTag == dTag);
    } catch (_) {
      return null;
    }
  }

  FollowSet? getByListId(String listId) {
    final parts = listId.split(':');
    if (parts.length < 2) return getByDTag(listId);
    final pubkey = parts[0];
    final dTag = parts.sublist(1).join(':');
    try {
      return allSets.firstWhere(
        (s) => s.pubkey == pubkey && s.dTag == dTag,
      );
    } catch (_) {
      return null;
    }
  }

  List<String>? pubkeysForList(String listId) {
    return getByListId(listId)?.pubkeys;
  }

  Future<void> loadFromDatabase({required String userPubkeyHex}) async {
    try {
      _ownSets = await _fetchFollowSets([userPubkeyHex], 100);
      _initialized = true;
    } catch (_) {
      _initialized = true;
    }
  }

  Future<void> loadFollowedUsersSets(
      {required List<String> followedPubkeys}) async {
    if (followedPubkeys.isEmpty) return;
    try {
      _followedUsersSets = await _fetchFollowSets(followedPubkeys, 500);
    } catch (_) {}
  }

  Future<List<FollowSet>> _fetchFollowSets(
      List<String> authors, int limit) async {
    final json = await rust_db.dbGetFollowSets(
      authorsHex: authors,
      limit: limit,
      hiddenDTags: _hiddenDTagsList,
    );
    final decoded = jsonDecode(json) as List<dynamic>;
    return decoded
        .map((e) => FollowSet.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> createFollowSetEvent({
    required String dTag,
    required String title,
    required String description,
    required String image,
    required List<String> pubkeys,
  }) async {
    final tags = <List<String>>[
      ['d', dTag],
      if (title.isNotEmpty) ['title', title],
      if (description.isNotEmpty) ['description', description],
      if (image.isNotEmpty) ['image', image],
      ...pubkeys.map((pk) => ['p', pk]),
    ];

    final eventJson = await rust_events.signEventWithSigner(
      kind: 30000,
      content: '',
      tags: tags,
    );

    final event = jsonDecode(eventJson) as Map<String, dynamic>;
    final followSet = FollowSet.fromEvent(event);

    _ownSets = [
      followSet,
      ..._ownSets.where((s) => s.dTag != dTag),
    ];
    _initialized = true;

    return event;
  }

  void addSet(FollowSet followSet) {
    _ownSets = [
      followSet,
      ..._ownSets.where((s) => s.dTag != followSet.dTag),
    ];
  }

  void removeSet(String dTag) {
    _ownSets = _ownSets.where((s) => s.dTag != dTag).toList();
  }

  void addPubkeyToSet(String dTag, String pubkey) {
    final index = _ownSets.indexWhere((s) => s.dTag == dTag);
    if (index == -1) return;

    final set = _ownSets[index];
    if (set.pubkeys.contains(pubkey)) return;

    _ownSets[index] = set.copyWith(
      pubkeys: [...set.pubkeys, pubkey],
    );
  }

  void removePubkeyFromSet(String dTag, String pubkey) {
    final index = _ownSets.indexWhere((s) => s.dTag == dTag);
    if (index == -1) return;

    final set = _ownSets[index];
    _ownSets[index] = set.copyWith(
      pubkeys: set.pubkeys.where((p) => p != pubkey).toList(),
    );
  }

  void clear() {
    _ownSets = [];
    _followedUsersSets = [];
    _initialized = false;
  }
}
