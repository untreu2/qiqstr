import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/base/result.dart';
import '../../models/note_model.dart';
import '../../models/user_model.dart';
import '../repositories/note_repository.dart';
import '../repositories/note_repository_compat.dart';
import '../repositories/user_repository.dart';
import 'user_batch_fetcher.dart';

enum FeedType {
  feed,
  profile,
  hashtag,
}

enum FeedSortMode {
  latest,
  mostInteracted,
}

class FeedLoadParams {
  final FeedType type;
  final String? currentUserNpub;
  final String? targetUserNpub;
  final String? hashtag;
  final int limit;
  final DateTime? until;
  final DateTime? since;
  final bool skipCache;

  const FeedLoadParams({
    required this.type,
    this.currentUserNpub,
    this.targetUserNpub,
    this.hashtag,
    this.limit = 50,
    this.until,
    this.since,
    this.skipCache = false,
  });
}

class FeedLoadResult {
  final List<NoteModel> notes;
  final bool hasMore;
  final String? error;

  const FeedLoadResult({
    required this.notes,
    this.hasMore = false,
    this.error,
  });

  bool get isSuccess => error == null;
}

class FeedLoaderService {
  final NoteRepository _noteRepository;
  final UserRepository _userRepository;

  FeedLoaderService({
    required NoteRepository noteRepository,
    required UserRepository userRepository,
  })  : _noteRepository = noteRepository,
        _userRepository = userRepository;

  Future<FeedLoadResult> loadFeed(FeedLoadParams params) async {
    try {
      Result<List<NoteModel>> result;

      switch (params.type) {
        case FeedType.feed:
          if (params.currentUserNpub == null || params.currentUserNpub!.isEmpty) {
            return const FeedLoadResult(notes: [], error: 'Current user npub is required for feed');
          }
          result = await _noteRepository.getFeedNotesFromFollowList(
            currentUserNpub: params.currentUserNpub!,
            limit: params.limit,
            until: params.until,
            since: params.since,
            skipCache: params.skipCache,
          );
          break;

        case FeedType.profile:
          if (params.targetUserNpub == null || params.targetUserNpub!.isEmpty) {
            return const FeedLoadResult(notes: [], error: 'Target user npub is required for profile feed');
          }
          result = await _noteRepository.getProfileNotes(
            authorNpub: params.targetUserNpub!,
            limit: params.limit,
            until: params.until,
            since: params.since,
            skipCache: params.skipCache,
          );
          break;

        case FeedType.hashtag:
          if (params.hashtag == null || params.hashtag!.isEmpty) {
            return const FeedLoadResult(notes: [], error: 'Hashtag is required for hashtag feed');
          }
          result = await _noteRepository.getHashtagNotes(
            hashtag: params.hashtag!,
            limit: params.limit,
            until: params.until,
            since: params.since,
          );
          break;
      }

      return result.fold(
        (notes) {
          if (notes.isEmpty) {
            return const FeedLoadResult(notes: []);
          }

          final processedNotes = _processNotes(notes);
          return FeedLoadResult(
            notes: processedNotes,
            hasMore: notes.length >= params.limit,
          );
        },
        (error) => FeedLoadResult(notes: [], error: error),
      );
    } on TimeoutException {
      final cachedNotes = _noteRepository.currentNotes;
      if (cachedNotes.isNotEmpty) {
        final processedNotes = _processNotes(cachedNotes);
        return FeedLoadResult(notes: processedNotes);
      }
      return const FeedLoadResult(notes: []);
    } catch (e) {
      return FeedLoadResult(notes: [], error: 'Failed to load feed: ${e.toString()}');
    }
  }

  List<NoteModel> _processNotes(List<NoteModel> notes) {
    final seenIds = <String>{};
    final deduplicatedNotes = <NoteModel>[];

    for (final note in notes) {
      if (!seenIds.contains(note.id)) {
        seenIds.add(note.id);
        deduplicatedNotes.add(note);
      }
    }

    return deduplicatedNotes;
  }

  List<NoteModel> sortNotes(List<NoteModel> notes, FeedSortMode sortMode) {
    if (notes.length <= 1) return notes;

    final sortedNotes = List<NoteModel>.from(notes);

    if (sortMode == FeedSortMode.mostInteracted) {
      final scoreCache = <String, int>{};
      int getScore(NoteModel note) {
        return scoreCache.putIfAbsent(
          note.id,
          () => note.reactionCount + note.repostCount + note.replyCount + (note.zapAmount ~/ 1000),
        );
      }

      sortedNotes.sort((a, b) {
        final scoreA = getScore(a);
        final scoreB = getScore(b);

        if (scoreA == scoreB) {
          return b.timestamp.compareTo(a.timestamp);
        }

        return scoreB.compareTo(scoreA);
      });
    } else {
      sortedNotes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }

    return sortedNotes;
  }

  List<NoteModel> filterProfileNotes(List<NoteModel> notes) {
    return notes.where((note) {
      if (!note.isReply && !note.isRepost) {
        return true;
      }

      if (note.isRepost) {
        return true;
      }

      if (note.isReply && !note.isRepost) {
        return false;
      }

      return true;
    }).toList();
  }

  Set<String> _extractAuthorIds(List<NoteModel> notes) {
    final authorIds = <String>{};
    for (final note in notes) {
      authorIds.add(note.author);
      if (note.repostedBy != null) {
        authorIds.add(note.repostedBy!);
      }
    }
    return authorIds;
  }

  void preloadCachedUserProfilesSync(
    List<NoteModel> notes,
    Map<String, UserModel> profiles,
    Function(Map<String, UserModel>) onProfilesUpdated,
  ) {
    try {
      final authorIds = _extractAuthorIds(notes);
      final missingIds = authorIds.where((id) => !profiles.containsKey(id)).toList();

      if (missingIds.isEmpty) {
        return;
      }

      bool hasUpdates = false;
      for (final authorId in missingIds) {
        final cachedUser = _userRepository.getCachedUserSync(authorId);
        if (cachedUser != null) {
          profiles[authorId] = cachedUser;
          hasUpdates = true;
        }
      }

      if (hasUpdates) {
        onProfilesUpdated(profiles);
      }
    } catch (e) {
      debugPrint('[FeedLoaderService] Error preloading cached user profiles: $e');
    }
  }

  Future<void> preloadCachedUserProfiles(
    List<NoteModel> notes,
    Map<String, UserModel> profiles,
    Function(Map<String, UserModel>) onProfilesUpdated,
  ) async {
    try {
      final authorIds = _extractAuthorIds(notes);
      final missingAuthorIds = authorIds.where((id) => !profiles.containsKey(id)).toList();

      if (missingAuthorIds.isEmpty) {
        return;
      }

      final cachedProfiles = await _userRepository.getUserProfiles(
        missingAuthorIds,
        priority: FetchPriority.urgent,
      );

      bool hasUpdates = false;
      for (final entry in cachedProfiles.entries) {
        entry.value.fold(
          (user) {
            profiles[entry.key] = user;
            hasUpdates = true;
          },
          (_) {},
        );
      }

      if (hasUpdates) {
        onProfilesUpdated(profiles);
      }
    } catch (e) {
      debugPrint('[FeedLoaderService] Error preloading cached user profiles: $e');
    }
  }

  Future<void> loadUserProfilesForNotes(
    List<NoteModel> notes,
    Map<String, UserModel> profiles,
    Function(Map<String, UserModel>) onProfilesUpdated,
  ) async {
    try {
      final authorIds = _extractAuthorIds(notes);
      final missingAuthorIds = authorIds.where((id) {
        final cachedProfile = profiles[id];
        return cachedProfile == null || cachedProfile.profileImage.isEmpty;
      }).toList();

      if (missingAuthorIds.isEmpty) {
        return;
      }

      final fetchedProfiles = await _userRepository.getUserProfiles(
        missingAuthorIds,
        priority: FetchPriority.urgent,
      );

      bool hasUpdates = false;
      for (final entry in fetchedProfiles.entries) {
        entry.value.fold(
          (user) {
            if (!profiles.containsKey(entry.key) || profiles[entry.key]!.profileImage.isEmpty) {
              profiles[entry.key] = user;
              hasUpdates = true;
            }
          },
          (error) {
            if (!profiles.containsKey(entry.key)) {
              profiles[entry.key] = UserModel(
                pubkeyHex: entry.key,
                name: entry.key.length > 8 ? entry.key.substring(0, 8) : entry.key,
                about: '',
                profileImage: '',
                banner: '',
                website: '',
                nip05: '',
                lud16: '',
                updatedAt: DateTime.now(),
                nip05Verified: false,
              );
              hasUpdates = true;
            }
          },
        );
      }

      if (hasUpdates) {
        onProfilesUpdated(profiles);
      }
    } catch (e) {
      debugPrint('[FeedLoaderService] Error loading user profiles: $e');
    }
  }

  Stream<List<NoteModel>> getNotesStream(FeedType type) {
    switch (type) {
      case FeedType.feed:
        return _noteRepository.realTimeNotesStream;
      case FeedType.profile:
      case FeedType.hashtag:
        return _noteRepository.notesStream;
    }
  }

  List<NoteModel> mergeNotesWithUpdates(
    List<NoteModel> currentNotes,
    List<NoteModel> updatedNotes,
    FeedSortMode sortMode,
  ) {
    if (currentNotes.isEmpty) {
      return sortNotes(updatedNotes, sortMode);
    }

    final noteIds = updatedNotes.map((n) => n.id).toSet();
    final currentNoteIds = currentNotes.map((n) => n.id).toSet();

    final removedNoteIds = currentNoteIds.difference(noteIds);
    final updatedNoteList = updatedNotes.where((n) => currentNoteIds.contains(n.id)).toList();
    final newerNotes = updatedNotes.where((n) => !currentNoteIds.contains(n.id)).toList();

    final hasRemovals = removedNoteIds.isNotEmpty;
    final hasUpdates = updatedNoteList.isNotEmpty;
    final hasNewNotes = newerNotes.isNotEmpty;

    if (hasRemovals) {
      final filteredCurrentNotes = List<NoteModel>.from(
        currentNotes.where((n) => !removedNoteIds.contains(n.id)),
      );

      for (final updatedNote in updatedNoteList) {
        final index = filteredCurrentNotes.indexWhere((n) => n.id == updatedNote.id);
        if (index != -1) {
          filteredCurrentNotes[index] = updatedNote;
        }
      }

      if (newerNotes.isNotEmpty) {
        final latestTimestamp = filteredCurrentNotes.isNotEmpty ? filteredCurrentNotes.first.timestamp : DateTime.now();
        final timestampNewerNotes = List<NoteModel>.from(
          newerNotes.where((n) => n.timestamp.isAfter(latestTimestamp)),
        );

        if (timestampNewerNotes.isNotEmpty) {
          filteredCurrentNotes.addAll(timestampNewerNotes);
        }
      }

      return sortNotes(filteredCurrentNotes, sortMode);
    }

    if (hasUpdates || hasNewNotes) {
      final filteredCurrentNotes = List<NoteModel>.from(currentNotes);

      if (hasUpdates) {
        for (final updatedNote in updatedNoteList) {
          final index = filteredCurrentNotes.indexWhere((n) => n.id == updatedNote.id);
          if (index != -1) {
            filteredCurrentNotes[index] = updatedNote;
          }
        }
      }

      final latestTimestamp = filteredCurrentNotes.isNotEmpty ? filteredCurrentNotes.first.timestamp : DateTime.now();
      final timestampNewerNotes = <NoteModel>[];
      for (final note in updatedNotes) {
        if (note.timestamp.isAfter(latestTimestamp)) {
          timestampNewerNotes.add(note);
        }
      }

      if (timestampNewerNotes.isEmpty) {
        if (hasUpdates) {
          return sortNotes(filteredCurrentNotes, sortMode);
        }
        return currentNotes;
      }

      final userNotes = <NoteModel>[];
      final otherNotes = <NoteModel>[];

      for (final note in timestampNewerNotes) {
        final currentUserNpub = _noteRepository.nostrDataService.currentUserNpub;
        if (note.author == currentUserNpub) {
          userNotes.add(note);
        } else {
          otherNotes.add(note);
        }
      }

      if (userNotes.isNotEmpty) {
        final allNotes = [...userNotes, ...filteredCurrentNotes];
        return sortNotes(allNotes, sortMode);
      } else if (hasUpdates) {
        return sortNotes(filteredCurrentNotes, sortMode);
      }
    }

    return currentNotes;
  }

  List<NoteModel> mergeProfileNotesWithUpdates(
    List<NoteModel> currentNotes,
    List<NoteModel> updatedNotes,
  ) {
    if (currentNotes.isEmpty) {
      return filterProfileNotes(updatedNotes);
    }

    final updatedNoteIds = updatedNotes.map((n) => n.id).toSet();
    final currentNoteIds = currentNotes.map((n) => n.id).toSet();

    final removedNoteIds = currentNoteIds.difference(updatedNoteIds);

    if (removedNoteIds.isNotEmpty) {
      final filteredNotes = currentNotes.where((note) => !removedNoteIds.contains(note.id)).toList();

      for (final updatedNote in updatedNotes) {
        if (currentNoteIds.contains(updatedNote.id)) {
          final index = filteredNotes.indexWhere((n) => n.id == updatedNote.id);
          if (index != -1) {
            filteredNotes[index] = updatedNote;
          }
        }
      }

      return filterProfileNotes(filteredNotes);
    }

    bool hasUpdates = false;
    for (final updatedNote in updatedNotes) {
      if (currentNoteIds.contains(updatedNote.id)) {
        final index = currentNotes.indexWhere((n) => n.id == updatedNote.id);
        if (index != -1) {
          final existingNote = currentNotes[index];
          if (existingNote.reactionCount != updatedNote.reactionCount ||
              existingNote.repostCount != updatedNote.repostCount ||
              existingNote.replyCount != updatedNote.replyCount ||
              existingNote.zapAmount != updatedNote.zapAmount) {
            hasUpdates = true;
            break;
          }
        }
      }
    }

    if (hasUpdates) {
      final updatedNotesList = List<NoteModel>.from(currentNotes);
      for (final updatedNote in updatedNotes) {
        if (currentNoteIds.contains(updatedNote.id)) {
          final index = updatedNotesList.indexWhere((n) => n.id == updatedNote.id);
          if (index != -1) {
            updatedNotesList[index] = updatedNote;
          }
        }
      }

      return filterProfileNotes(updatedNotesList);
    }

    return currentNotes;
  }
}
