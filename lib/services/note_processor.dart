import 'dart:async';
import 'dart:convert';
import 'dart:collection';

import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/services/data_service.dart';

class NoteProcessorMetrics {
  int notesProcessed = 0;
  int notesSkipped = 0;
  int repostsProcessed = 0;
  int repliesProcessed = 0;
  int profilesFetched = 0;
  final Map<String, int> skipReasons = {};

  void recordSkip(String reason) {
    notesSkipped++;
    skipReasons[reason] = (skipReasons[reason] ?? 0) + 1;
  }

  Map<String, dynamic> getStats() {
    return {
      'notesProcessed': notesProcessed,
      'notesSkipped': notesSkipped,
      'repostsProcessed': repostsProcessed,
      'repliesProcessed': repliesProcessed,
      'profilesFetched': profilesFetched,
      'skipReasons': Map<String, int>.from(skipReasons),
    };
  }
}

class NoteProcessor {
  static final NoteProcessorMetrics _metrics = NoteProcessorMetrics();
  static final Queue<Map<String, dynamic>> _processingQueue = Queue();
  static bool _isProcessing = false;

  // Cache for recently processed events to avoid duplicates
  static final Set<String> _recentlyProcessed = {};
  static Timer? _cleanupTimer;

  static void _startCleanupTimer() {
    _cleanupTimer ??= Timer.periodic(const Duration(minutes: 5), (_) {
      if (_recentlyProcessed.length > 1000) {
        _recentlyProcessed.clear();
      }
    });
  }

  static NoteProcessorMetrics get metrics => _metrics;

  static Future<void> processNoteEvent(
    DataService dataService,
    Map<String, dynamic> eventData,
    List<String> targetNpubs, {
    String? rawWs,
  }) async {
    _startCleanupTimer();

    final eventId = eventData['id'] as String?;
    if (eventId != null && _recentlyProcessed.contains(eventId)) {
      _metrics.recordSkip('already_processed');
      return;
    }

    // Add to processing queue for batch processing
    _processingQueue.add({
      'eventData': eventData,
      'targetNpubs': targetNpubs,
      'rawWs': rawWs,
      'dataService': dataService,
    });

    if (!_isProcessing) {
      _processQueue();
    }
  }

  static void _processQueue() async {
    if (_isProcessing || _processingQueue.isEmpty) return;

    _isProcessing = true;
    final stopwatch = Stopwatch()..start();

    try {
      final batch = <Map<String, dynamic>>[];
      while (_processingQueue.isNotEmpty && batch.length < 5) {
        batch.add(_processingQueue.removeFirst());
      }

      await Future.wait(batch.map((item) => _processNoteEventInternal(
            item['dataService'] as DataService,
            item['eventData'] as Map<String, dynamic>,
            List<String>.from(item['targetNpubs']),
            rawWs: item['rawWs'] as String?,
          )));

      print('[NoteProcessor] Processed batch of ${batch.length} events in ${stopwatch.elapsedMilliseconds}ms');
    } finally {
      _isProcessing = false;

      // Continue processing if there are more items
      if (_processingQueue.isNotEmpty) {
        Future.microtask(_processQueue);
      }
    }
  }

  static Future<void> _processNoteEventInternal(
    DataService dataService,
    Map<String, dynamic> eventData,
    List<String> targetNpubs, {
    String? rawWs,
  }) async {
    final processingStopwatch = Stopwatch()..start();

    try {
      int kind = eventData['kind'] as int;
      final String outerEventAuthor = eventData['pubkey'] as String;
      bool isOuterEventRepost = kind == 6;
      Map<String, dynamic>? innerEventData;
      DateTime? repostTimestamp;
      String? repostedEventJsonString;

      if (isOuterEventRepost) {
        _metrics.repostsProcessed++;
        repostTimestamp = DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000);
        repostedEventJsonString = eventData['content'] as String?;

        if (repostedEventJsonString != null && repostedEventJsonString.isNotEmpty) {
          try {
            innerEventData = jsonDecode(repostedEventJsonString) as Map<String, dynamic>;
          } catch (e) {
            print('[NoteProcessor] Error decoding repost content: $e');
            _metrics.recordSkip('repost_decode_error');
            return;
          }
        }

        if (innerEventData == null) {
          innerEventData = await _fetchOriginalEventData(dataService, eventData);
          if (innerEventData == null) {
            _metrics.recordSkip('repost_original_not_found');
            return;
          }
        }

        eventData = innerEventData;
        kind = eventData['kind'] as int? ?? 1;
      }

      final eventId = eventData['id'] as String?;
      if (eventId == null) {
        _metrics.recordSkip('missing_event_id');
        return;
      }

      // Mark as recently processed
      _recentlyProcessed.add(eventId);

      final String noteAuthor = eventData['pubkey'] as String;
      final noteContentRaw = eventData['content'];
      String noteContent = noteContentRaw is String ? noteContentRaw : jsonEncode(noteContentRaw);
      final tags = eventData['tags'] as List<dynamic>? ?? [];

      if (dataService.eventIds.contains(eventId)) {
        _metrics.recordSkip('already_exists');
        return;
      }

      if (noteContent.trim().isEmpty) {
        _metrics.recordSkip('empty_content');
        return;
      }

      // Optimized target validation
      if (!_isValidTarget(dataService, targetNpubs, outerEventAuthor, noteAuthor, isOuterEventRepost)) {
        _metrics.recordSkip('invalid_target');
        return;
      }

      final timestamp = DateTime.fromMillisecondsSinceEpoch((eventData['created_at'] as int) * 1000);

      // Optimized tag parsing
      final tagInfo = _parseReplyTags(tags);
      final bool isActualReply = tagInfo['isReply'] as bool;
      final String? rootId = tagInfo['rootId'] as String?;
      final String? parentId = tagInfo['parentId'] as String?;

      if (isActualReply) {
        _metrics.repliesProcessed++;
      }

      final newNote = NoteModel(
        id: eventId,
        content: noteContent,
        author: noteAuthor,
        timestamp: timestamp,
        isRepost: isOuterEventRepost,
        repostedBy: isOuterEventRepost ? outerEventAuthor : null,
        repostTimestamp: isOuterEventRepost ? repostTimestamp : null,
        rawWs: isOuterEventRepost ? repostedEventJsonString : rawWs,
        isReply: isActualReply,
        rootId: rootId,
        parentId: parentId,
      );

      dataService.parseContentForNote(newNote);

      if (!dataService.eventIds.contains(newNote.id)) {
        // Optimized profile fetching
        await _fetchProfilesOptimized(dataService, noteAuthor, isOuterEventRepost ? outerEventAuthor : null);

        dataService.notes.add(newNote);
        dataService.eventIds.add(newNote.id);

        // Async save to avoid blocking
        _saveNoteAsync(dataService, newNote);

        dataService.addNote(newNote);
        dataService.onNewNote?.call(newNote);

        _metrics.notesProcessed++;

        // Async interaction fetching
        _fetchInteractionsAsync(dataService, newNote.id);
      }

      print('[NoteProcessor] Processed note ${eventId} in ${processingStopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      print('[NoteProcessor] Error processing note event: $e');
      _metrics.recordSkip('processing_error');
    }
  }

  static Future<Map<String, dynamic>?> _fetchOriginalEventData(DataService dataService, Map<String, dynamic> eventData) async {
    String? originalEventId;
    final tags = eventData['tags'] as List<dynamic>? ?? [];

    for (var tag in tags) {
      if (tag is List && tag.length >= 2 && tag[0] == 'e') {
        originalEventId = tag[1] as String?;
        break;
      }
    }

    if (originalEventId != null) {
      final fetchedNote = await dataService.fetchNoteByIdIndependently(originalEventId);
      if (fetchedNote != null) {
        if (fetchedNote.rawWs != null && fetchedNote.rawWs!.isNotEmpty) {
          try {
            final decodedRawWs = jsonDecode(fetchedNote.rawWs!) as Map<String, dynamic>;
            if (_isValidEventData(decodedRawWs)) {
              return decodedRawWs;
            }
          } catch (e) {
            print("[NoteProcessor] Error decoding fetchedNote.rawWs: $e");
          }
        }

        return {
          'id': fetchedNote.id,
          'pubkey': fetchedNote.author,
          'content': fetchedNote.content,
          'created_at': fetchedNote.timestamp.millisecondsSinceEpoch ~/ 1000,
          'kind': 1,
          'tags': [],
        };
      }
    }

    return null;
  }

  static bool _isValidEventData(Map<String, dynamic> data) {
    return data.containsKey('id') &&
        data.containsKey('pubkey') &&
        data.containsKey('content') &&
        data.containsKey('created_at') &&
        data.containsKey('kind') &&
        data.containsKey('tags');
  }

  static bool _isValidTarget(
    DataService dataService,
    List<String> targetNpubs,
    String outerEventAuthor,
    String noteAuthor,
    bool isOuterEventRepost,
  ) {
    if (dataService.dataType == DataType.feed) {
      if (isOuterEventRepost) {
        return targetNpubs.contains(outerEventAuthor) || targetNpubs.contains(noteAuthor);
      } else {
        return targetNpubs.contains(noteAuthor);
      }
    } else if (dataService.dataType == DataType.profile) {
      if (isOuterEventRepost) {
        return outerEventAuthor == dataService.npub || noteAuthor == dataService.npub;
      } else {
        return noteAuthor == dataService.npub;
      }
    }
    return true;
  }

  static Map<String, dynamic> _parseReplyTags(List<dynamic> tags) {
    String? rootId;
    String? parentId;
    bool isReply = false;

    for (var tag in tags) {
      if (tag is List && tag.length >= 4 && tag[0] == 'e') {
        if (tag[3] == 'root') {
          rootId = tag[1] as String?;
          isReply = true;
        } else if (tag[3] == 'reply') {
          parentId = tag[1] as String?;
        }
      }
    }

    return {
      'isReply': isReply,
      'rootId': rootId,
      'parentId': parentId ?? (isReply ? rootId : null),
    };
  }

  static Future<void> _fetchProfilesOptimized(
    DataService dataService,
    String noteAuthor,
    String? repostedBy,
  ) async {
    final authorsToFetch = <String>{noteAuthor};
    if (repostedBy != null) {
      authorsToFetch.add(repostedBy);
    }

    _metrics.profilesFetched += authorsToFetch.length;

    // Use batch fetching for better performance
    await dataService.fetchProfilesBatch(authorsToFetch.toList());
  }

  static void _saveNoteAsync(DataService dataService, NoteModel note) {
    if (dataService.notesBox != null && dataService.notesBox!.isOpen) {
      Future.microtask(() async {
        try {
          await dataService.notesBox!.put(note.id, note);
        } catch (e) {
          print('[NoteProcessor] Error saving note: $e');
        }
      });
    }
  }

  static void _fetchInteractionsAsync(DataService dataService, String noteId) {
    Future.microtask(() async {
      try {
        await dataService.fetchInteractionsForEvents([noteId]);
      } catch (e) {
        print('[NoteProcessor] Error fetching interactions: $e');
      }
    });
  }

  // Cleanup method
  static void dispose() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _recentlyProcessed.clear();
    _processingQueue.clear();
  }
}
