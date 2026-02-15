import 'dart:async';
import '../../domain/entities/feed_note.dart';
import 'base_repository.dart';

abstract class FeedRepository {
  Stream<List<FeedNote>> watchFeed(String userPubkey, {int limit = 100});
  Stream<List<FeedNote>> watchListFeed(List<String> pubkeys, {int limit = 100});
  Future<List<FeedNote>> getFeed(String userPubkey, {int limit = 100});
  Stream<List<FeedNote>> watchProfileNotes(String pubkey, {int limit = 50});
  Future<List<FeedNote>> getProfileNotes(String pubkey, {int limit = 50});
  Stream<List<FeedNote>> watchProfileReplies(String pubkey, {int limit = 50});
  Future<List<FeedNote>> getProfileReplies(String pubkey, {int limit = 50});
  Stream<List<FeedNote>> watchProfileLikes(String pubkey, {int limit = 50});
  Future<List<FeedNote>> getProfileLikes(String pubkey, {int limit = 50});
  Stream<List<FeedNote>> watchHashtagFeed(String hashtag, {int limit = 100});
  Future<FeedNote?> getNote(String noteId);
  Future<Map<String, dynamic>?> getNoteRaw(String noteId);
  Stream<FeedNote?> watchNote(String noteId);
  Future<List<FeedNote>> getReplies(String noteId, {int limit = 100});
  Future<List<Map<String, dynamic>>> getRepliesRaw(String noteId,
      {int limit = 100});
  Stream<List<FeedNote>> watchReplies(String noteId, {int limit = 100});
  Future<void> saveNotes(List<Map<String, dynamic>> notes);
  Future<List<String>?> getFollowingList(String userPubkey);
}

class FeedRepositoryImpl extends BaseRepository implements FeedRepository {
  FeedRepositoryImpl({
    required super.db,
    required super.mapper,
  });

  @override
  Stream<List<FeedNote>> watchFeed(String userPubkey,
      {int limit = 100}) async* {
    if (userPubkey.isEmpty || userPubkey.length != 64) {
      yield [];
      return;
    }

    var follows = await db.getFollowingList(userPubkey);

    if (follows == null || follows.isEmpty) {
      yield [];
      await for (final _ in db.onChange) {
        follows = await db.getFollowingList(userPubkey);
        if (follows != null && follows.isNotEmpty) break;
      }
      if (follows == null || follows.isEmpty) return;
    }

    final activeFollows = follows;

    final initial =
        await db.getHydratedFeedNotes(activeFollows, limit: limit);
    if (initial.isNotEmpty) {
      yield initial.map((m) => FeedNote.fromMap(m)).toList();
    }

    yield* db
        .watchHydratedFeedNotes(activeFollows, limit: limit)
        .map((maps) => maps.map((m) => FeedNote.fromMap(m)).toList());
  }

  @override
  Stream<List<FeedNote>> watchListFeed(List<String> pubkeys,
      {int limit = 100}) async* {
    if (pubkeys.isEmpty) {
      yield [];
      return;
    }

    final initial = await db.getHydratedFeedNotes(pubkeys, limit: limit);
    if (initial.isNotEmpty) {
      yield initial.map((m) => FeedNote.fromMap(m)).toList();
    }

    yield* db
        .watchHydratedFeedNotes(pubkeys, limit: limit)
        .map((maps) => maps.map((m) => FeedNote.fromMap(m)).toList());
  }

  @override
  Future<List<FeedNote>> getFeed(String userPubkey, {int limit = 100}) async {
    final follows = await db.getFollowingList(userPubkey);
    if (follows == null || follows.isEmpty) {
      return [];
    }

    final maps = await db.getHydratedFeedNotes(follows, limit: limit);
    return maps.map((m) => FeedNote.fromMap(m)).toList();
  }

  @override
  Stream<List<FeedNote>> watchProfileNotes(String pubkey,
      {int limit = 50}) async* {
    final initial =
        await db.getHydratedProfileNotes(pubkey, limit: limit);
    if (initial.isNotEmpty) {
      yield initial.map((m) => FeedNote.fromMap(m)).toList();
    }

    yield* db
        .watchHydratedProfileNotes(pubkey, limit: limit)
        .map((maps) => maps.map((m) => FeedNote.fromMap(m)).toList());
  }

  @override
  Future<List<FeedNote>> getProfileNotes(String pubkey,
      {int limit = 50}) async {
    final maps = await db.getHydratedProfileNotes(pubkey, limit: limit);
    return maps.map((m) => FeedNote.fromMap(m)).toList();
  }

  @override
  Stream<List<FeedNote>> watchProfileReplies(String pubkey,
      {int limit = 50}) async* {
    final initial = await db.getHydratedProfileNotes(pubkey,
        limit: limit, filterReplies: false);
    if (initial.isNotEmpty) {
      final all = initial.map((m) => FeedNote.fromMap(m)).toList();
      yield all.where((n) => n.isReply && !n.isRepost).toList();
    }

    yield* db
        .watchHydratedProfileNotes(pubkey,
            limit: limit, filterReplies: false)
        .map((maps) {
      final all = maps.map((m) => FeedNote.fromMap(m)).toList();
      return all.where((n) => n.isReply && !n.isRepost).toList();
    });
  }

  @override
  Future<List<FeedNote>> getProfileReplies(String pubkey,
      {int limit = 50}) async {
    final maps = await db.getHydratedProfileNotes(pubkey,
        limit: limit, filterReplies: false);
    final all = maps.map((m) => FeedNote.fromMap(m)).toList();
    return all.where((n) => n.isReply && !n.isRepost).toList();
  }

  @override
  Stream<List<FeedNote>> watchProfileLikes(String pubkey,
      {int limit = 50}) async* {
    final initial = await db.getProfileReactions(pubkey, limit: limit);
    if (initial.isNotEmpty) {
      yield await _resolveReactionNotes(initial);
    }

    yield* db
        .watchProfileReactions(pubkey, limit: limit)
        .asyncMap((events) async {
      return await _resolveReactionNotes(events);
    });
  }

  @override
  Future<List<FeedNote>> getProfileLikes(String pubkey,
      {int limit = 50}) async {
    final events = await db.getProfileReactions(pubkey, limit: limit);
    return await _resolveReactionNotes(events);
  }

  Future<List<FeedNote>> _resolveReactionNotes(
      List<Map<String, dynamic>> reactionEvents) async {
    if (reactionEvents.isEmpty) return [];

    final noteIds = <String>[];
    for (final event in reactionEvents) {
      final tags = event['tags'] as List<dynamic>? ?? [];
      for (final tag in tags) {
        if (tag is List && tag.isNotEmpty && tag[0] == 'e' && tag.length > 1) {
          final noteId = tag[1] as String;
          if (noteId.isNotEmpty) noteIds.add(noteId);
          break;
        }
      }
    }

    final seen = <String>{};
    final uniqueIds = <String>[];
    for (final id in noteIds) {
      if (seen.add(id)) uniqueIds.add(id);
    }

    final notes = <FeedNote>[];
    for (final noteId in uniqueIds) {
      final note = await getNote(noteId);
      if (note != null) {
        notes.add(note);
      }
    }

    return notes;
  }

  @override
  Stream<List<FeedNote>> watchHashtagFeed(String hashtag, {int limit = 100}) {
    return db
        .watchHydratedHashtagNotes(hashtag, limit: limit)
        .map((maps) => maps.map((m) => FeedNote.fromMap(m)).toList());
  }

  @override
  Future<FeedNote?> getNote(String noteId) async {
    final map = await db.getHydratedNote(noteId);
    if (map == null) return null;
    return FeedNote.fromMap(map);
  }

  @override
  Stream<FeedNote?> watchNote(String noteId) async* {
    final note = await getNote(noteId);
    yield note;
  }

  @override
  Future<Map<String, dynamic>?> getNoteRaw(String noteId) async {
    final map = await db.getHydratedNote(noteId);
    return map;
  }

  @override
  Future<List<Map<String, dynamic>>> getRepliesRaw(String noteId,
      {int limit = 100}) async {
    return await db.getHydratedReplies(noteId, limit: limit);
  }

  @override
  Future<List<FeedNote>> getReplies(String noteId, {int limit = 100}) async {
    final maps = await db.getHydratedReplies(noteId, limit: limit);
    return maps.map((m) => FeedNote.fromMap(m)).toList();
  }

  @override
  Stream<List<FeedNote>> watchReplies(String noteId, {int limit = 100}) {
    return db
        .watchHydratedReplies(noteId, limit: limit)
        .map((maps) => maps.map((m) => FeedNote.fromMap(m)).toList());
  }

  @override
  Future<void> saveNotes(List<Map<String, dynamic>> notes) async {
    await db.saveFeedNotes(notes);
  }

  @override
  Future<List<String>?> getFollowingList(String userPubkey) async {
    return await db.getFollowingList(userPubkey);
  }
}
