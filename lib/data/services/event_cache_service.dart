import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../models/event_model.dart';
import 'isar_database_service.dart';
import 'event_converter_service.dart';

class EventCacheService {
  static EventCacheService? _instance;
  static EventCacheService get instance =>
      _instance ??= EventCacheService._internal();

  EventCacheService._internal();

  final IsarDatabaseService _isarService = IsarDatabaseService.instance;
  final EventConverterService _eventConverter = EventConverterService.instance;

  Future<Isar> get _isar async => await _isarService.isar;

  Future<void> saveEvent(Map<String, dynamic> eventData,
      {String? relayUrl}) async {
    try {
      final eventId = eventData['id'] as String? ?? '';
      if (eventId.isEmpty) return;

      final db = await _isar;

      final eventModel =
          _eventConverter.eventDataToModel(eventData, relayUrl: relayUrl);

      await db.writeTxn(() async {
        final existing =
            await db.eventModels.where().eventIdEqualTo(eventId).findFirst();
        if (existing == null) {
          await db.eventModels.put(eventModel);
        }
      });
    } on IsarError catch (e) {
      if (!e.message.contains('Unique index violated')) {
        debugPrint('[EventCacheService] Error saving event: $e');
      }
    } catch (e) {
      debugPrint('[EventCacheService] Error saving event: $e');
    }
  }

  Future<void> saveEvents(List<Map<String, dynamic>> events,
      {String? relayUrl}) async {
    if (events.isEmpty) return;

    try {
      final db = await _isar;

      final eventsToSave = <EventModel>[];
      for (final eventData in events) {
        final eventId = eventData['id'] as String? ?? '';
        if (eventId.isEmpty) continue;

        try {
          final eventModel =
              _eventConverter.eventDataToModel(eventData, relayUrl: relayUrl);
          eventsToSave.add(eventModel);
        } catch (e) {
          debugPrint('[EventCacheService] Error creating event model: $e');
        }
      }

      if (eventsToSave.isEmpty) return;

      int savedCount = 0;
      await db.writeTxn(() async {
        final eventIds = eventsToSave.map((e) => e.eventId).toList();
        final existingEvents = await db.eventModels
            .where()
            .anyOf(eventIds, (q, String eventId) => q.eventIdEqualTo(eventId))
            .findAll();
        final existingIds = existingEvents.map((e) => e.eventId).toSet();

        for (final eventModel in eventsToSave) {
          if (!existingIds.contains(eventModel.eventId)) {
            await db.eventModels.put(eventModel);
            savedCount++;
          }
        }
      });

      if (savedCount > 0) {
        debugPrint('[EventCacheService] Saved $savedCount new events');
      }
    } on IsarError catch (e) {
      if (!e.message.contains('Unique index violated')) {
        debugPrint('[EventCacheService] Error batch saving events: $e');
      }
    } catch (e) {
      debugPrint('[EventCacheService] Error batch saving events: $e');
    }
  }

  Future<EventModel?> getEventById(String eventId) async {
    try {
      if (eventId.isEmpty) return null;

      final db = await _isar;
      return await db.eventModels.where().eventIdEqualTo(eventId).findFirst();
    } catch (e) {
      debugPrint('[EventCacheService] Error getting event by ID: $e');
      return null;
    }
  }

  Future<List<EventModel>> getEventsByKind(
    int kind, {
    DateTime? since,
    DateTime? until,
    int? limit,
  }) async {
    try {
      final db = await _isar;
      final baseQuery = db.eventModels.where().kindEqualToAnyCreatedAt(kind);

      List<EventModel> results;
      if (since != null || until != null) {
        final allResults = await baseQuery.sortByCreatedAtDesc().findAll();
        results = allResults.where((event) {
          if (since != null &&
              event.createdAt < since.millisecondsSinceEpoch ~/ 1000) {
            return false;
          }
          if (until != null &&
              event.createdAt > until.millisecondsSinceEpoch ~/ 1000) {
            return false;
          }
          return true;
        }).toList();
        if (limit != null && limit > 0) {
          return results.take(limit).toList();
        }
        return results;
      }

      final sortedQuery = baseQuery.sortByCreatedAtDesc();
      if (limit != null && limit > 0) {
        return await sortedQuery.limit(limit).findAll();
      }
      return await sortedQuery.findAll();
    } catch (e) {
      debugPrint('[EventCacheService] Error getting events by kind: $e');
      return [];
    }
  }

  Future<List<EventModel>> getEventsByAuthor(
    String pubkey, {
    int? kind,
    DateTime? since,
    DateTime? until,
    int? limit,
  }) async {
    try {
      if (pubkey.isEmpty) return [];

      final db = await _isar;
      final baseQuery =
          db.eventModels.where().pubkeyEqualToAnyKindCreatedAt(pubkey);

      List<EventModel> results;
      if (kind != null || since != null || until != null) {
        final allResults = await baseQuery.sortByCreatedAtDesc().findAll();
        results = allResults.where((event) {
          if (kind != null && event.kind != kind) return false;
          if (since != null &&
              event.createdAt < since.millisecondsSinceEpoch ~/ 1000) {
            return false;
          }
          if (until != null &&
              event.createdAt > until.millisecondsSinceEpoch ~/ 1000) {
            return false;
          }
          return true;
        }).toList();
        if (limit != null && limit > 0) {
          return results.take(limit).toList();
        }
        return results;
      }

      final sortedQuery = baseQuery.sortByCreatedAtDesc();
      if (limit != null && limit > 0) {
        return await sortedQuery.limit(limit).findAll();
      }
      return await sortedQuery.findAll();
    } catch (e) {
      debugPrint('[EventCacheService] Error getting events by author: $e');
      return [];
    }
  }

  Future<List<EventModel>> getEventsByTag(
    String tagType,
    String tagValue, {
    int? kind,
    DateTime? since,
    DateTime? until,
    int? limit,
  }) async {
    try {
      if (tagType.isEmpty || tagValue.isEmpty) return [];

      final db = await _isar;
      final allEvents = await db.eventModels.where().findAll();

      final matchingEvents = <EventModel>[];

      for (final event in allEvents) {
        if (kind != null && event.kind != kind) continue;

        if (since != null && event.createdAtDateTime.isBefore(since)) continue;
        if (until != null && event.createdAtDateTime.isAfter(until)) continue;

        final tagValues = event.getTagValues(tagType);
        if (tagValues.contains(tagValue)) {
          matchingEvents.add(event);
        }

        if (limit != null && limit > 0 && matchingEvents.length >= limit) break;
      }

      matchingEvents.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (limit != null && limit > 0) {
        return matchingEvents.take(limit).toList();
      }

      return matchingEvents;
    } catch (e) {
      debugPrint('[EventCacheService] Error getting events by tag: $e');
      return [];
    }
  }

  Future<List<EventModel>> getEventsByIds(List<String> eventIds) async {
    try {
      if (eventIds.isEmpty) return [];

      final db = await _isar;
      return await db.eventModels
          .where()
          .anyOf(eventIds, (q, String eventId) => q.eventIdEqualTo(eventId))
          .findAll();
    } catch (e) {
      debugPrint('[EventCacheService] Error getting events by IDs: $e');
      return [];
    }
  }

  Future<List<EventModel>> getProfileEventsByPubkeys(
      List<String> pubkeys) async {
    try {
      if (pubkeys.isEmpty) return [];

      final db = await _isar;
      final allProfiles = <EventModel>[];

      for (final pubkey in pubkeys) {
        if (pubkey.isEmpty) continue;
        final allResults = await db.eventModels
            .where()
            .pubkeyEqualToAnyKindCreatedAt(pubkey)
            .sortByCreatedAtDesc()
            .findAll();
        final profiles = allResults.where((event) => event.kind == 0).toList();
        if (profiles.isNotEmpty) {
          allProfiles.add(profiles.first);
        }
      }

      return allProfiles;
    } catch (e) {
      debugPrint(
          '[EventCacheService] Error getting profile events by pubkeys: $e');
      return [];
    }
  }

  Future<List<EventModel>> getInteractionEventsForNotes(
    List<String> noteIds, {
    List<int>? kinds,
    DateTime? since,
  }) async {
    try {
      if (noteIds.isEmpty) return [];

      final db = await _isar;
      final interactionKinds = kinds ?? [7, 6, 9735];
      final allEvents = await db.eventModels
          .where()
          .anyOf(interactionKinds,
              (q, int kind) => q.kindEqualToAnyCreatedAt(kind))
          .findAll();

      final matchingEvents = <EventModel>[];

      for (final event in allEvents) {
        if (since != null && event.createdAtDateTime.isBefore(since)) continue;

        final tagValues = event.getTagValues('e');
        final hasMatchingNoteId =
            noteIds.any((noteId) => tagValues.contains(noteId));

        if (hasMatchingNoteId) {
          matchingEvents.add(event);
        }
      }

      matchingEvents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return matchingEvents;
    } catch (e) {
      debugPrint(
          '[EventCacheService] Error getting interaction events for notes: $e');
      return [];
    }
  }

  Future<bool> hasEvent(String eventId) async {
    try {
      if (eventId.isEmpty) return false;

      final db = await _isar;
      final count =
          await db.eventModels.where().eventIdEqualTo(eventId).count();
      return count > 0;
    } catch (e) {
      debugPrint('[EventCacheService] Error checking event existence: $e');
      return false;
    }
  }

  Future<int> getEventCount({int? kind}) async {
    try {
      final db = await _isar;
      if (kind != null) {
        return await db.eventModels
            .where()
            .kindEqualToAnyCreatedAt(kind)
            .count();
      }
      return await db.eventModels.count();
    } catch (e) {
      debugPrint('[EventCacheService] Error getting event count: $e');
      return 0;
    }
  }

  Future<int> cleanupOldEvents(
      {Duration retentionPeriod = const Duration(days: 30)}) async {
    try {
      final db = await _isar;
      final cutoffDate = DateTime.now().subtract(retentionPeriod);

      final expiredEvents =
          await db.eventModels.filter().cachedAtLessThan(cutoffDate).findAll();

      if (expiredEvents.isEmpty) {
        return 0;
      }

      await db.writeTxn(() async {
        for (final event in expiredEvents) {
          await db.eventModels.delete(event.id);
        }
      });

      debugPrint(
          '[EventCacheService] Cleaned up ${expiredEvents.length} expired events');
      return expiredEvents.length;
    } catch (e) {
      debugPrint('[EventCacheService] Error cleaning up old events: $e');
      return 0;
    }
  }

  Future<void> deleteEvent(String eventId) async {
    try {
      if (eventId.isEmpty) return;

      final db = await _isar;
      await db.writeTxn(() async {
        await db.eventModels.deleteByEventId(eventId);
      });
    } catch (e) {
      debugPrint('[EventCacheService] Error deleting event: $e');
    }
  }

  Future<void> deleteEvents(List<String> eventIds) async {
    try {
      if (eventIds.isEmpty) return;

      final db = await _isar;
      await db.writeTxn(() async {
        for (final eventId in eventIds) {
          await db.eventModels.deleteByEventId(eventId);
        }
      });
    } catch (e) {
      debugPrint('[EventCacheService] Error deleting events: $e');
    }
  }

  Future<void> clearAllEvents() async {
    try {
      final db = await _isar;
      await db.writeTxn(() async {
        await db.eventModels.clear();
      });
      debugPrint('[EventCacheService] Cleared all events');
    } catch (e) {
      debugPrint('[EventCacheService] Error clearing events: $e');
    }
  }

  Stream<EventModel?> watchEvent(String eventId) async* {
    final db = await _isar;
    yield* db.eventModels
        .where()
        .eventIdEqualTo(eventId)
        .watch(fireImmediately: true)
        .map((events) => events.isEmpty ? null : events.first);
  }

  Stream<List<EventModel>> watchEventsByKind(int kind) async* {
    final db = await _isar;
    yield* db.eventModels
        .where()
        .kindEqualToAnyCreatedAt(kind)
        .sortByCreatedAtDesc()
        .watch(fireImmediately: true);
  }

  Future<List<EventModel>> getEventsByAuthorsAndKinds(
    List<String> authors,
    List<int> kinds, {
    int? limit,
    DateTime? since,
    DateTime? until,
  }) async {
    try {
      if (authors.isEmpty || kinds.isEmpty) return [];

      final db = await _isar;
      final allEvents = <EventModel>[];

      for (final author in authors) {
        if (author.isEmpty) continue;
        final events = await db.eventModels
            .where()
            .pubkeyEqualToAnyKindCreatedAt(author)
            .filter()
            .anyOf(kinds, (q, kind) => q.kindEqualTo(kind))
            .sortByCreatedAtDesc()
            .findAll();
        allEvents.addAll(events);
      }

      var results = allEvents.where((event) {
        if (since != null &&
            event.createdAt < since.millisecondsSinceEpoch ~/ 1000) {
          return false;
        }
        if (until != null &&
            event.createdAt > until.millisecondsSinceEpoch ~/ 1000) {
          return false;
        }
        return true;
      }).toList();

      results.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (limit != null && limit > 0 && results.length > limit) {
        return results.take(limit).toList();
      }

      return results;
    } catch (e) {
      debugPrint(
          '[EventCacheService] Error getting events by authors and kinds: $e');
      return [];
    }
  }

  Future<List<EventModel>> getEventsByPTags(
    List<String> pubkeys,
    List<int> kinds, {
    int? limit,
    DateTime? since,
  }) async {
    try {
      if (pubkeys.isEmpty || kinds.isEmpty) return [];

      final db = await _isar;
      final allEvents = await db.eventModels
          .where()
          .anyOf(kinds, (q, int kind) => q.kindEqualToAnyCreatedAt(kind))
          .findAll();

      final matchingEvents = <EventModel>[];

      for (final event in allEvents) {
        if (since != null && event.createdAtDateTime.isBefore(since)) continue;

        final pTagValues = event.getTagValues('p');
        final hasMatchingPubkey = pubkeys.any((pk) => pTagValues.contains(pk));

        if (hasMatchingPubkey) {
          matchingEvents.add(event);
        }
      }

      matchingEvents.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (limit != null && limit > 0 && matchingEvents.length > limit) {
        return matchingEvents.take(limit).toList();
      }

      return matchingEvents;
    } catch (e) {
      debugPrint('[EventCacheService] Error getting events by p-tags: $e');
      return [];
    }
  }

  Future<List<EventModel>> getEventsByETags(
    List<String> eventIds, {
    List<int>? kinds,
    int? limit,
    DateTime? since,
  }) async {
    try {
      if (eventIds.isEmpty) return [];

      final db = await _isar;
      List<EventModel> allEvents;

      if (kinds != null && kinds.isNotEmpty) {
        allEvents = await db.eventModels
            .where()
            .anyOf(kinds, (q, int kind) => q.kindEqualToAnyCreatedAt(kind))
            .findAll();
      } else {
        allEvents = await db.eventModels.where().findAll();
      }
      final matchingEvents = <EventModel>[];

      for (final event in allEvents) {
        if (since != null && event.createdAtDateTime.isBefore(since)) continue;

        final eTagValues = event.getTagValues('e');
        final hasMatchingEventId =
            eventIds.any((id) => eTagValues.contains(id));

        if (hasMatchingEventId) {
          matchingEvents.add(event);
        }
      }

      matchingEvents.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (limit != null && limit > 0 && matchingEvents.length > limit) {
        return matchingEvents.take(limit).toList();
      }

      return matchingEvents;
    } catch (e) {
      debugPrint('[EventCacheService] Error getting events by e-tags: $e');
      return [];
    }
  }

  Future<EventModel?> getLatestByAuthorAndKind(String author, int kind) async {
    try {
      if (author.isEmpty) return null;

      final db = await _isar;
      final events = await db.eventModels
          .where()
          .pubkeyKindEqualToAnyCreatedAt(author, kind)
          .sortByCreatedAtDesc()
          .limit(1)
          .findAll();

      return events.isNotEmpty ? events.first : null;
    } catch (e) {
      debugPrint(
          '[EventCacheService] Error getting latest event by author and kind: $e');
      return null;
    }
  }

  Future<List<EventModel>> getDMEvents(
    String userPubkey, {
    String? otherPubkey,
    int? limit,
    DateTime? since,
  }) async {
    try {
      if (userPubkey.isEmpty) return [];

      final db = await _isar;
      final allDMs =
          await db.eventModels.where().kindEqualToAnyCreatedAt(4).findAll();

      final matchingEvents = <EventModel>[];

      for (final event in allDMs) {
        if (since != null && event.createdAtDateTime.isBefore(since)) continue;

        final isFromUser = event.pubkey == userPubkey;
        final pTagValues = event.getTagValues('p');
        final isToUser = pTagValues.contains(userPubkey);

        if (!isFromUser && !isToUser) continue;

        if (otherPubkey != null) {
          final isFromOther = event.pubkey == otherPubkey;
          final isToOther = pTagValues.contains(otherPubkey);
          if (!isFromOther && !isToOther) continue;
        }

        matchingEvents.add(event);
      }

      matchingEvents.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (limit != null && limit > 0 && matchingEvents.length > limit) {
        return matchingEvents.take(limit).toList();
      }

      return matchingEvents;
    } catch (e) {
      debugPrint('[EventCacheService] Error getting DM events: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final db = await _isar;
      final totalEvents = await db.eventModels.count();
      final kind0Count =
          await db.eventModels.where().kindEqualToAnyCreatedAt(0).count();
      final kind1Count =
          await db.eventModels.where().kindEqualToAnyCreatedAt(1).count();
      final kind3Count =
          await db.eventModels.where().kindEqualToAnyCreatedAt(3).count();
      final dbSize = await db.getSize();

      return {
        'totalEvents': totalEvents,
        'kind0Count': kind0Count,
        'kind1Count': kind1Count,
        'kind3Count': kind3Count,
        'databaseSize': '${(dbSize / 1024 / 1024).toStringAsFixed(2)} MB',
        'databaseSizeBytes': dbSize,
      };
    } catch (e) {
      debugPrint('[EventCacheService] Error getting statistics: $e');
      return {
        'error': e.toString(),
      };
    }
  }

  Future<void> printStatistics() async {
    final stats = await getStatistics();
    debugPrint('\n=== Event Cache Statistics ===');
    stats.forEach((key, value) {
      debugPrint('  $key: $value');
    });
    debugPrint('===============================\n');
  }
}
