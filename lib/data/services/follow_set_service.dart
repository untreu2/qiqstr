import 'dart:convert';
import '../../domain/entities/follow_set.dart';
import '../../src/rust/api/events.dart' as rust_events;
import '../../src/rust/api/database.dart' as rust_db;

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
      final filterJson = jsonEncode({
        'kinds': [30000],
        'authors': [userPubkeyHex],
      });
      final eventsJson =
          await rust_db.dbQueryEvents(filterJson: filterJson, limit: 100);
      final events = jsonDecode(eventsJson) as List<dynamic>;

      _ownSets = _parseSets(events);
      _initialized = true;
    } catch (_) {
      _initialized = true;
    }
  }

  Future<void> loadFollowedUsersSets(
      {required List<String> followedPubkeys}) async {
    if (followedPubkeys.isEmpty) return;
    try {
      final filterJson = jsonEncode({
        'kinds': [30000],
        'authors': followedPubkeys,
      });
      final eventsJson =
          await rust_db.dbQueryEvents(filterJson: filterJson, limit: 500);
      final events = jsonDecode(eventsJson) as List<dynamic>;

      _followedUsersSets = _parseSets(events);
    } catch (_) {}
  }

  static const _hiddenDTags = {'mute', 'Chat-Friends'};

  List<FollowSet> _parseSets(List<dynamic> events) {
    final sets = <FollowSet>[];
    final seenKeys = <String>{};

    final sortedEvents = List<Map<String, dynamic>>.from(
      events.map((e) => e as Map<String, dynamic>),
    )..sort((a, b) {
        final aTime = a['created_at'] as int? ?? 0;
        final bTime = b['created_at'] as int? ?? 0;
        return bTime.compareTo(aTime);
      });

    for (final event in sortedEvents) {
      final followSet = FollowSet.fromEvent(event);
      if (_hiddenDTags.contains(followSet.dTag)) continue;
      final uniqueKey = '${followSet.pubkey}:${followSet.dTag}';
      if (followSet.dTag.isNotEmpty && !seenKeys.contains(uniqueKey)) {
        seenKeys.add(uniqueKey);
        sets.add(followSet);
      }
    }

    return sets;
  }

  Map<String, dynamic> createFollowSetEvent({
    required String dTag,
    required String title,
    required String description,
    required String image,
    required List<String> pubkeys,
    required String privateKeyHex,
  }) {
    final tags = <List<String>>[
      ['d', dTag],
      if (title.isNotEmpty) ['title', title],
      if (description.isNotEmpty) ['description', description],
      if (image.isNotEmpty) ['image', image],
      ...pubkeys.map((pk) => ['p', pk]),
    ];

    final eventJson = rust_events.createSignedEvent(
      kind: 30000,
      content: '',
      tags: tags,
      privateKeyHex: privateKeyHex,
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
