import 'dart:async';
import '../../domain/entities/feed_note.dart';
import '../../models/event_model.dart';
import 'base_repository.dart';

abstract class FeedRepository {
  Stream<List<FeedNote>> watchFeed(String userPubkey, {int limit = 100});
  Future<List<FeedNote>> getFeed(String userPubkey, {int limit = 100});
  Stream<List<FeedNote>> watchProfileNotes(String pubkey, {int limit = 50});
  Future<List<FeedNote>> getProfileNotes(String pubkey, {int limit = 50});
  Stream<List<FeedNote>> watchHashtagFeed(String hashtag, {int limit = 100});
  Future<FeedNote?> getNote(String noteId);
  Stream<FeedNote?> watchNote(String noteId);
  Future<List<FeedNote>> getReplies(String noteId, {int limit = 100});
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
    final follows = await db.getFollowingList(userPubkey);
    if (follows == null || follows.isEmpty) {
      yield [];
      return;
    }

    yield* db.watchFeedNotes(follows, limit: limit).asyncMap((events) async {
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
  Stream<List<FeedNote>> watchProfileNotes(String pubkey, {int limit = 50}) {
    return db.watchProfileNotes(pubkey, limit: limit).asyncMap((events) async {
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
    return db.watchHashtagNotes(hashtag, limit: limit).asyncMap((events) async {
      return await _hydrateNotes(events);
    });
  }

  @override
  Future<FeedNote?> getNote(String noteId) async {
    final event = await db.getEventModel(noteId);
    if (event == null) return null;

    final results = await Future.wait([
      db.getUserProfile(event.pubkey),
      db.getInteractionCounts(noteId),
    ]);
    final profile = results[0] as Map<String, String>?;
    final counts = results[1] as Map<String, int>;

    return mapper.toFeedNote(
      event,
      authorName: profile?['name'] ?? profile?['display_name'],
      authorImage: profile?['profileImage'],
      authorNip05: profile?['nip05'],
      reactionCount: counts['reactions'] ?? 0,
      repostCount: counts['reposts'] ?? 0,
      replyCount: counts['replies'] ?? 0,
      zapCount: counts['zaps'] ?? 0,
    );
  }

  @override
  Stream<FeedNote?> watchNote(String noteId) async* {
    final db = this.db;

    EventModel? currentEvent = await db.getEventModel(noteId);
    if (currentEvent == null) {
      yield null;
      return;
    }

    final results = await Future.wait([
      db.getUserProfile(currentEvent.pubkey),
      db.getInteractionCounts(noteId),
    ]);
    final profile = results[0] as Map<String, String>?;
    final counts = results[1] as Map<String, int>;

    yield mapper.toFeedNote(
      currentEvent,
      authorName: profile?['name'] ?? profile?['display_name'],
      authorImage: profile?['profileImage'],
      authorNip05: profile?['nip05'],
      reactionCount: counts['reactions'] ?? 0,
      repostCount: counts['reposts'] ?? 0,
      replyCount: counts['replies'] ?? 0,
      zapCount: counts['zaps'] ?? 0,
    );
  }

  @override
  Future<List<FeedNote>> getReplies(String noteId, {int limit = 100}) async {
    final events = await db.getReplies(noteId, limit: limit);
    return await _hydrateNotes(events);
  }

  @override
  Stream<List<FeedNote>> watchReplies(String noteId, {int limit = 100}) {
    return db.watchReplies(noteId, limit: limit).asyncMap((events) async {
      return await _hydrateNotes(events);
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

  Future<List<FeedNote>> _hydrateNotes(List<EventModel> events) async {
    if (events.isEmpty) return [];

    final pubkeys = <String>{};
    final noteIdMap = <String, String>{};

    for (final event in events) {
      pubkeys.add(event.pubkey);
      if (event.kind == 6) {
        final originalId = _extractOriginalNoteId(event);
        if (originalId != null) {
          noteIdMap[event.eventId] = originalId;
          final originalAuthor = _extractOriginalAuthor(event);
          if (originalAuthor != null) {
            pubkeys.add(originalAuthor);
          }
        } else {
          noteIdMap[event.eventId] = event.eventId;
        }
      } else {
        noteIdMap[event.eventId] = event.eventId;
      }
    }

    final originalNoteIds = noteIdMap.values.toSet().toList();
    final results = await Future.wait([
      db.getUserProfiles(pubkeys.toList()),
      db.getCachedInteractionCounts(originalNoteIds),
    ]);
    final profiles = results[0] as Map<String, Map<String, String>>;
    final counts = results[1] as Map<String, Map<String, int>>;

    return events.map((event) {
      final originalNoteId = noteIdMap[event.eventId] ?? event.eventId;
      final originalAuthor = event.kind == 6
          ? _extractOriginalAuthor(event) ?? event.pubkey
          : event.pubkey;
      final profile = profiles[originalAuthor];
      final noteCounts = counts[originalNoteId] ?? {};

      return mapper.toFeedNote(
        event,
        authorName: profile?['name'] ?? profile?['display_name'],
        authorImage: profile?['profileImage'],
        authorNip05: profile?['nip05'],
        reactionCount: noteCounts['reactions'] ?? 0,
        repostCount: noteCounts['reposts'] ?? 0,
        replyCount: noteCounts['replies'] ?? 0,
        zapCount: noteCounts['zaps'] ?? 0,
      );
    }).toList();
  }

  String? _extractOriginalNoteId(EventModel event) {
    final tags = event.getTags();
    for (final tag in tags) {
      if (tag.isNotEmpty && tag[0] == 'e' && tag.length > 1) {
        return tag[1];
      }
    }
    return null;
  }

  String? _extractOriginalAuthor(EventModel event) {
    final tags = event.getTags();
    for (final tag in tags) {
      if (tag.isNotEmpty && tag[0] == 'p' && tag.length > 1) {
        return tag[1];
      }
    }
    return null;
  }
}
