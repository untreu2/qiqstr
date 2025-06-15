import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/services/data_service.dart';

class NoteProcessor {
  static Future<void> processNoteEvent(
    DataService dataService,
    Map<String, dynamic> eventData,
    List<String> targetNpubs, {
    String? rawWs,
  }) async {
    int kind = eventData['kind'] as int;
    final String outerEventAuthor = eventData['pubkey'] as String;
    bool isOuterEventRepost = kind == 6;
    Map<String, dynamic>? innerEventData;
    DateTime? repostTimestamp;
    String? repostedEventJsonString;

    if (isOuterEventRepost) {
      repostTimestamp =
          DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000);
      repostedEventJsonString = eventData['content'] as String?;

      if (repostedEventJsonString != null && repostedEventJsonString.isNotEmpty) {
        try {
          innerEventData = jsonDecode(repostedEventJsonString) as Map<String, dynamic>;
        } catch (e) {
          print('[NoteProcessor] Error decoding repost content: $e. Content: $repostedEventJsonString');
        }
      }

      if (innerEventData == null) {
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
                if (decodedRawWs.containsKey('id') &&
                    decodedRawWs.containsKey('pubkey') &&
                    decodedRawWs.containsKey('content') &&
                    decodedRawWs.containsKey('created_at') &&
                    decodedRawWs.containsKey('kind') &&
                    decodedRawWs.containsKey('tags')) {
                  innerEventData = decodedRawWs;
                }
              } catch (e) {
                print("[NoteProcessor] Error decoding fetchedNote.rawWs for event $originalEventId: $e");
              }
            }
            innerEventData ??= {
                'id': fetchedNote.id,
                'pubkey': fetchedNote.author,
                'content': fetchedNote.content,
                'created_at': fetchedNote.timestamp.millisecondsSinceEpoch ~/ 1000,
                'kind': 1,
                'tags': [],
              };
          }
        }
      }

      if (innerEventData == null) {
        print('[NoteProcessor] Skipped repost: original event data could not be obtained for kind 6 event ID ${eventData['id']} by author $outerEventAuthor');
        return;
      }
      eventData = innerEventData;
      kind = eventData['kind'] as int? ?? 1;
    }

    final eventId = eventData['id'] as String?;
    if (eventId == null) {
      print('[NoteProcessor] Skipped event: missing event ID.');
      return;
    }

    final String noteAuthor = eventData['pubkey'] as String;
    final noteContentRaw = eventData['content'];
    String noteContent = noteContentRaw is String ? noteContentRaw : jsonEncode(noteContentRaw);
    final tags = eventData['tags'] as List<dynamic>? ?? [];

    if (dataService.eventIds.contains(eventId) || noteContent.trim().isEmpty) {
      return;
    }

    if (dataService.dataType == DataType.feed) {
      if (isOuterEventRepost) {
        if (!targetNpubs.contains(outerEventAuthor) && !targetNpubs.contains(noteAuthor)) return;
      } else {
        if (!targetNpubs.contains(noteAuthor)) return;
      }
    } else if (dataService.dataType == DataType.profile) {
      if (isOuterEventRepost) {
        if (outerEventAuthor != dataService.npub && noteAuthor != dataService.npub) return;
      } else {
        if (noteAuthor != dataService.npub) return;
      }
    }

    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      (eventData['created_at'] as int) * 1000,
    );

    final rootTag = tags.firstWhereOrNull(
      (tag) => tag is List && tag.length >= 4 && tag[0] == 'e' && tag[3] == 'root',
    );
    final replyTag = tags.firstWhereOrNull(
      (tag) => tag is List && tag.length >= 4 && tag[0] == 'e' && tag[3] == 'reply',
    );

    final bool isActualReply = rootTag != null;
    final String? rootId = rootTag != null ? rootTag[1] as String? : null;
    final String? parentId = replyTag != null ? replyTag[1] as String? : (isActualReply ? rootId : null);

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
      dataService.eventIds.add(newNote.id);
      if (dataService.notesBox != null && dataService.notesBox!.isOpen) {
        await dataService.notesBox!.put(newNote.id, newNote);
      }

      dataService.onNewNote?.call(newNote);
      dataService.addPendingNote(newNote);

      final List<String> authorsToFetch = [noteAuthor];
      if (isOuterEventRepost) {
        authorsToFetch.add(outerEventAuthor);
      }
      await dataService.fetchProfilesBatch(authorsToFetch.toSet().toList());
    }

    Future.microtask(() async {
      await Future.wait([
        dataService.fetchInteractionsForEvents([newNote.id]),
      ]);
    });
  }
}
