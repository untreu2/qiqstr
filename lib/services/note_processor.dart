import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/note_model.dart';
import 'time_service.dart';
import 'note_widget_calculator.dart';

class NoteProcessor {
  static final TimeService timeService = TimeService.instance;

  static void processNoteEvent(
    dynamic dataService,
    Map<String, dynamic> eventData,
    List<String> targetNpubs, {
    String? rawWs,
    String? repostedBy,
    DateTime? repostTimestamp,
  }) {
    try {
      final noteId = eventData['id'] as String;
      final author = eventData['pubkey'] as String;
      final content = eventData['content'] as String;
      final createdAt = eventData['created_at'] as int;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

      if (dataService.eventIds.contains(noteId)) {
        return;
      }

      final replyInfo = _analyzeReplyStructure(eventData);

      final noteModel = NoteModel(
        id: noteId,
        content: content,
        author: author,
        timestamp: timestamp,
        isRepost: repostedBy != null,
        repostedBy: repostedBy,
        repostTimestamp: repostTimestamp,
        isReply: replyInfo.isReply,
        parentId: replyInfo.parentId,
        rootId: replyInfo.rootId,
        rawWs: rawWs ?? jsonEncode(eventData),
        eTags: replyInfo.eTags,
        pTags: replyInfo.pTags,
        tTags: replyInfo.tTags,
        replyMarker: replyInfo.replyMarker,
      );

      noteModel.hasMedia = noteModel.hasMediaLazy;

      try {
        final calculator = NoteWidgetCalculator.instance;
        final metrics = NoteWidgetCalculator.calculateMetrics(noteModel);
        calculator.cacheMetrics(metrics);
        NoteWidgetCalculator.updateNoteWithMetrics(noteModel, metrics);
      } catch (e) {
        debugPrint('[NoteProcessor] Error calculating widget metrics: $e');
      }

      dataService.notes.add(noteModel);
      dataService.eventIds.add(noteModel.id);
      dataService.addNote(noteModel);

      dataService._dataManager.notesBox?.put(noteModel.id, noteModel).catchError((e) {
        debugPrint('[NoteProcessor] Error caching note: $e');
      });

      if (dataService.onNewNote != null) {
        dataService.onNewNote!(noteModel);
      }

      debugPrint('[NoteProcessor] Processed ${replyInfo.isReply ? 'reply' : 'note'}: ${noteId.substring(0, 8)}... '
          '${repostedBy != null ? 'reposted by ${repostedBy.substring(0, 8)}...' : ''}');
    } catch (e) {
      debugPrint('[NoteProcessor] Error processing note event: $e');
    }
  }

  static ReplyInfo _analyzeReplyStructure(Map<String, dynamic> eventData) {
    final tags = List<dynamic>.from(eventData['tags'] ?? []);

    String? rootId;
    String? parentId;
    String? replyMarker;
    List<Map<String, String>> eTags = [];
    List<Map<String, String>> pTags = [];
    List<String> tTags = [];

    for (var tag in tags) {
      if (tag is List && tag.isNotEmpty) {
        if (tag[0] == 'e' && tag.length >= 2) {
          final eTag = <String, String>{
            'eventId': tag[1] as String,
            'relayUrl': tag.length > 2 ? (tag[2] as String? ?? '') : '',
            'marker': tag.length > 3 ? (tag[3] as String? ?? '') : '',
            'pubkey': tag.length > 4 ? (tag[4] as String? ?? '') : '',
          };
          eTags.add(eTag);

          if (tag.length >= 4) {
            final marker = tag[3] as String;
            if (marker == 'root') {
              rootId = tag[1] as String;
              replyMarker = 'root';
            } else if (marker == 'reply') {
              parentId = tag[1] as String;
              replyMarker = 'reply';
            }
          }
        } else if (tag[0] == 'p' && tag.length >= 2) {
          final pTag = <String, String>{
            'pubkey': tag[1] as String,
            'relayUrl': tag.length > 2 ? (tag[2] as String? ?? '') : '',
            'petname': tag.length > 3 ? (tag[3] as String? ?? '') : '',
          };
          pTags.add(pTag);
        } else if (tag[0] == 't' && tag.length >= 2) {
          final hashtag = (tag[1] as String).toLowerCase();
          if (!tTags.contains(hashtag)) {
            tTags.add(hashtag);
          }
        }
      }
    }

    if (rootId != null && parentId == null) {
      parentId = rootId;
    }

    final bool isReply = rootId != null;

    return ReplyInfo(
      isReply: isReply,
      rootId: rootId,
      parentId: parentId,
      eTags: eTags,
      pTags: pTags,
      tTags: tTags,
      replyMarker: replyMarker,
    );
  }

  static bool isRepostOfReply(String repostContent) {
    try {
      final contentJson = jsonDecode(repostContent) as Map<String, dynamic>;
      final replyInfo = _analyzeReplyStructure(contentJson);
      return replyInfo.isReply;
    } catch (e) {
      debugPrint('[NoteProcessor] Error checking if repost is reply: $e');
      return false;
    }
  }

  static Map<String, dynamic>? extractOriginalNoteFromRepost(String repostContent) {
    try {
      return jsonDecode(repostContent) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[NoteProcessor] Error extracting original note from repost: $e');
      return null;
    }
  }
}

class ReplyInfo {
  final bool isReply;
  final String? rootId;
  final String? parentId;
  final List<Map<String, String>> eTags;
  final List<Map<String, String>> pTags;
  final List<String> tTags;
  final String? replyMarker;

  ReplyInfo({
    required this.isReply,
    this.rootId,
    this.parentId,
    required this.eTags,
    required this.pTags,
    required this.tTags,
    this.replyMarker,
  });
}
