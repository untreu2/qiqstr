import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/note_model.dart';
import 'time_service.dart';

class NoteProcessor {
  static final TimeService timeService = TimeService.instance;

  /// Process a note event (kind 1) or reposted note content
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

      // Skip if we already have this note
      if (dataService.eventIds.contains(noteId)) {
        return;
      }

      // Check if this note is a reply using NIP-10 rules
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
        replyMarker: replyInfo.replyMarker,
      );

      // Set media detection
      noteModel.hasMedia = noteModel.hasMediaLazy;

      // Add to data structures
      dataService.notes.add(noteModel);
      dataService.eventIds.add(noteModel.id);
      dataService.addNote(noteModel);

      // Cache the note
      dataService._dataManager.notesBox?.put(noteModel.id, noteModel).catchError((e) {
        debugPrint('[NoteProcessor] Error caching note: $e');
      });

      // Notify listeners if it's a new note for the current user
      if (dataService.onNewNote != null) {
        dataService.onNewNote!(noteModel);
      }

      debugPrint('[NoteProcessor] Processed ${replyInfo.isReply ? 'reply' : 'note'}: ${noteId.substring(0, 8)}... '
          '${repostedBy != null ? 'reposted by ${repostedBy.substring(0, 8)}...' : ''}');
    } catch (e) {
      debugPrint('[NoteProcessor] Error processing note event: $e');
    }
  }

  /// Analyze a note's reply structure according to NIP-10
  static ReplyInfo _analyzeReplyStructure(Map<String, dynamic> eventData) {
    final tags = List<dynamic>.from(eventData['tags'] ?? []);

    String? rootId;
    String? parentId;
    String? replyMarker;
    bool isReply = false;
    List<Map<String, String>> eTags = [];
    List<Map<String, String>> pTags = [];

    // Process all tags
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

          // Check for NIP-10 markers
          if (tag.length >= 4) {
            final marker = tag[3] as String;
            if (marker == 'root') {
              rootId = tag[1] as String;
              replyMarker = 'root';
              isReply = true;
            } else if (marker == 'reply') {
              parentId = tag[1] as String;
              replyMarker = 'reply';
              isReply = true;
            } else if (marker == 'mention') {
              // This is just a mention, not a reply
              continue;
            }
          } else {
            // Legacy positional e-tags (deprecated but still supported)
            if (!isReply) {
              // First e-tag without marker is considered the parent/root
              parentId = tag[1] as String;
              isReply = true;
            }
          }
        } else if (tag[0] == 'p' && tag.length >= 2) {
          final pTag = <String, String>{
            'pubkey': tag[1] as String,
            'relayUrl': tag.length > 2 ? (tag[2] as String? ?? '') : '',
            'petname': tag.length > 3 ? (tag[3] as String? ?? '') : '',
          };
          pTags.add(pTag);
        }
      }
    }

    // If we have both root and reply markers, use the appropriate parent
    if (rootId != null && parentId != null) {
      // This is a reply in a thread, parentId is the immediate parent
      // rootId stays as the thread root
    } else if (rootId != null && parentId == null) {
      // This is a direct reply to the root
      parentId = rootId;
    }

    return ReplyInfo(
      isReply: isReply,
      rootId: rootId,
      parentId: parentId,
      eTags: eTags,
      pTags: pTags,
      replyMarker: replyMarker,
    );
  }

  /// Check if a repost content contains a reply
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

  /// Extract the original note from repost content
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
  final String? replyMarker;

  ReplyInfo({
    required this.isReply,
    this.rootId,
    this.parentId,
    required this.eTags,
    required this.pTags,
    this.replyMarker,
  });
}
