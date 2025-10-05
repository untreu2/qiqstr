import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/base/result.dart';
import '../../models/note_model.dart';
import '../../models/reaction_model.dart';
import '../../models/zap_model.dart';
import '../services/network_service.dart';
import '../services/nostr_data_service.dart';

class NoteRepository {
  final NostrDataService _nostrDataService;

  NoteRepository({
    required NetworkService networkService,
    required NostrDataService nostrDataService,
  }) : _nostrDataService = nostrDataService {
    _setupNostrDataServiceForwarding();
  }

  final List<NoteModel> _notes = [];
  final Map<String, List<ReactionModel>> _reactions = {};
  final Map<String, List<ZapModel>> _zaps = {};

  final StreamController<List<NoteModel>> _notesController = StreamController<List<NoteModel>>.broadcast();
  final StreamController<Map<String, List<ReactionModel>>> _reactionsController =
      StreamController<Map<String, List<ReactionModel>>>.broadcast();

  Future<Result<List<NoteModel>>> getFeedNotes({
    required List<String> authorNpubs,
    int limit = 50,
    DateTime? until,
    DateTime? since,
  }) async {
    try {
      debugPrint('[NoteRepository] getFeedNotes called with ${authorNpubs.length} authors: $authorNpubs');

      final result = await _nostrDataService.fetchFeedNotes(
        authorNpubs: authorNpubs,
        limit: limit,
        until: until,
        since: since,
      );

      result.fold(
        (notes) {
          debugPrint('[NoteRepository] NostrDataService returned ${notes.length} notes');

          debugPrint('[NoteRepository] Loaded ${notes.length} feed notes without automatic interaction fetch');
        },
        (error) => debugPrint('[NoteRepository] NostrDataService error: $error'),
      );

      return result;
    } catch (e) {
      debugPrint('[NoteRepository] Exception in getFeedNotes: $e');
      return Result.error('Failed to get feed notes: ${e.toString()}');
    }
  }

  Future<Result<List<NoteModel>>> getFeedNotesFromFollowList({
    required String currentUserNpub,
    int limit = 50,
    DateTime? until,
    DateTime? since,
  }) async {
    try {
      debugPrint('[NoteRepository] getFeedNotesFromFollowList for user: $currentUserNpub');

      final result = await _nostrDataService.fetchFeedNotes(
        authorNpubs: [currentUserNpub], // Special case: triggers follow list expansion
        limit: limit,
        until: until,
        since: since,
      );

      return result.fold(
        (notes) {
          debugPrint('[NoteRepository] Got ${notes.length} notes from follow list');

          final filteredNotes = _filterNotesByFollowList(notes, currentUserNpub);
          debugPrint('[NoteRepository] Filtered to ${filteredNotes.length} notes from followed authors');

          return Result.success(filteredNotes);
        },
        (error) => Result.error(error),
      );
    } catch (e) {
      debugPrint(' [NoteRepository] Exception in getFeedNotesFromFollowList: $e');
      return Result.error('Failed to get feed notes from follow list: ${e.toString()}');
    }
  }

  List<NoteModel> _filterNotesByFollowList(List<NoteModel> notes, String currentUserNpub) {
    debugPrint('[NoteRepository] Feed filtering delegated to NostrDataService, returning ${notes.length} notes');
    return notes;
  }

  Future<Result<List<NoteModel>>> getProfileNotes({
    required String authorNpub,
    int limit = 50,
    DateTime? until,
    DateTime? since,
  }) async {
    try {
      debugPrint('[NoteRepository] PROFILE MODE: Getting notes for $authorNpub (bypassing feed filters)');

      final result = await _nostrDataService.fetchProfileNotes(
        userNpub: authorNpub,
        limit: limit,
        until: until,
        since: since,
      );

      result.fold(
        (notes) {
          debugPrint('[NoteRepository] PROFILE MODE: Loaded ${notes.length} profile notes');
          debugPrint(
              '[NoteRepository] PROFILE MODE: Notes include - Posts: ${notes.where((n) => !n.isReply && !n.isRepost).length}, Replies: ${notes.where((n) => n.isReply && !n.isRepost).length}, Reposts: ${notes.where((n) => n.isRepost).length}');
        },
        (error) => debugPrint('[NoteRepository] PROFILE MODE: Profile notes error: $error'),
      );

      return result;
    } catch (e) {
      debugPrint('[NoteRepository] PROFILE MODE: Exception getting profile notes: $e');
      return Result.error('Failed to get profile notes: ${e.toString()}');
    }
  }

  Future<Result<NoteModel?>> getNoteById(String noteId) async {
    try {
      debugPrint('[NoteRepository] Looking for note ID: $noteId');

      final localNote = _notes.where((n) => n.id == noteId).firstOrNull;
      if (localNote != null) {
        debugPrint('[NoteRepository] Found note in local cache: ${localNote.id}');
        return Result.success(localNote);
      }

      final cachedNotes = _nostrDataService.cachedNotes;
      final cachedNote = cachedNotes.where((n) => n.id == noteId).firstOrNull;
      if (cachedNote != null) {
        debugPrint('[NoteRepository] Found note in NostrDataService cache: ${cachedNote.id}');
        if (!_notes.any((n) => n.id == cachedNote.id)) {
          _notes.add(cachedNote);
        }
        return Result.success(cachedNote);
      }

      debugPrint('[NoteRepository] Note not found in cache, fetching from relays...');

      final success = await _fetchNoteDirectly(noteId);
      if (success) {
        final fetchedNote = _nostrDataService.cachedNotes.where((n) => n.id == noteId).firstOrNull;
        if (fetchedNote != null) {
          debugPrint('[NoteRepository] Successfully fetched note: ${fetchedNote.id}');
          _notes.add(fetchedNote);
          return Result.success(fetchedNote);
        }
      }

      debugPrint('[NoteRepository] Note not found anywhere: $noteId');
      return const Result.success(null);
    } catch (e) {
      debugPrint('[NoteRepository] Error getting note by ID: $e');
      return Result.error('Failed to get note: ${e.toString()}');
    }
  }

  Future<bool> _fetchNoteDirectly(String noteId) async {
    try {
      debugPrint('[NoteRepository] Directly fetching note from relays: $noteId');

      final success = await _nostrDataService.fetchSpecificNote(noteId);

      if (success) {
        debugPrint('[NoteRepository] Successfully requested note from relays: $noteId');
        await Future.delayed(const Duration(seconds: 3));
        return true;
      } else {
        debugPrint('[NoteRepository] Failed to request note from relays: $noteId');
        return false;
      }
    } catch (e) {
      debugPrint('[NoteRepository] Error in direct note fetch: $e');
      return false;
    }
  }

  Future<Result<List<NoteModel>>> getThreadReplies(String rootNoteId) async {
    try {
      debugPrint('[NoteRepository] Getting thread replies for root: $rootNoteId');

      final allNotes = <NoteModel>[];

      allNotes.addAll(_notes);
      debugPrint(' [NoteRepository] Local cache has ${_notes.length} notes');

      final cachedNotes = _nostrDataService.cachedNotes;
      debugPrint(' [NoteRepository] NostrDataService cache has ${cachedNotes.length} notes');

      for (final note in cachedNotes) {
        if (!allNotes.any((n) => n.id == note.id)) {
          allNotes.add(note);
          _notes.add(note);
        }
      }

      debugPrint('[NoteRepository] Combined cache has ${allNotes.length} notes total');

      final threadReplies = allNotes.where((note) {
        final isReply = note.isReply;
        final hasCorrectRoot = note.rootId == rootNoteId;
        final hasCorrectParent = note.parentId == rootNoteId;
        final isThreadMember = hasCorrectRoot || hasCorrectParent;

        debugPrint(
            '[NoteRepository] Note ${note.id}: isReply=$isReply, rootId=${note.rootId}, parentId=${note.parentId}, isThreadMember=$isThreadMember');

        return isReply && isThreadMember;
      }).toList();

      debugPrint('[NoteRepository] Found ${threadReplies.length} thread replies in combined cache');

      for (final reply in threadReplies) {
        debugPrint('Reply ${reply.id}: parentId=${reply.parentId}, rootId=${reply.rootId}, author=${reply.author}');
      }

      debugPrint('[NoteRepository] Found ${threadReplies.length} thread replies without automatic interaction fetch');

      threadReplies.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      return Result.success(threadReplies);
    } catch (e) {
      debugPrint('[NoteRepository] Error getting thread replies: $e');
      return Result.error('Failed to get thread replies: ${e.toString()}');
    }
  }

  Future<Result<List<NoteModel>>> getDirectReplies(String noteId) async {
    try {
      final directReplies = _notes.where((note) => note.isReply && note.parentId == noteId).toList();

      directReplies.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      return Result.success(directReplies);
    } catch (e) {
      return Result.error('Failed to get direct replies: ${e.toString()}');
    }
  }

  Future<Result<void>> addNote(NoteModel note) async {
    try {
      final existingNote = _notes.where((n) => n.id == note.id).firstOrNull;
      if (existingNote != null) {
        return const Result.success(null); // Note already exists
      }

      _notes.add(note);
      _notesController.add(_notes);

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to add note: ${e.toString()}');
    }
  }

  Future<Result<void>> updateNote(NoteModel updatedNote) async {
    try {
      final index = _notes.indexWhere((n) => n.id == updatedNote.id);
      if (index != -1) {
        _notes[index] = updatedNote;
        _notesController.add(_notes);
      }

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to update note: ${e.toString()}');
    }
  }

  Future<Result<void>> removeNote(String noteId) async {
    try {
      _notes.removeWhere((n) => n.id == noteId);
      _notesController.add(_notes);

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to remove note: ${e.toString()}');
    }
  }

  Future<Result<List<ReactionModel>>> getReactions(String noteId) async {
    try {
      final reactions = _reactions[noteId] ?? [];
      return Result.success(reactions);
    } catch (e) {
      return Result.error('Failed to get reactions: ${e.toString()}');
    }
  }

  Future<Result<void>> addReaction(String noteId, ReactionModel reaction) async {
    try {
      _reactions.putIfAbsent(noteId, () => []);

      final existingReaction = _reactions[noteId]!.where((r) => r.id == reaction.id).firstOrNull;

      if (existingReaction == null) {
        _reactions[noteId]!.add(reaction);

        final note = _notes.where((n) => n.id == noteId).firstOrNull;
        if (note != null) {
          note.reactionCount = _reactions[noteId]!.length;
        }

        _reactionsController.add(_reactions);
      }

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to add reaction: ${e.toString()}');
    }
  }

  Future<Result<void>> clearCache() async {
    try {
      _notes.clear();
      _reactions.clear();
      _zaps.clear();

      _notesController.add(_notes);
      _reactionsController.add(_reactions);

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to clear cache: ${e.toString()}');
    }
  }

  Stream<List<NoteModel>> get notesStream => _notesController.stream;

  Stream<Map<String, List<ReactionModel>>> get reactionsStream => _reactionsController.stream;

  List<NoteModel> get currentNotes => List.unmodifiable(_notes);

  Map<String, List<ReactionModel>> get currentReactions => Map.unmodifiable(_reactions);

  Map<String, List<NoteModel>> buildThreadHierarchy(String rootNoteId) {
    final Map<String, List<NoteModel>> hierarchy = {};
    final threadReplies = _notes.where((note) => note.isReply && (note.rootId == rootNoteId || note.parentId == rootNoteId)).toList();

    for (final reply in threadReplies) {
      final parentId = reply.parentId ?? rootNoteId;
      hierarchy.putIfAbsent(parentId, () => []);
      hierarchy[parentId]!.add(reply);
    }

    hierarchy.forEach((key, replies) {
      replies.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });

    return hierarchy;
  }

  NoteStats getNoteStats(String noteId) {
    return NoteStats(
      reactionCount: _reactions[noteId]?.length ?? 0,
      replyCount: 0, // Simplified: No separate reply tracking
      repostCount: 0, // Simplified: No separate repost tracking
      zapAmount: _zaps[noteId]?.fold<int>(0, (sum, zap) => sum + zap.amount) ?? 0,
    );
  }

  void updateNoteInteractionCounts(String noteId) {
    final note = _notes.where((n) => n.id == noteId).firstOrNull;
    if (note != null) {
      final stats = getNoteStats(noteId);
      note.reactionCount = stats.reactionCount;
      note.replyCount = stats.replyCount;
      note.repostCount = stats.repostCount;
      note.zapAmount = stats.zapAmount;
    }
  }

  Future<Result<void>> reactToNote(String noteId, String reaction) async {
    try {
      return await _nostrDataService.reactToNote(
        noteId: noteId,
        reaction: reaction,
      );
    } catch (e) {
      return Result.error('Failed to react to note: $e');
    }
  }

  Future<Result<void>> repostNote(String noteId) async {
    try {
      final note = _notes.where((n) => n.id == noteId).firstOrNull;
      if (note == null) {
        return const Result.error('Note not found');
      }

      return await _nostrDataService.repostNote(
        noteId: noteId,
        noteAuthor: note.author,
      );
    } catch (e) {
      return Result.error('Failed to repost note: $e');
    }
  }

  Future<Result<NoteModel>> postNote({
    required String content,
    List<List<String>>? tags,
  }) async {
    try {
      return await _nostrDataService.postNote(
        content: content,
        tags: tags,
      );
    } catch (e) {
      return Result.error('Failed to post note: $e');
    }
  }

  Future<Result<NoteModel>> postReply({
    required String content,
    required String rootId,
    String? replyId,
    required String parentAuthor,
    required List<String> relayUrls,
  }) async {
    try {
      return await _nostrDataService.postReply(
        content: content,
        rootId: rootId,
        replyId: replyId,
        parentAuthor: parentAuthor,
        relayUrls: relayUrls,
      );
    } catch (e) {
      return Result.error('Failed to post reply: $e');
    }
  }

  Future<Result<NoteModel>> postQuote({
    required String content,
    required String quotedEventId,
    String? quotedEventPubkey,
    String? relayUrl,
    List<List<String>>? additionalTags,
  }) async {
    try {
      return await _nostrDataService.postQuote(
        content: content,
        quotedEventId: quotedEventId,
        quotedEventPubkey: quotedEventPubkey,
        relayUrl: relayUrl,
        additionalTags: additionalTags,
      );
    } catch (e) {
      return Result.error('Failed to post quote: $e');
    }
  }

  Stream<List<NoteModel>> get realTimeNotesStream => _nostrDataService.notesStream;

  Future<Result<void>> startRealTimeFeed(List<String> authorNpubs) async {
    try {
      debugPrint(' [NoteRepository] Starting real-time feed for ${authorNpubs.length} authors');

      final feedResult = await getFeedNotes(authorNpubs: authorNpubs);
      if (feedResult.isError) {
        debugPrint(' [NoteRepository] Initial feed fetch failed: ${feedResult.error}');
        return Result.error(feedResult.error!);
      }

      debugPrint(' [NoteRepository] Setting up stream subscription...');

      _nostrDataService.notesStream.listen((newNotes) {
        debugPrint(' [NoteRepository] Stream received ${newNotes.length} notes');

        int addedCount = 0;
        for (final note in newNotes) {
          if (!_notes.any((n) => n.id == note.id)) {
            _notes.add(note);
            addedCount++;
          }
        }

        debugPrint(' [NoteRepository] Added $addedCount new notes, total: ${_notes.length}');

        _notes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _notesController.add(_notes);

        debugPrint(' [NoteRepository] Emitted update to subscribers');
      });

      return const Result.success(null);
    } catch (e) {
      debugPrint(' [NoteRepository] Exception in startRealTimeFeed: $e');
      return Result.error('Failed to start real-time feed: $e');
    }
  }

  void _setupNostrDataServiceForwarding() {
    _nostrDataService.notesStream.listen((updatedNotes) {
      debugPrint(' [NoteRepository] Forwarding ${updatedNotes.length} updated notes from NostrDataService');

      for (final updatedNote in updatedNotes) {
        final existingIndex = _notes.indexWhere((n) => n.id == updatedNote.id);
        if (existingIndex != -1) {
          _notes[existingIndex] = updatedNote;
        } else {
          _notes.add(updatedNote);
        }
      }

      _notesController.add(_notes);

      debugPrint(' [NoteRepository] Forwarded note updates to InteractionBar listeners');
    });
  }

  void dispose() {
    _notesController.close();
    _reactionsController.close();
  }
}

class NoteStats {
  final int reactionCount;
  final int replyCount;
  final int repostCount;
  final int zapAmount;

  const NoteStats({
    required this.reactionCount,
    required this.replyCount,
    required this.repostCount,
    required this.zapAmount,
  });

  @override
  String toString() => 'NoteStats(reactions: $reactionCount, replies: $replyCount, reposts: $repostCount, zaps: $zapAmount)';
}
