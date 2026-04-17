import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import '../../domain/entities/feed_note.dart';
import '../../src/rust/api/database.dart' as rust_db;
import '../services/auth_service.dart';
import '../services/encrypted_mute_service.dart';
import '../services/rust_database_service.dart';

class FeedRepository {
  final RustDatabaseService _events;

  FeedRepository({required RustDatabaseService events}) : _events = events;

  List<String> get _mutedPubkeys => EncryptedMuteService.instance.mutedPubkeys;
  List<String> get _mutedWords => EncryptedMuteService.instance.mutedWords;
  String? get _currentUserHex => AuthService.instance.currentUserPubkeyHex;

  Stream<T> _onChange<T>(Future<T> Function() fetch, {int debounceMs = 300}) {
    return _events.onFeedChange
        .debounceTime(Duration(milliseconds: debounceMs))
        .startWith(null)
        .asyncMap((_) => fetch());
  }

  Stream<List<FeedNote>> watchFeed(
    String userPubkey, {
    List<String>? authors,
    int limit = 100,
  }) async* {
    if (userPubkey.isEmpty || userPubkey.length != 64) {
      yield [];
      return;
    }
    if (authors != null && authors.isEmpty) {
      yield [];
      return;
    }

    final initial = await _fetchFeed(userPubkey, authors, limit);
    if (initial.isNotEmpty) yield initial;

    yield* _events.onFeedChange
        .debounceTime(const Duration(milliseconds: 300))
        .startWith(null)
        .asyncMap((_) => _fetchFeed(userPubkey, authors, limit));
  }

  Future<List<FeedNote>> _fetchFeed(
    String userPubkey,
    List<String>? authors,
    int limit,
  ) async {
    try {
      final json = await rust_db.dbGetHydratedFeedNotes(
        userPubkeyHex: userPubkey,
        authorsHex: authors,
        limit: limit,
        mutedPubkeys: _mutedPubkeys,
        mutedWords: _mutedWords,
        filterReplies: true,
        currentUserPubkeyHex: _currentUserHex,
      );
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded
          .cast<Map<String, dynamic>>()
          .map((m) => FeedNote.fromMap(m))
          .toList();
    } catch (e) {
      if (kDebugMode) print('[FeedRepository] fetchFeed error: $e');
      return [];
    }
  }

  Future<List<FeedNote>> getFeed(
    String userPubkey, {
    List<String>? authors,
    int limit = 100,
  }) =>
      _fetchFeed(userPubkey, authors, limit);

  Stream<List<FeedNote>> watchNotes(String pubkey, {int limit = 50}) async* {
    final initial = await _fetchNotes(pubkey, limit);
    if (initial.isNotEmpty) {
      yield initial.map((m) => FeedNote.fromMap(m)).toList();
    }
    yield* _onChange(() => _fetchNotes(pubkey, limit))
        .map((maps) => maps.map((m) => FeedNote.fromMap(m)).toList());
  }

  Future<List<Map<String, dynamic>>> _fetchNotes(String pubkey, int limit,
      {int? untilTimestamp}) async {
    try {
      final json = await rust_db.dbGetHydratedProfileNotes(
        pubkeyHex: pubkey,
        limit: limit,
        mutedPubkeys: _mutedPubkeys,
        mutedWords: _mutedWords,
        filterReplies: true,
        currentUserPubkeyHex: _currentUserHex,
        untilTimestamp: untilTimestamp,
      );
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('[FeedRepository] getNotes error: $e');
      return [];
    }
  }

  Future<List<FeedNote>> getNotes(String pubkey,
      {int limit = 50, int? untilTimestamp}) async {
    final maps =
        await _fetchNotes(pubkey, limit, untilTimestamp: untilTimestamp);
    return maps.map((m) => FeedNote.fromMap(m)).toList();
  }

  Stream<List<FeedNote>> watchUserReplies(String pubkey,
      {int limit = 50}) async* {
    final initial = await _fetchUserReplies(pubkey, limit);
    if (initial.isNotEmpty) {
      yield initial.map((m) => FeedNote.fromMap(m)).toList();
    }
    yield* _onChange(() => _fetchUserReplies(pubkey, limit))
        .map((maps) => maps.map((m) => FeedNote.fromMap(m)).toList());
  }

  Future<List<Map<String, dynamic>>> _fetchUserReplies(String pubkey, int limit,
      {int? untilTimestamp}) async {
    try {
      final json = await rust_db.dbGetHydratedProfileReplies(
        pubkeyHex: pubkey,
        limit: limit,
        mutedPubkeys: _mutedPubkeys,
        mutedWords: _mutedWords,
        currentUserPubkeyHex: _currentUserHex,
        untilTimestamp: untilTimestamp,
      );
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('[FeedRepository] getUserReplies error: $e');
      return [];
    }
  }

  Future<List<FeedNote>> getUserReplies(String pubkey,
      {int limit = 50, int? untilTimestamp}) async {
    final maps =
        await _fetchUserReplies(pubkey, limit, untilTimestamp: untilTimestamp);
    return maps.map((m) => FeedNote.fromMap(m)).toList();
  }

  Stream<({List<FeedNote> notes, List<FeedNote> replies})>
      watchProfileNotesAndReplies(String pubkey,
          {int notesLimit = 200,
          int repliesLimit = 200,
          int debounceMs = 500}) async* {
    Future<({List<FeedNote> notes, List<FeedNote> replies})> fetchBoth() async {
      final results = await Future.wait([
        _fetchNotes(pubkey, notesLimit),
        _fetchUserReplies(pubkey, repliesLimit),
      ]);
      return (
        notes: results[0].map((m) => FeedNote.fromMap(m)).toList(),
        replies: results[1].map((m) => FeedNote.fromMap(m)).toList(),
      );
    }

    final initial = await fetchBoth();
    yield initial;

    yield* _events.onChange
        .debounceTime(Duration(milliseconds: debounceMs))
        .asyncMap((_) => fetchBoth());
  }

  Stream<List<FeedNote>> watchLikes(String pubkey, {int limit = 50}) async* {
    final initial = await _fetchLikes(pubkey, limit);
    if (initial.isNotEmpty) {
      yield initial.map((m) => FeedNote.fromMap(m)).toList();
    }
    yield* _onChange(() => _fetchLikes(pubkey, limit))
        .map((maps) => maps.map((m) => FeedNote.fromMap(m)).toList());
  }

  Future<List<Map<String, dynamic>>> _fetchLikes(
      String pubkey, int limit) async {
    try {
      final json = await rust_db.dbGetHydratedReactionNotes(
        pubkeyHex: pubkey,
        limit: limit,
        mutedPubkeys: _mutedPubkeys,
        mutedWords: _mutedWords,
        currentUserPubkeyHex: _currentUserHex,
      );
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('[FeedRepository] getLikes error: $e');
      return [];
    }
  }

  Future<List<FeedNote>> getLikes(String pubkey, {int limit = 50}) async {
    final maps = await _fetchLikes(pubkey, limit);
    return maps.map((m) => FeedNote.fromMap(m)).toList();
  }

  Stream<List<FeedNote>> watchHashtag(String hashtag, {int limit = 100}) {
    return _onChange(() async {
      try {
        final json = await rust_db.dbGetHydratedHashtagNotes(
          hashtag: hashtag,
          limit: limit,
          mutedPubkeys: _mutedPubkeys,
          mutedWords: _mutedWords,
          currentUserPubkeyHex: _currentUserHex,
        );
        final decoded = jsonDecode(json) as List<dynamic>;
        return decoded.cast<Map<String, dynamic>>();
      } catch (e) {
        if (kDebugMode) print('[FeedRepository] watchHashtag error: $e');
        return <Map<String, dynamic>>[];
      }
    }).map((maps) => maps.map((m) => FeedNote.fromMap(m)).toList());
  }

  Future<FeedNote?> getNote(String noteId) async {
    try {
      final json = await rust_db.dbGetHydratedNote(
        eventId: noteId,
        currentUserPubkeyHex: _currentUserHex,
      );
      if (json == null) return null;
      final map = jsonDecode(json) as Map<String, dynamic>;
      return FeedNote.fromMap(map);
    } catch (e) {
      if (kDebugMode) print('[FeedRepository] getNote error: $e');
      return null;
    }
  }

  Stream<FeedNote?> watchNote(String noteId) async* {
    yield await getNote(noteId);
  }

  Future<List<FeedNote>> getThreadReplies(String noteId,
      {int limit = 500}) async {
    try {
      final json = await rust_db.dbGetHydratedReplies(
        noteId: noteId,
        limit: limit,
        mutedPubkeys: _mutedPubkeys,
        mutedWords: _mutedWords,
        currentUserPubkeyHex: _currentUserHex,
      );
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded
          .cast<Map<String, dynamic>>()
          .map((m) => FeedNote.fromMap(m))
          .toList();
    } catch (e) {
      if (kDebugMode) print('[FeedRepository] getThreadReplies error: $e');
      return [];
    }
  }

  Stream<List<FeedNote>> watchThreadReplies(String noteId, {int limit = 100}) {
    return _events.onChange
        .debounceTime(const Duration(milliseconds: 200))
        .startWith(null)
        .asyncMap((_) => getThreadReplies(noteId, limit: limit));
  }

  Future<List<FeedNote>> getNotesByIds(List<String> noteIds) async {
    if (noteIds.isEmpty) return [];
    try {
      final json = await rust_db.dbGetHydratedNotesByIds(
        eventIds: noteIds,
        mutedPubkeys: _mutedPubkeys,
        mutedWords: _mutedWords,
        currentUserPubkeyHex: _currentUserHex,
      );
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded
          .cast<Map<String, dynamic>>()
          .map((m) => FeedNote.fromMap(m))
          .toList();
    } catch (e) {
      if (kDebugMode) print('[FeedRepository] getNotesByIds error: $e');
      return [];
    }
  }

  Future<List<FeedNote>> searchNotes(String query, {int limit = 50}) async {
    try {
      final json = await rust_db.dbSearchNotes(query: query, limit: limit);
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded
          .cast<Map<String, dynamic>>()
          .map((m) => FeedNote.fromMap(m))
          .toList();
    } catch (e) {
      if (kDebugMode) print('[FeedRepository] searchNotes error: $e');
      return [];
    }
  }

  Future<void> save(List<Map<String, dynamic>> notes) async {
    if (notes.isEmpty) return;
    try {
      final json = jsonEncode(notes);
      await rust_db.dbSaveEvents(eventsJson: json);
      _events.notifyChange();
    } catch (e) {
      if (kDebugMode) print('[FeedRepository] save error: $e');
    }
  }
}
