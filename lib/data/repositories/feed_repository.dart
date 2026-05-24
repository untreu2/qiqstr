import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import '../../domain/entities/feed_note.dart';
import '../../src/rust/api/database.dart' as rust_db;
import '../services/auth_service.dart';
import '../services/encrypted_mute_service.dart';
import '../services/rust_database_service.dart';

class EmbeddedIdsResult {
  final List<String> quoteEventIds;
  final List<String> articleAuthorPubkeys;

  const EmbeddedIdsResult({
    required this.quoteEventIds,
    required this.articleAuthorPubkeys,
  });
}

sealed class FeedUpdate {
  const FeedUpdate();
}

class FeedSnapshot extends FeedUpdate {
  final List<FeedNote> notes;
  const FeedSnapshot(this.notes);
}

class FeedDelta extends FeedUpdate {
  final List<FeedNote> changed;
  final List<String> removed;
  const FeedDelta({
    this.changed = const [],
    this.removed = const [],
  });
}

abstract interface class FeedRepository {
  Stream<FeedUpdate> watchFeed(
    String userPubkey, {
    List<String>? authors,
    int limit,
    String sortMode,
  });

  Future<List<FeedNote>> getFeed(
    String userPubkey, {
    List<String>? authors,
    int limit,
  });

  Stream<List<FeedNote>> watchNotes(String pubkey, {int limit});

  Future<List<FeedNote>> getNotes(String pubkey,
      {int limit, int? untilTimestamp});

  Stream<List<FeedNote>> watchUserReplies(String pubkey, {int limit});

  Future<List<FeedNote>> getUserReplies(String pubkey,
      {int limit, int? untilTimestamp});

  Stream<({List<FeedNote> notes, List<FeedNote> replies})>
      watchProfileNotesAndReplies(
    String pubkey, {
    int notesLimit,
    int repliesLimit,
    int debounceMs,
  });

  Stream<List<FeedNote>> watchLikes(String pubkey, {int limit});

  Future<List<FeedNote>> getLikes(String pubkey, {int limit});

  Stream<FeedUpdate> watchHashtag(String hashtag, {int limit});

  Future<FeedNote?> getNote(String noteId);

  Stream<FeedNote?> watchNote(String noteId);

  Future<List<FeedNote>> getThreadReplies(String noteId, {int limit});

  Stream<List<FeedNote>> watchThreadReplies(String noteId, {int limit});

  Future<List<FeedNote>> getNotesByIds(List<String> noteIds);

  Future<List<FeedNote>> searchNotes(String query, {int limit});

  EmbeddedIdsResult extractEmbeddedIds(List<String> contents);

  Future<void> save(List<Map<String, dynamic>> notes);
}

class FeedRepositoryImpl implements FeedRepository {
  final RustDatabaseService _events;

  FeedRepositoryImpl({required RustDatabaseService events}) : _events = events;

  List<String> get _mutedPubkeys => EncryptedMuteService.instance.mutedPubkeys;
  List<String> get _mutedWords => EncryptedMuteService.instance.mutedWords;
  String? get _currentUserHex => AuthService.instance.currentUserPubkeyHex;

  Stream<T> _onChange<T>(Future<T> Function() fetch, {int debounceMs = 300}) {
    return _events.onFeedChange
        .debounceTime(Duration(milliseconds: debounceMs))
        .startWith(null)
        .asyncMap((_) => fetch());
  }

  @override
  Stream<FeedUpdate> watchFeed(
    String userPubkey, {
    List<String>? authors,
    int limit = 50,
    String sortMode = 'latest',
  }) async* {
    if (userPubkey.isEmpty || userPubkey.length != 64) {
      yield const FeedSnapshot(<FeedNote>[]);
      return;
    }
    if (authors != null && authors.isEmpty) {
      yield const FeedSnapshot(<FeedNote>[]);
      return;
    }

    final initial = await _fetchFeed(userPubkey, authors, limit, sortMode);
    yield FeedSnapshot(initial);

    final feedEvents = _events.onDbChange
        .where((e) =>
            e.type == DbChangeType.feed || e.type == DbChangeType.generic)
        .bufferTime(const Duration(milliseconds: 300))
        .where((batch) => batch.isNotEmpty);

    await for (final batch in feedEvents) {
      final allIds = <String>{};
      bool hasUntargeted = false;
      for (final e in batch) {
        if (e.ids.isEmpty) {
          hasUntargeted = true;
          break;
        }
        allIds.addAll(e.ids);
      }

      if (hasUntargeted || allIds.isEmpty) {
        final snapshot =
            await _fetchFeed(userPubkey, authors, limit, sortMode);
        yield FeedSnapshot(snapshot);
      } else {
        try {
          final changed = await getNotesByIds(allIds.toList());
          if (changed.isNotEmpty) {
            yield FeedDelta(changed: changed);
          }
        } catch (e) {
          if (kDebugMode) print('[FeedRepository] delta fetch error: $e');
        }
      }
    }
  }

  Future<List<FeedNote>> _fetchFeed(
    String userPubkey,
    List<String>? authors,
    int limit,
    String sortMode,
  ) async {
    try {
      final json = await rust_db.dbGetHydratedFeedNotesSorted(
        userPubkeyHex: userPubkey,
        authorsHex: authors,
        limit: limit,
        filterReplies: true,
        currentUserPubkeyHex: _currentUserHex,
        sortMode: sortMode,
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

  @override
  Future<List<FeedNote>> getFeed(
    String userPubkey, {
    List<String>? authors,
    int limit = 100,
  }) =>
      _fetchFeed(userPubkey, authors, limit, 'latest');

  @override
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

  @override
  Future<List<FeedNote>> getNotes(String pubkey,
      {int limit = 50, int? untilTimestamp}) async {
    final maps =
        await _fetchNotes(pubkey, limit, untilTimestamp: untilTimestamp);
    return maps.map((m) => FeedNote.fromMap(m)).toList();
  }

  @override
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

  @override
  Future<List<FeedNote>> getUserReplies(String pubkey,
      {int limit = 50, int? untilTimestamp}) async {
    final maps =
        await _fetchUserReplies(pubkey, limit, untilTimestamp: untilTimestamp);
    return maps.map((m) => FeedNote.fromMap(m)).toList();
  }

  @override
  Stream<({List<FeedNote> notes, List<FeedNote> replies})>
      watchProfileNotesAndReplies(
    String pubkey, {
    int notesLimit = 200,
    int repliesLimit = 200,
    int debounceMs = 500,
  }) async* {
    Future<({List<FeedNote> notes, List<FeedNote> replies})>
        fetchBoth() async {
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

    yield* _events.onFeedChange
        .debounceTime(Duration(milliseconds: debounceMs))
        .asyncMap((_) => fetchBoth());
  }

  @override
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

  @override
  Future<List<FeedNote>> getLikes(String pubkey, {int limit = 50}) async {
    final maps = await _fetchLikes(pubkey, limit);
    return maps.map((m) => FeedNote.fromMap(m)).toList();
  }

  @override
  Stream<FeedUpdate> watchHashtag(String hashtag, {int limit = 50}) async* {
    Future<List<FeedNote>> fetch() async {
      try {
        final json = await rust_db.dbGetHydratedHashtagNotes(
          hashtag: hashtag,
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
        if (kDebugMode) print('[FeedRepository] watchHashtag error: $e');
        return <FeedNote>[];
      }
    }

    yield FeedSnapshot(await fetch());

    final feedEvents = _events.onDbChange
        .where((e) =>
            e.type == DbChangeType.feed || e.type == DbChangeType.generic)
        .bufferTime(const Duration(milliseconds: 300))
        .where((batch) => batch.isNotEmpty);

    await for (final batch in feedEvents) {
      final allIds = <String>{};
      bool hasUntargeted = false;
      for (final e in batch) {
        if (e.ids.isEmpty) {
          hasUntargeted = true;
          break;
        }
        allIds.addAll(e.ids);
      }

      if (hasUntargeted || allIds.isEmpty) {
        yield FeedSnapshot(await fetch());
      } else {
        try {
          final changed = await getNotesByIds(allIds.toList());
          if (changed.isNotEmpty) {
            yield FeedDelta(changed: changed);
          }
        } catch (e) {
          if (kDebugMode) print('[FeedRepository] hashtag delta error: $e');
        }
      }
    }
  }

  @override
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

  @override
  Stream<FeedNote?> watchNote(String noteId) {
    return _onChange(() => getNote(noteId));
  }

  @override
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

  @override
  Stream<List<FeedNote>> watchThreadReplies(String noteId, {int limit = 100}) {
    return _events.onFeedChange
        .debounceTime(const Duration(milliseconds: 200))
        .startWith(null)
        .asyncMap((_) => getThreadReplies(noteId, limit: limit));
  }

  @override
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

  @override
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

  @override
  EmbeddedIdsResult extractEmbeddedIds(List<String> contents) {
    try {
      final (quoteIds, articlePubkeys) =
          rust_db.extractEmbeddedIdsBatchTyped(contents: contents);
      return EmbeddedIdsResult(
        quoteEventIds: quoteIds,
        articleAuthorPubkeys: articlePubkeys,
      );
    } catch (e) {
      if (kDebugMode) {
        print('[FeedRepository] extractEmbeddedIds error: $e');
      }
      return const EmbeddedIdsResult(
          quoteEventIds: [], articleAuthorPubkeys: []);
    }
  }

  @override
  Future<void> save(List<Map<String, dynamic>> notes) async {
    if (notes.isEmpty) return;
    try {
      final json = jsonEncode(notes);
      await rust_db.dbSaveEvents(eventsJson: json);
      _events.notifyFeedChange();
    } catch (e) {
      if (kDebugMode) print('[FeedRepository] save error: $e');
    }
  }
}
