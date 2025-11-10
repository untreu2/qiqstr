import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/base/result.dart';
import '../../models/note_model.dart';
import '../../models/user_model.dart';
import '../../data/services/user_batch_fetcher.dart';
import 'note_repository.dart';
import 'user_repository.dart';

class ThreadRepository {
  final NoteRepository _noteRepository;
  final UserRepository? _userRepository;

  ThreadRepository({
    required NoteRepository noteRepository,
    UserRepository? userRepository,
  })  : _noteRepository = noteRepository,
        _userRepository = userRepository;

  Future<Result<NoteModel?>> getRootNote(String rootNoteId) async {
    try {
      return await _noteRepository.getNoteById(rootNoteId);
    } catch (e) {
      debugPrint('[ThreadRepository] Error getting root note: $e');
      return Result.error('Failed to get root note: ${e.toString()}');
    }
  }

  Future<Result<List<NoteModel>>> getThreadReplies(String rootNoteId) async {
    try {
      return await _noteRepository.getThreadReplies(rootNoteId);
    } catch (e) {
      debugPrint('[ThreadRepository] Error getting thread replies: $e');
      return Result.error('Failed to get thread replies: ${e.toString()}');
    }
  }

  Future<Result<ThreadData>> loadThread(String rootNoteId) async {
    try {
      final results = await Future.wait([
        _noteRepository.getNoteById(rootNoteId),
        _noteRepository.getThreadReplies(rootNoteId),
      ]);

      final rootResult = results[0] as Result<NoteModel?>;
      if (rootResult.isError) {
        return Result.error(rootResult.error!);
      }

      final rootNote = rootResult.data;
      if (rootNote == null) {
        return Result.error('Note not found');
      }

      final repliesResult = results[1] as Result<List<NoteModel>>;
      if (repliesResult.isError) {
        return Result.error(repliesResult.error!);
      }

      final replies = repliesResult.data!;

      if (_userRepository != null) {
        await _loadUsersForThread([rootNote, ...replies]);
      }

      final structure = buildThreadStructure(rootNote, replies);

      return Result.success(ThreadData(
        rootNote: rootNote,
        replies: replies,
        structure: structure,
      ));
    } catch (e) {
      debugPrint('[ThreadRepository] Error loading thread: $e');
      return Result.error('Failed to load thread: ${e.toString()}');
    }
  }

  Future<Result<void>> addReply({
    required String content,
    required String rootId,
    required String replyId,
    required String parentAuthor,
    List<String>? relayUrls,
  }) async {
    try {
      return await _noteRepository.postReply(
        content: content,
        rootId: rootId,
        replyId: replyId,
        parentAuthor: parentAuthor,
        relayUrls: relayUrls ?? ['wss://relay.damus.io'],
      );
    } catch (e) {
      debugPrint('[ThreadRepository] Error adding reply: $e');
      return Result.error('Failed to add reply: ${e.toString()}');
    }
  }

  Future<void> fetchInteractionsForThread(List<NoteModel> notes) async {
    try {
      const maxInitialInteractionFetch = 8;
      final limitedNotes = notes.take(maxInitialInteractionFetch).toList();
      
      if (notes.length > maxInitialInteractionFetch) {
        debugPrint('[ThreadRepository] Limiting interaction fetch from ${notes.length} to $maxInitialInteractionFetch notes');
      }
      
      final noteIds = <String>{};
      for (final note in limitedNotes) {
        if (note.isRepost && note.rootId != null) {
          noteIds.add(note.rootId!);
        } else {
          noteIds.add(note.id);
        }
      }
      
      if (noteIds.isEmpty) return;

      debugPrint('[ThreadRepository] Fetching interactions for ${noteIds.length} notes');
      
      await _noteRepository.fetchInteractionsForNotes(
        noteIds.toList(), 
        useCount: false,
        forceLoad: true,
      );
    } catch (e) {
      debugPrint('[ThreadRepository] Error fetching interactions: $e');
    }
  }

  Stream<List<NoteModel>> get realTimeNotesStream => _noteRepository.realTimeNotesStream;

  Future<Result<void>> reactToNote(String noteId, String reaction) async {
    try {
      return await _noteRepository.reactToNote(noteId, reaction);
    } catch (e) {
      debugPrint('[ThreadRepository] Error reacting to note: $e');
      return Result.error('Failed to react to note: ${e.toString()}');
    }
  }

  Future<Result<void>> repostNote(String noteId) async {
    try {
      return await _noteRepository.repostNote(noteId);
    } catch (e) {
      debugPrint('[ThreadRepository] Error reposting note: $e');
      return Result.error('Failed to repost note: ${e.toString()}');
    }
  }

  ThreadStructure buildThreadStructure(NoteModel root, List<NoteModel> replies) {
    final Map<String, List<NoteModel>> childrenMap = {};
    final Map<String, NoteModel> notesMap = {root.id: root};

    for (final reply in replies) {
      notesMap[reply.id] = reply;
    }

    for (final reply in replies) {
      final parentId = reply.parentId ?? root.id;

      childrenMap.putIfAbsent(parentId, () => []);
      childrenMap[parentId]!.add(reply);
    }

    for (final children in childrenMap.values) {
      children.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    return ThreadStructure(
      rootNote: root,
      childrenMap: childrenMap,
      notesMap: notesMap,
      totalReplies: replies.length,
    );
  }

  Future<void> _loadUsersForThread(List<NoteModel> notes) async {
    if (notes.isEmpty || _userRepository == null) return;

    final userRepository = _userRepository!;

    try {
      final allNpubs = <String>{};
      final noteAuthorMap = <String, List<NoteModel>>{};
      final noteReposterMap = <String, List<NoteModel>>{};
      
      for (final note in notes) {
        if (note.authorUser == null) {
          allNpubs.add(note.author);
          noteAuthorMap.putIfAbsent(note.author, () => []).add(note);
        }
        
        if (note.isRepost && note.repostedBy != null && note.reposterUser == null) {
          allNpubs.add(note.repostedBy!);
          noteReposterMap.putIfAbsent(note.repostedBy!, () => []).add(note);
        }
      }

      if (allNpubs.isEmpty) return;

      final cachedUsers = <String, UserModel>{};
      final npubsToLoad = <String>[];

      final cacheFutures = allNpubs.map((npub) async {
        try {
          final cachedUser = await userRepository.getCachedUser(npub);
          if (cachedUser != null && cachedUser.name.isNotEmpty && cachedUser.name != cachedUser.npub.substring(0, 8)) {
            cachedUsers[npub] = cachedUser;
          } else {
            npubsToLoad.add(npub);
          }
        } catch (e) {
          debugPrint('[ThreadRepository] Error getting cached user $npub: $e');
          npubsToLoad.add(npub);
        }
      });

      await Future.wait(cacheFutures);

      for (final entry in cachedUsers.entries) {
        final npub = entry.key;
        final user = entry.value;
        
        if (noteAuthorMap.containsKey(npub)) {
          for (final note in noteAuthorMap[npub]!) {
            if (note.authorUser == null) {
              note.authorUser = user;
            }
          }
        }
        
        if (noteReposterMap.containsKey(npub)) {
          for (final note in noteReposterMap[npub]!) {
            if (note.reposterUser == null) {
              note.reposterUser = user;
            }
          }
        }
      }

      if (npubsToLoad.isNotEmpty) {
        final results = await userRepository.getUserProfiles(
          npubsToLoad,
          priority: FetchPriority.urgent,
        );

        for (final entry in results.entries) {
          final npub = entry.key;
          entry.value.fold(
            (user) {
              if (noteAuthorMap.containsKey(npub)) {
                for (final note in noteAuthorMap[npub]!) {
                  if (note.authorUser == null) {
                    note.authorUser = user;
                  }
                }
              }
              
              if (noteReposterMap.containsKey(npub)) {
                for (final note in noteReposterMap[npub]!) {
                  if (note.reposterUser == null) {
                    note.reposterUser = user;
                  }
                }
              }
            },
            (error) {
              debugPrint('[ThreadRepository] Failed to load user $npub: $error');
            },
          );
        }
      }
    } catch (e) {
      debugPrint('[ThreadRepository] Error loading users for thread: $e');
    }
  }
}

class ThreadData {
  final NoteModel rootNote;
  final List<NoteModel> replies;
  final ThreadStructure structure;

  ThreadData({
    required this.rootNote,
    required this.replies,
    required this.structure,
  });
}

class ThreadStructure {
  final NoteModel rootNote;
  final Map<String, List<NoteModel>> childrenMap;
  final Map<String, NoteModel> notesMap;
  final int totalReplies;

  ThreadStructure({
    required this.rootNote,
    required this.childrenMap,
    required this.notesMap,
    required this.totalReplies,
  });

  List<NoteModel> getChildren(String noteId) {
    return childrenMap[noteId] ?? [];
  }

  NoteModel? getNote(String noteId) {
    return notesMap[noteId];
  }

  int getDepth(String noteId) {
    int depth = 0;
    NoteModel? current = notesMap[noteId];

    while (current != null && current.parentId != null) {
      depth++;
      current = notesMap[current.parentId!];
    }

    return depth;
  }

  bool hasChildren(String noteId) {
    return childrenMap.containsKey(noteId) && childrenMap[noteId]!.isNotEmpty;
  }

  List<NoteModel> getAllNotes() {
    return notesMap.values.toList();
  }
}

