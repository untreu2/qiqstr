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
  Timer? _notesUpdateThrottleTimer;
  bool _notesUpdatePending = false;
  final Map<String, NoteModel> _notesMap = {};

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
    bool forceRefresh = false,
  }) async {
    try {
      debugPrint('[NoteRepository] getFeedNotesFromFollowList for user: $currentUserNpub, forceRefresh: $forceRefresh');

      final result = await _nostrDataService.fetchFeedNotes(
        authorNpubs: [currentUserNpub],
        limit: limit,
        until: until,
        since: since,
        forceRefresh: forceRefresh,
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

  Future<Result<List<NoteModel>>> getHashtagNotes({
    required String hashtag,
    int limit = 20,
    DateTime? until,
    DateTime? since,
    bool forceRefresh = false,
  }) async {
    try {
      debugPrint('[NoteRepository] HASHTAG MODE: Getting notes for #$hashtag, forceRefresh: $forceRefresh');

      final result = await _nostrDataService.fetchHashtagNotes(
        hashtag: hashtag,
        limit: limit,
        until: until,
        since: since,
        forceRefresh: forceRefresh,
      );

      result.fold(
        (notes) {
          debugPrint('[NoteRepository] HASHTAG MODE: Loaded ${notes.length} notes');
        },
        (error) => debugPrint('[NoteRepository] HASHTAG MODE: Error: $error'),
      );

      return result;
    } catch (e) {
      debugPrint('[NoteRepository] HASHTAG MODE: Exception: $e');
      return Result.error('Failed to get hashtag notes: ${e.toString()}');
    }
  }

  Future<Result<NoteModel?>> getNoteById(String noteId) async {
    try {
      debugPrint('[NoteRepository] Looking for note ID: $noteId');

      _nostrDataService.setContext('thread');

      final localNote = _notesMap[noteId];
      if (localNote != null) {
        debugPrint('[NoteRepository] Found note in local cache: ${localNote.id}');
        return Result.success(localNote);
      }

      final cachedNotes = _nostrDataService.cachedNotes;
      NoteModel? cachedNote;
      for (final note in cachedNotes) {
        if (note.id == noteId) {
          cachedNote = note;
          break;
        }
      }
      if (cachedNote != null) {
        debugPrint('[NoteRepository] Found note in NostrDataService cache: ${cachedNote.id}');
        if (!_notesMap.containsKey(cachedNote.id)) {
          _notesMap[cachedNote.id] = cachedNote;
          _notes.add(cachedNote);
        }
        return Result.success(cachedNote);
      }

      debugPrint('[NoteRepository] Note not found in cache, fetching from relays...');

      final success = await _fetchNoteDirectly(noteId);
      if (success) {
        NoteModel? fetchedNote;
        for (final note in _nostrDataService.cachedNotes) {
          if (note.id == noteId) {
            fetchedNote = note;
            break;
          }
        }
        if (fetchedNote != null) {
          debugPrint('[NoteRepository] Successfully fetched note: ${fetchedNote.id}');
          _notesMap[fetchedNote.id] = fetchedNote;
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

      _nostrDataService.setContext('thread');

      final allNotes = <NoteModel>[];

      allNotes.addAll(_notes);
      debugPrint(' [NoteRepository] Local cache has ${_notes.length} notes');

      final cachedNotes = _nostrDataService.cachedNotes;
      debugPrint(' [NoteRepository] NostrDataService cache has ${cachedNotes.length} notes');

      final allNotesSet = <String>{};
      for (final note in _notes) {
        allNotesSet.add(note.id);
      }
      for (final note in cachedNotes) {
        if (!allNotesSet.contains(note.id)) {
          allNotesSet.add(note.id);
          allNotes.add(note);
          _notesMap[note.id] = note;
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
      final directReplies = <NoteModel>[];
      for (final note in _notes) {
        if (note.isReply && note.parentId == noteId) {
          directReplies.add(note);
        }
      }

      directReplies.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      return Result.success(directReplies);
    } catch (e) {
      return Result.error('Failed to get direct replies: ${e.toString()}');
    }
  }

  Future<Result<void>> addNote(NoteModel note) async {
    try {
      final existingNote = _notesMap[note.id];
      if (existingNote != null) {
        return const Result.success(null);
      }

      _notesMap[note.id] = note;
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

      ReactionModel? existingReaction;
      for (final r in _reactions[noteId]!) {
        if (r.id == reaction.id) {
          existingReaction = r;
          break;
        }
      }

      if (existingReaction == null) {
        _reactions[noteId]!.add(reaction);

        final note = _notesMap[noteId];
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
    final threadReplies = <NoteModel>[];
    for (final note in _notes) {
      if (note.isReply && (note.rootId == rootNoteId || note.parentId == rootNoteId)) {
        threadReplies.add(note);
      }
    }

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
      replyCount: 0,
      repostCount: 0,
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
    List<List<String>>? additionalTags,
  }) async {
    try {
      return await _nostrDataService.postReply(
        content: content,
        rootId: rootId,
        replyId: replyId,
        parentAuthor: parentAuthor,
        relayUrls: relayUrls,
        additionalTags: additionalTags,
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
        if (newNotes.isEmpty) return;

        bool hasChanges = false;
        for (final note in newNotes) {
          if (!_notesMap.containsKey(note.id)) {
            _notesMap[note.id] = note;
            _notes.add(note);
            hasChanges = true;
          }
        }

        if (!hasChanges) return;

        _notesUpdatePending = true;
        _notesUpdateThrottleTimer?.cancel();
        _notesUpdateThrottleTimer = Timer(const Duration(milliseconds: 150), () {
          if (_notesUpdatePending) {
            _notes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            _notesUpdatePending = false;
            _notesController.add(List.unmodifiable(_notes));
          }
        });
      });

      return const Result.success(null);
    } catch (e) {
      debugPrint(' [NoteRepository] Exception in startRealTimeFeed: $e');
      return Result.error('Failed to start real-time feed: $e');
    }
  }

  void _setupNostrDataServiceForwarding() {
    _nostrDataService.notesStream.listen((updatedNotes) {
      if (updatedNotes.isEmpty) return;

      bool hasChanges = false;
      for (final updatedNote in updatedNotes) {
        final existingNote = _notesMap[updatedNote.id];
        if (existingNote != null) {
          if (existingNote.reactionCount != updatedNote.reactionCount ||
              existingNote.repostCount != updatedNote.repostCount ||
              existingNote.replyCount != updatedNote.replyCount ||
              existingNote.zapAmount != updatedNote.zapAmount) {
            _notesMap[updatedNote.id] = updatedNote;
            final index = _notes.indexWhere((n) => n.id == updatedNote.id);
            if (index != -1) {
              _notes[index] = updatedNote;
            }
            hasChanges = true;
          }
        } else {
          _notesMap[updatedNote.id] = updatedNote;
          _notes.add(updatedNote);
          hasChanges = true;
        }
      }

      if (!hasChanges) return;

      _notesUpdatePending = true;
      _notesUpdateThrottleTimer?.cancel();
      _notesUpdateThrottleTimer = Timer(const Duration(seconds: 1), () {
        if (_notesUpdatePending) {
          _notesUpdatePending = false;
          _notesController.add(List.unmodifiable(_notes));
        }
      });
    });
  }

  Future<void> fetchInteractionsForNote(String noteId) async {
    try {
      await _nostrDataService.fetchInteractionsForNotes([noteId], forceLoad: false);

      _updateNoteReplyCount(noteId);
    } catch (e) {
      debugPrint('[NoteRepository] Error fetching interactions for note $noteId: $e');
    }
  }

  Future<void> fetchInteractionsForNotes(List<String> noteIds) async {
    try {
      if (noteIds.isEmpty) return;

      await _nostrDataService.fetchInteractionsForNotes(noteIds, forceLoad: false);

      for (final noteId in noteIds) {
        _updateNoteReplyCount(noteId);
      }
    } catch (e) {
      debugPrint('[NoteRepository] Error fetching interactions for notes: $e');
    }
  }

  void _updateNoteReplyCount(String noteId) {
    try {
      final note = _notesMap[noteId];
      if (note != null) {
        final cachedNotes = _nostrDataService.cachedNotes;
        int replyCount = 0;
        for (final reply in cachedNotes) {
          if (reply.isReply && (reply.parentId == noteId || reply.rootId == noteId)) {
            replyCount++;
          }
        }

        if (note.replyCount != replyCount) {
          note.replyCount = replyCount;

          _notesController.add(_notes);
        }
      }
    } catch (e) {
      debugPrint('[NoteRepository] Error updating note reply count: $e');
    }
  }

  bool hasUserReacted(String noteId, String userNpub) {
    try {
      return _nostrDataService.hasUserReacted(noteId, userNpub);
    } catch (e) {
      debugPrint('[NoteRepository] Error checking user reaction: $e');
      return false;
    }
  }

  bool hasUserReposted(String noteId, String userNpub) {
    try {
      return _nostrDataService.hasUserReposted(noteId, userNpub);
    } catch (e) {
      debugPrint('[NoteRepository] Error checking user repost: $e');
      return false;
    }
  }

  bool hasUserZapped(String noteId, String userNpub) {
    try {
      return _nostrDataService.hasUserZapped(noteId, userNpub);
    } catch (e) {
      debugPrint('[NoteRepository] Error checking user zap: $e');
      return false;
    }
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
