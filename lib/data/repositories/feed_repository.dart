import 'dart:async';
import '../../domain/entities/feed_note.dart';
import 'base_repository.dart';

abstract class FeedRepository {
  Stream<List<FeedNote>> watchFeed(String userPubkey, {int limit = 100});
  Future<List<FeedNote>> getFeed(String userPubkey, {int limit = 100});
  Stream<List<FeedNote>> watchProfileNotes(String pubkey, {int limit = 50});
  Future<List<FeedNote>> getProfileNotes(String pubkey, {int limit = 50});
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

    final initial = await db.getCachedFeedNotes(activeFollows, limit: limit);
    if (initial.isNotEmpty) {
      yield await _hydrateNotes(initial);
    }

    yield* db
        .watchFeedNotes(activeFollows, limit: limit)
        .asyncMap((events) async {
      return await _hydrateNotes(events);
    });
  }

  @override
  Future<List<FeedNote>> getFeed(String userPubkey, {int limit = 100}) async {
    final follows = await db.getFollowingList(userPubkey);
    if (follows == null || follows.isEmpty) {
      return [];
    }

    final events = await db.getCachedFeedNotes(follows, limit: limit);
    return await _hydrateNotes(events);
  }

  @override
  Stream<List<FeedNote>> watchProfileNotes(String pubkey,
      {int limit = 50}) async* {
    final initial = await db.getCachedProfileNotes(pubkey, limit: limit);
    if (initial.isNotEmpty) {
      yield await _hydrateNotes(initial);
    }

    yield* db.watchProfileNotes(pubkey, limit: limit).asyncMap((events) async {
      return await _hydrateNotes(events);
    });
  }

  @override
  Future<List<FeedNote>> getProfileNotes(String pubkey,
      {int limit = 50}) async {
    final events = await db.getCachedProfileNotes(pubkey, limit: limit);
    return await _hydrateNotes(events);
  }

  @override
  Stream<List<FeedNote>> watchHashtagFeed(String hashtag, {int limit = 100}) {
    return db
        .watchHashtagNotes(hashtag, limit: limit)
        .asyncMap((events) async {
      return await _hydrateNotes(events);
    });
  }

  @override
  Future<FeedNote?> getNote(String noteId) async {
    final event = await db.getEventModel(noteId);
    if (event == null) return null;

    final pubkey = event['pubkey'] as String? ?? '';
    final results = await Future.wait([
      db.getUserProfile(pubkey),
      db.getInteractionCounts(noteId),
    ]);
    final profile = results[0] as Map<String, String>?;
    final counts = results[1] as Map<String, int>;

    return mapper.toFeedNote(
      event,
      authorName: profile?['name'] ?? profile?['display_name'],
      authorImage: profile?['picture'],
      authorNip05: profile?['nip05'],
      reactionCount: counts['reactions'] ?? 0,
      repostCount: counts['reposts'] ?? 0,
      replyCount: counts['replies'] ?? 0,
      zapCount: counts['zaps'] ?? 0,
    );
  }

  @override
  Stream<FeedNote?> watchNote(String noteId) async* {
    final event = await db.getEventModel(noteId);
    if (event == null) {
      yield null;
      return;
    }

    final pubkey = event['pubkey'] as String? ?? '';
    final results = await Future.wait([
      db.getUserProfile(pubkey),
      db.getInteractionCounts(noteId),
    ]);
    final profile = results[0] as Map<String, String>?;
    final counts = results[1] as Map<String, int>;

    yield mapper.toFeedNote(
      event,
      authorName: profile?['name'] ?? profile?['display_name'],
      authorImage: profile?['picture'],
      authorNip05: profile?['nip05'],
      reactionCount: counts['reactions'] ?? 0,
      repostCount: counts['reposts'] ?? 0,
      replyCount: counts['replies'] ?? 0,
      zapCount: counts['zaps'] ?? 0,
    );
  }

  @override
  Future<Map<String, dynamic>?> getNoteRaw(String noteId) async {
    final event = await db.getEventModel(noteId);
    if (event == null) return null;
    return mapper.toFeedNote(event).toMap();
  }

  @override
  Future<List<Map<String, dynamic>>> getRepliesRaw(String noteId,
      {int limit = 100}) async {
    final events = await db.getReplies(noteId, limit: limit);
    if (events.isEmpty) return [];
    return events.map((e) => mapper.toFeedNote(e).toMap()).toList();
  }

  @override
  Future<List<FeedNote>> getReplies(String noteId, {int limit = 100}) async {
    final events = await db.getReplies(noteId, limit: limit);
    return await _hydrateNotes(events, filterReplies: false);
  }

  @override
  Stream<List<FeedNote>> watchReplies(String noteId, {int limit = 100}) {
    return db.watchReplies(noteId, limit: limit).asyncMap((events) async {
      return await _hydrateNotes(events, filterReplies: false);
    });
  }

  @override
  Future<void> saveNotes(List<Map<String, dynamic>> notes) async {
    await db.saveFeedNotes(notes);
  }

  @override
  Future<List<String>?> getFollowingList(String userPubkey) async {
    return await db.getFollowingList(userPubkey);
  }

  Future<List<FeedNote>> _hydrateNotes(
      List<Map<String, dynamic>> events, {bool filterReplies = true}) async {
    if (events.isEmpty) return [];

    final pubkeys = <String>{};
    final noteIds = <String>[];

    for (final event in events) {
      final pubkey = event['pubkey'] as String? ?? '';
      final kind = event['kind'] as int? ?? 1;
      final eventId = event['id'] as String? ?? '';
      pubkeys.add(pubkey);
      if (eventId.isNotEmpty) noteIds.add(eventId);

      if (kind == 6) {
        final originalAuthor = _extractOriginalAuthor(event);
        if (originalAuthor != null) {
          pubkeys.add(originalAuthor);
        }
      }
    }

    final profilesFuture = db.getUserProfiles(pubkeys.toList());
    final countsFuture = noteIds.isNotEmpty
        ? db.getCachedInteractionCounts(noteIds)
        : Future.value(<String, Map<String, int>>{});

    late final Map<String, Map<String, String>> profiles;
    late final Map<String, Map<String, int>> interactionCounts;
    await Future.wait([
      profilesFuture.then((v) => profiles = v),
      countsFuture.then((v) => interactionCounts = v),
    ]);

    final notes = <FeedNote>[];
    for (final event in events) {
      final kind = event['kind'] as int? ?? 1;
      final eventId = event['id'] as String? ?? '';
      final originalAuthor = kind == 6
          ? _extractOriginalAuthor(event) ?? (event['pubkey'] as String? ?? '')
          : (event['pubkey'] as String? ?? '');
      final profile = profiles[originalAuthor];
      final counts = interactionCounts[eventId];

      final note = mapper.toFeedNote(
        event,
        authorName: profile?['name'] ?? profile?['display_name'],
        authorImage: profile?['picture'],
        authorNip05: profile?['nip05'],
        reactionCount: counts?['reactions'] ?? 0,
        repostCount: counts?['reposts'] ?? 0,
        replyCount: counts?['replies'] ?? 0,
        zapCount: counts?['zaps'] ?? 0,
      );

      if (filterReplies && note.isReply && !note.isRepost) continue;
      notes.add(note);
    }
    return notes;
  }

  String? _extractOriginalAuthor(Map<String, dynamic> event) {
    final tags = event['tags'] as List<dynamic>? ?? [];
    for (final tag in tags) {
      if (tag is List && tag.isNotEmpty && tag[0] == 'p' && tag.length > 1) {
        return tag[1] as String?;
      }
    }
    return null;
  }
}
