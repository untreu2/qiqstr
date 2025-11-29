import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:ndk/ndk.dart';
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
  
  final Map<String, NoteCountModelIsar> _memoryCache = {};
  
  Timer? _batchFetchTimer;
  final List<String> _batchQueue = [];
  static const Duration _batchDelay = Duration(milliseconds: 300);
  static const int _maxBatchSize = 20;

  Future<NoteCountModelIsar?> getCounts(String noteId) async {
    try {
      final cached = _getFromMemoryCache(noteId);
      if (cached != null) {
        return cached;
      }

      final db = await IsarDatabaseService.instance.isar;
      final counts = await db.noteCountModelIsars.getByNoteId(noteId);

      if (counts != null) {
        _addToMemoryCache(noteId, counts);
        return counts;
      }

      if (_pendingFetches.containsKey(noteId)) {
        try {
          return await _pendingFetches[noteId]!.future.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              return null;
            },
          );
        } catch (e) {
          return null;
        }
      }

      _addToBatchQueue(noteId);
      
      final completer = Completer<NoteCountModelIsar?>();
      _pendingFetches[noteId] = completer;

      unawaited(_processBatchQueue().then((_) {
        if (_pendingFetches.containsKey(noteId)) {
          final result = _memoryCache[noteId];
          if (!completer.isCompleted) {
            completer.complete(result);
          }
          _pendingFetches.remove(noteId);
        }
      }).catchError((e) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
        _pendingFetches.remove(noteId);
      }));

      try {
        return await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
            _pendingFetches.remove(noteId);
            return null;
          },
        );
      } catch (e) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
        _pendingFetches.remove(noteId);
        return null;
      }
    } catch (e) {
      return null;
    }
  }
  
  NoteCountModelIsar? _getFromMemoryCache(String noteId) {
    return _memoryCache[noteId];
  }
  
  void _addToMemoryCache(String noteId, NoteCountModelIsar counts) {
    _memoryCache[noteId] = counts;
  }
  
  void _addToBatchQueue(String noteId) {
    if (!_batchQueue.contains(noteId)) {
      _batchQueue.add(noteId);
    }
    
    _batchFetchTimer?.cancel();
    _batchFetchTimer = Timer(_batchDelay, () {
      unawaited(_processBatchQueue());
    });
  }
  
  Future<void> _processBatchQueue() async {
    if (_batchQueue.isEmpty) return;
    
    final toProcess = _batchQueue.take(_maxBatchSize).toList();
    _batchQueue.removeRange(0, toProcess.length);
    
    final uncached = <String>[];
    final db = await IsarDatabaseService.instance.isar;
    
    for (final noteId in toProcess) {
      if (_getFromMemoryCache(noteId) == null) {
        final cached = await db.noteCountModelIsars.getByNoteId(noteId);
        if (cached != null) {
          _addToMemoryCache(noteId, cached);
        } else {
          uncached.add(noteId);
        }
      }
    }
    
    if (uncached.isNotEmpty) {
      await _batchFetchFromRelays(uncached);
    }
  }
  
  Future<void> _batchFetchFromRelays(List<String> noteIds) async {
    if (noteIds.isEmpty) return;
    
    final now = DateTime.now();
    final toFetch = <String>[];
    
    for (final noteId in noteIds) {
      if (_fetchingNotes.contains(noteId)) continue;
      
      final lastFetch = _lastFetchTime[noteId];
      if (lastFetch == null || now.difference(lastFetch) >= _fetchCooldown) {
        toFetch.add(noteId);
        _fetchingNotes.add(noteId);
        _lastFetchTime[noteId] = now;
      }
    }
    
    if (toFetch.isEmpty) return;
    
    try {
      final relayUrls = await getRelaySetMainSockets();
      if (relayUrls.isEmpty) {
        toFetch.forEach(_fetchingNotes.remove);
        return;
      }

      final filter = Filter(
        kinds: [1, 6, 7, 9735],
        eTags: toFetch,
      );

      final serializedRequest = NostrService.createRequest(filter);
      final requestJson = jsonDecode(serializedRequest) as List;
      final subscriptionId = requestJson[1] as String;

      final Map<String, Map<String, Map<String, dynamic>>> noteEvents = {};
      for (final noteId in toFetch) {
        noteEvents[noteId] = {};
      }

      await RelayQueryHelper.queryRelaysParallel<Map<String, dynamic>>(
        relayUrls: relayUrls,
        request: serializedRequest,
        subscriptionId: subscriptionId,
        eventProcessor: (eventData, relayUrl) {
          final eventId = eventData['id'] as String? ?? '';
          if (eventId.isEmpty) return null;
          
          final tags = eventData['tags'] as List<dynamic>? ?? [];
          for (final tag in tags) {
            if (tag is List && tag.length >= 2 && tag[0] == 'e') {
              final targetNoteId = tag[1] as String? ?? '';
              if (targetNoteId.isNotEmpty && noteEvents.containsKey(targetNoteId)) {
                if (!noteEvents[targetNoteId]!.containsKey(eventId)) {
                  noteEvents[targetNoteId]![eventId] = eventData;
                }
                return eventData;
              }
            }
          }
          return null;
        },
        timeout: const Duration(seconds: 4),
        connectTimeout: const Duration(seconds: 3),
        debugPrefix: 'COUNTER-BATCH',
      );

      final db = await IsarDatabaseService.instance.isar;
      await db.writeTxn(() async {
        for (final noteId in toFetch) {
          final events = noteEvents[noteId] ?? {};
          
          int reactionCount = 0;
          int replyCount = 0;
          int repostCount = 0;
          int zapAmount = 0;

          for (final event in events.values) {
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

          await db.noteCountModelIsars.put(counts);
          _addToMemoryCache(noteId, counts);
          
          final completer = _pendingFetches[noteId];
          if (completer != null && !completer.isCompleted) {
            completer.complete(counts);
            _pendingFetches.remove(noteId);
          }
        }
      });
    } catch (e) {
      debugPrint('[NoteCounterService] Error batch fetching: $e');
    } finally {
      toFetch.forEach(_fetchingNotes.remove);
    }
  }

  Future<NoteCountModelIsar?> fetchAndStoreCounts(String noteId) async {
    final cached = _getFromMemoryCache(noteId);
    if (cached != null) {
      return cached;
    }
    
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
      final counts = await db.noteCountModelIsars.getByNoteId(noteId);
      if (counts != null) {
        _addToMemoryCache(noteId, counts);
      }
      return counts;
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
        eTags: [noteId],
      );

      final serializedRequest = NostrService.createRequest(filter);
      final requestJson = jsonDecode(serializedRequest) as List;
      final subscriptionId = requestJson[1] as String;

      final Map<String, Map<String, dynamic>> uniqueEvents = {};

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

      _addToMemoryCache(noteId, counts);
      return counts;
    } catch (e) {
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
      _memoryCache.remove(noteId);
      _lastFetchTime.remove(noteId);
      _fetchingNotes.remove(noteId);
      _pendingFetches.remove(noteId);
      _batchQueue.remove(noteId);
    } catch (e) {
      debugPrint('[NoteCounterService] Error invalidating counts: $e');
    }
  }

  Future<void> batchFetchCounts(List<String> noteIds) async {
    if (noteIds.isEmpty) return;
    
    final uncached = <String>[];
    final db = await IsarDatabaseService.instance.isar;
    
    for (final noteId in noteIds) {
      final cached = _getFromMemoryCache(noteId);
      if (cached == null) {
        final dbCached = await db.noteCountModelIsars.getByNoteId(noteId);
        if (dbCached != null) {
          _addToMemoryCache(noteId, dbCached);
        } else {
          uncached.add(noteId);
        }
      }
    }
    
    if (uncached.isNotEmpty) {
      await _batchFetchFromRelays(uncached);
    }
  }
  
  void clearMemoryCache() {
    _memoryCache.clear();
  }
}

