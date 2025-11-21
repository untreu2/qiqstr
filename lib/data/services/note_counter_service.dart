import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:nostr/nostr.dart';
import '../../models/note_count_model_isar.dart';
import '../../services/nostr_service.dart';
import '../../constants/relays.dart';
import 'isar_database_service.dart';
import 'relay_query_helper.dart';

class NoteCounterService {
  static NoteCounterService? _instance;
  static NoteCounterService get instance => _instance ??= NoteCounterService._internal();

  NoteCounterService._internal();

  final Map<String, DateTime> _lastFetchTime = {};
  final Duration _fetchCooldown = const Duration(seconds: 10);
  final Set<String> _fetchingNotes = {};
  final Map<String, Completer<NoteCountModelIsar?>> _pendingFetches = {};

  Future<NoteCountModelIsar?> getCounts(String noteId) async {
    try {
      final db = await IsarDatabaseService.instance.isar;
      final counts = await db.noteCountModelIsars.getByNoteId(noteId);

      if (counts != null) {
        return counts;
      }

      if (_pendingFetches.containsKey(noteId)) {
        try {
          return await _pendingFetches[noteId]!.future.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('[NoteCounterService] Timeout waiting for counts: $noteId');
              return null;
            },
          );
        } catch (e) {
          debugPrint('[NoteCounterService] Error waiting for pending fetch: $e');
          return null;
        }
      }

      final completer = Completer<NoteCountModelIsar?>();
      _pendingFetches[noteId] = completer;

      unawaited(fetchAndStoreCounts(noteId).then((result) {
        if (!completer.isCompleted) {
          completer.complete(result);
        }
        _pendingFetches.remove(noteId);
      }).catchError((e) {
        debugPrint('[NoteCounterService] Error in fetch promise: $e');
        if (!completer.isCompleted) {
          completer.complete(null);
        }
        _pendingFetches.remove(noteId);
      }));

      try {
        return await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('[NoteCounterService] Timeout fetching counts: $noteId');
            if (!completer.isCompleted) {
              completer.complete(null);
            }
            _pendingFetches.remove(noteId);
            return null;
          },
        );
      } catch (e) {
        debugPrint('[NoteCounterService] Error in getCounts future: $e');
        if (!completer.isCompleted) {
          completer.complete(null);
        }
        _pendingFetches.remove(noteId);
        return null;
      }
    } catch (e) {
      debugPrint('[NoteCounterService] Error getting counts: $e');
      return null;
    }
  }

  Future<NoteCountModelIsar?> fetchAndStoreCounts(String noteId) async {
    if (_fetchingNotes.contains(noteId)) {
      final completer = _pendingFetches[noteId];
      if (completer != null) {
        return await completer.future;
      }
      return null;
    }

    final now = DateTime.now();
    final lastFetch = _lastFetchTime[noteId];
    if (lastFetch != null && now.difference(lastFetch) < _fetchCooldown) {
      final db = await IsarDatabaseService.instance.isar;
      return await db.noteCountModelIsars.getByNoteId(noteId);
    }

    _fetchingNotes.add(noteId);
    _lastFetchTime[noteId] = now;

    try {
      final relayUrls = await getRelaySetMainSockets();
      if (relayUrls.isEmpty) {
        return null;
      }

      final filter = Filter(
        kinds: [1, 6, 7, 9735],
        e: [noteId],
      );

      final request = NostrService.createRequest(filter);
      final subscriptionId = request.subscriptionId;
      final serializedRequest = NostrService.serializeRequest(request);

      final Map<String, Map<String, dynamic>> uniqueEvents = {};

      try {
        await RelayQueryHelper.queryRelaysParallel<Map<String, dynamic>>(
          relayUrls: relayUrls,
          request: serializedRequest,
          subscriptionId: subscriptionId,
          eventProcessor: (eventData, relayUrl) {
            final eventId = eventData['id'] as String? ?? '';
            if (eventId.isNotEmpty && !uniqueEvents.containsKey(eventId)) {
              uniqueEvents[eventId] = eventData;
              return eventData;
            }
            return null;
          },
          timeout: const Duration(seconds: 4),
          connectTimeout: const Duration(seconds: 3),
          debugPrefix: 'COUNTER',
        );
      } catch (e) {
        debugPrint('[NoteCounterService] Error querying relays for $noteId: $e');
      }

      int reactionCount = 0;
      int replyCount = 0;
      int repostCount = 0;
      int zapAmount = 0;

      for (final event in uniqueEvents.values) {
        final kind = event['kind'] as int? ?? 0;
        switch (kind) {
          case 7:
            reactionCount++;
            break;
          case 1:
            replyCount++;
            break;
          case 6:
            repostCount++;
            break;
          case 9735:
            zapAmount += _extractZapAmount(event);
            break;
        }
      }

      final counts = NoteCountModelIsar.create(
        noteId: noteId,
        reactionCount: reactionCount,
        replyCount: replyCount,
        repostCount: repostCount,
        zapAmount: zapAmount,
      );

      final db = await IsarDatabaseService.instance.isar;
      await db.writeTxn(() async {
        await db.noteCountModelIsars.put(counts);
      });

      return counts;
    } catch (e) {
      debugPrint('[NoteCounterService] Error fetching counts for $noteId: $e');
      return null;
    } finally {
      _fetchingNotes.remove(noteId);
    }
  }


  int _extractZapAmount(Map<String, dynamic> zapEvent) {
    try {
      final tags = zapEvent['tags'] as List<dynamic>?;
      if (tags == null) return 0;

      for (final tag in tags) {
        if (tag is List && tag.length >= 2) {
          if (tag[0] == 'bolt11') {
            final bolt11 = tag[1] as String? ?? '';
            return _parseBolt11Amount(bolt11);
          }
        }
      }

      final content = zapEvent['content'] as String? ?? '';
      if (content.isNotEmpty) {
        try {
          final zapRequest = jsonDecode(content) as Map<String, dynamic>?;
          if (zapRequest != null) {
            final amountStr = zapRequest['amount']?.toString() ?? '';
            if (amountStr.isNotEmpty) {
              return int.tryParse(amountStr) ?? 0;
            }
          }
        } catch (_) {}
      }

      return 0;
    } catch (e) {
      debugPrint('[NoteCounterService] Error extracting zap amount: $e');
      return 0;
    }
  }

  int _parseBolt11Amount(String bolt11) {
    if (bolt11.isEmpty) return 0;

    final regex = RegExp(r'^lnbc(\d+)([munp]?)');
    final match = regex.firstMatch(bolt11);
    if (match == null) return 0;

    final numberStr = match.group(1);
    if (numberStr == null) return 0;

    final number = int.tryParse(numberStr) ?? 0;
    final unit = match.group(2)?.toLowerCase() ?? '';

    switch (unit) {
      case 'm':
        return number * 100000;
      case 'u':
        return number * 100;
      case 'n':
        return (number * 0.1).round();
      case 'p':
        return (number * 0.001).round();
      default:
        return number * 1000;
    }
  }

  Future<void> invalidateCounts(String noteId) async {
    try {
      final db = await IsarDatabaseService.instance.isar;
      await db.writeTxn(() async {
        await db.noteCountModelIsars.deleteByNoteId(noteId);
      });
      _lastFetchTime.remove(noteId);
      _fetchingNotes.remove(noteId);
    } catch (e) {
      debugPrint('[NoteCounterService] Error invalidating counts: $e');
    }
  }

  Future<void> batchFetchCounts(List<String> noteIds) async {
    final futures = noteIds.map((noteId) => fetchAndStoreCounts(noteId));
    await Future.wait(futures, eagerError: false);
  }
}

