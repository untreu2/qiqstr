import 'dart:async';
import '../../core/base/result.dart';
import 'logging_service.dart';
import '../repositories/note_repository.dart';
import '../repositories/user_repository.dart';
import 'user_batch_fetcher.dart';

enum FeedType {
  feed,
  profile,
  hashtag,
  article,
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
  final bool cacheOnly;

  const FeedLoadParams({
    required this.type,
    this.currentUserNpub,
    this.targetUserNpub,
    this.hashtag,
    this.limit = 50,
    this.until,
    this.since,
    this.skipCache = false,
    this.cacheOnly = false,
  });
}

class FeedLoadResult {
  final List<Map<String, dynamic>> notes;
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
  final LoggingService _logger;

  FeedLoaderService({
    required NoteRepository noteRepository,
    required UserRepository userRepository,
    LoggingService? logger,
  })  : _noteRepository = noteRepository,
        _userRepository = userRepository,
        _logger = logger ?? LoggingService.instance;

  Future<FeedLoadResult> loadFeed(FeedLoadParams params) async {
    try {
      Result<List<Map<String, dynamic>>> result;

      switch (params.type) {
        case FeedType.feed:
          if (params.currentUserNpub == null ||
              params.currentUserNpub!.isEmpty) {
            return const FeedLoadResult(
                notes: [], error: 'Current user npub is required for feed');
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
            return const FeedLoadResult(
                notes: [],
                error: 'Target user npub is required for profile feed');
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
            return const FeedLoadResult(
                notes: [], error: 'Hashtag is required for hashtag feed');
          }
          result = await _noteRepository.getHashtagNotes(
            hashtag: params.hashtag!,
            limit: params.limit,
            until: params.until,
            since: params.since,
          );
          break;

        case FeedType.article:
          if (params.currentUserNpub == null || params.currentUserNpub!.isEmpty) {
            return const FeedLoadResult(
                notes: [], error: 'Current user npub is required for article feed');
          }
          result = await _noteRepository.getArticlesFromFollowList(
            currentUserNpub: params.currentUserNpub!,
            limit: params.limit,
            until: params.until,
            since: params.since,
            cacheOnly: params.cacheOnly,
          );
          break;
      }

      return result.fold(
        (notes) {
          if (notes.isEmpty) {
            return const FeedLoadResult(notes: []);
          }

          final processedNotes = _processNotes(notes);

          _fetchInteractionsForNotes(processedNotes);

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
      _logger.error('Failed to load feed', 'FeedLoaderService', e);
      return FeedLoadResult(
          notes: [], error: 'Failed to load feed: ${e.toString()}');
    }
  }

  void _fetchInteractionsForNotes(List<Map<String, dynamic>> notes) {
    try {
      final noteIds = notes
          .map((note) {
            final isRepost = note['isRepost'] as bool? ?? false;
            final rootId = note['rootId'] as String?;
            if (isRepost && rootId != null && rootId.isNotEmpty) {
              return rootId;
            }
            return note['id'] as String? ?? '';
          })
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (noteIds.isEmpty) return;

      _noteRepository.nostrDataService
          .fetchInteractionsForNotesBatchWithEOSE(noteIds);
    } catch (e) {
      _logger.error(
          'Error fetching interactions for notes', 'FeedLoaderService', e);
    }
  }

  List<Map<String, dynamic>> _processNotes(List<Map<String, dynamic>> notes) {
    if (notes.isEmpty) return notes;

    final seenIds = <String>{};
    final deduplicatedNotes = <Map<String, dynamic>>[];

    for (final note in notes) {
      final noteId = note['id'] as String? ?? '';
      if (noteId.isNotEmpty && seenIds.add(noteId)) {
        deduplicatedNotes.add(note);
      }
    }

    return deduplicatedNotes;
  }

  List<Map<String, dynamic>> sortNotes(
      List<Map<String, dynamic>> notes, FeedSortMode sortMode) {
    if (notes.length <= 1) return notes;

    final sortedNotes = List<Map<String, dynamic>>.from(notes);

    if (sortMode == FeedSortMode.mostInteracted) {
      final scoreCache = <String, int>{};
      int getScore(Map<String, dynamic> note) {
        final noteId = note['id'] as String? ?? '';
        if (noteId.isEmpty) return 0;
        return scoreCache.putIfAbsent(
          noteId,
          () {
            final reactionCount = note['reactionCount'] as int? ?? 0;
            final repostCount = note['repostCount'] as int? ?? 0;
            final replyCount = note['replyCount'] as int? ?? 0;
            final zapAmount = note['zapAmount'] as int? ?? 0;
            return reactionCount +
                repostCount +
                replyCount +
                (zapAmount ~/ 1000);
          },
        );
      }

      sortedNotes.sort((a, b) {
        final scoreA = getScore(a);
        final scoreB = getScore(b);

        if (scoreA == scoreB) {
          final aTime = a['timestamp'] as DateTime? ?? DateTime(2000);
          final bTime = b['timestamp'] as DateTime? ?? DateTime(2000);
          return bTime.compareTo(aTime);
        }

        return scoreB.compareTo(scoreA);
      });
    } else {
      sortedNotes.sort((a, b) {
        final aTime = a['timestamp'] as DateTime? ?? DateTime(2000);
        final bTime = b['timestamp'] as DateTime? ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });
    }

    return sortedNotes;
  }

  List<Map<String, dynamic>> filterProfileNotes(
      List<Map<String, dynamic>> notes) {
    return notes.where((note) {
      final isReply = note['isReply'] as bool? ?? false;
      final isRepost = note['isRepost'] as bool? ?? false;
      if (!isReply && !isRepost) {
        return true;
      }

      if (isRepost) {
        return true;
      }

      if (isReply && !isRepost) {
        return false;
      }

      return true;
    }).toList();
  }

  Set<String> _extractAuthorIds(List<Map<String, dynamic>> notes) {
    final authorIds = <String>{};
    for (final note in notes) {
      final author = note['author'] as String? ?? '';
      if (author.isNotEmpty) {
        authorIds.add(author);
      }
      final repostedBy = note['repostedBy'] as String?;
      if (repostedBy != null && repostedBy.isNotEmpty) {
        authorIds.add(repostedBy);
      }
    }
    return authorIds;
  }

  Future<void> preloadCachedUserProfilesSync(
    List<Map<String, dynamic>> notes,
    Map<String, Map<String, dynamic>> profiles,
    Function(Map<String, Map<String, dynamic>>) onProfilesUpdated,
  ) async {
    try {
      final authorIds = _extractAuthorIds(notes);
      final missingIds =
          authorIds.where((id) => !profiles.containsKey(id)).toList();

      if (missingIds.isEmpty) {
        return;
      }

      bool hasUpdates = false;
      for (final authorId in missingIds) {
        final cachedUser = await _userRepository.getCachedUser(authorId);
        if (cachedUser != null) {
          profiles[authorId] = cachedUser;
          hasUpdates = true;
        }
      }

      if (hasUpdates) {
        onProfilesUpdated(profiles);
      }
    } catch (e) {
      _logger.error(
          'Error preloading cached user profiles', 'FeedLoaderService', e);
    }
  }

  Future<void> preloadCachedUserProfiles(
    List<Map<String, dynamic>> notes,
    Map<String, Map<String, dynamic>> profiles,
    Function(Map<String, Map<String, dynamic>>) onProfilesUpdated,
  ) async {
    try {
      final authorIds = _extractAuthorIds(notes);
      final missingAuthorIds =
          authorIds.where((id) => !profiles.containsKey(id)).toList();

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
      _logger.error(
          'Error preloading cached user profiles', 'FeedLoaderService', e);
    }
  }

  void loadProfilesAndInteractionsForNotes(
    List<Map<String, dynamic>> notes,
    Map<String, Map<String, dynamic>> profiles,
    Function(Map<String, Map<String, dynamic>>) onProfilesUpdated,
  ) {
    _fetchInteractionsForNotes(notes);
    preloadCachedUserProfilesSync(notes, profiles, onProfilesUpdated);
    loadUserProfilesForNotes(notes, profiles, onProfilesUpdated)
        .catchError((e) {
      _logger.error('Error loading user profiles', 'FeedLoaderService', e);
    });
  }

  Future<void> loadUserProfilesForNotes(
    List<Map<String, dynamic>> notes,
    Map<String, Map<String, dynamic>> profiles,
    Function(Map<String, Map<String, dynamic>>) onProfilesUpdated,
  ) async {
    try {
      final authorIds = _extractAuthorIds(notes);
      final missingAuthorIds = <String>[];

      bool hasCacheUpdates = false;
      for (final id in authorIds) {
        final cachedProfile = profiles[id];
        final profileImage = cachedProfile?['profileImage'] as String? ?? '';
        if (cachedProfile == null || profileImage.isEmpty) {
          final cached = await _userRepository.getCachedUser(id);
          if (cached != null) {
            final cachedProfileImage = cached['profileImage'] as String? ?? '';
            if (cachedProfileImage.isNotEmpty) {
              profiles[id] = cached;
              hasCacheUpdates = true;
            } else {
              missingAuthorIds.add(id);
            }
          } else {
            missingAuthorIds.add(id);
          }
        }
      }

      if (hasCacheUpdates) {
        onProfilesUpdated(profiles);
      }

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
            final existingProfile = profiles[entry.key];
            final existingImage =
                existingProfile?['profileImage'] as String? ?? '';
            if (!profiles.containsKey(entry.key) || existingImage.isEmpty) {
              profiles[entry.key] = user;
              hasUpdates = true;
            }
          },
          (error) {
            if (!profiles.containsKey(entry.key)) {
              profiles[entry.key] = <String, dynamic>{
                'pubkeyHex': entry.key,
                'name': entry.key.length > 8
                    ? entry.key.substring(0, 8)
                    : entry.key,
                'about': '',
                'profileImage': '',
                'banner': '',
                'website': '',
                'nip05': '',
                'lud16': '',
                'updatedAt': DateTime.now(),
                'nip05Verified': false,
              };
              hasUpdates = true;
            }
          },
        );
      }

      if (hasUpdates) {
        onProfilesUpdated(profiles);
      }
    } catch (e) {
      _logger.error('Error loading user profiles', 'FeedLoaderService', e);
    }
  }

  Stream<List<Map<String, dynamic>>> getNotesStream(FeedType type) {
    switch (type) {
      case FeedType.feed:
        return _noteRepository.realTimeNotesStream;
      case FeedType.profile:
      case FeedType.hashtag:
      case FeedType.article:
        return _noteRepository.notesStream;
    }
  }

  List<Map<String, dynamic>> mergeNotesWithUpdates(
    List<Map<String, dynamic>> currentNotes,
    List<Map<String, dynamic>> updatedNotes,
    FeedSortMode sortMode,
  ) {
    if (currentNotes.isEmpty) {
      return sortNotes(updatedNotes, sortMode);
    }

    if (updatedNotes.isEmpty) {
      return currentNotes;
    }

    if (updatedNotes.length < currentNotes.length * 0.3) {
      final currentNoteIds = currentNotes
          .map((n) => n['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final newNotes = updatedNotes.where((n) {
        final noteId = n['id'] as String? ?? '';
        return noteId.isNotEmpty && !currentNoteIds.contains(noteId);
      }).toList();

      if (newNotes.isNotEmpty) {
        final updatedNoteMap = <String, Map<String, dynamic>>{};
        for (var n in updatedNotes) {
          final noteId = n['id'] as String? ?? '';
          if (noteId.isNotEmpty) {
            updatedNoteMap[noteId] = n;
          }
        }
        final mergedNotes = currentNotes.map((note) {
          final noteId = note['id'] as String? ?? '';
          return updatedNoteMap[noteId] ?? note;
        }).toList();
        mergedNotes.addAll(newNotes);
        return sortNotes(mergedNotes, sortMode);
      }

      final updatedNoteMap = <String, Map<String, dynamic>>{};
      for (var n in updatedNotes) {
        final noteId = n['id'] as String? ?? '';
        if (noteId.isNotEmpty) {
          updatedNoteMap[noteId] = n;
        }
      }
      final mergedNotes = currentNotes.map((note) {
        final noteId = note['id'] as String? ?? '';
        return updatedNoteMap[noteId] ?? note;
      }).toList();
      return mergedNotes;
    }

    final noteIds = updatedNotes
        .map((n) => n['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final currentNoteIds = currentNotes
        .map((n) => n['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    final removedNoteIds = currentNoteIds.difference(noteIds);
    final updatedNoteList = updatedNotes.where((n) {
      final noteId = n['id'] as String? ?? '';
      return noteId.isNotEmpty && currentNoteIds.contains(noteId);
    }).toList();
    final newerNotes = updatedNotes.where((n) {
      final noteId = n['id'] as String? ?? '';
      return noteId.isNotEmpty && !currentNoteIds.contains(noteId);
    }).toList();

    final hasRemovals = removedNoteIds.isNotEmpty;
    final hasUpdates = updatedNoteList.isNotEmpty;
    final hasNewNotes = newerNotes.isNotEmpty;

    if (hasRemovals && noteIds.length >= currentNoteIds.length * 0.7) {
      final filteredCurrentNotes = List<Map<String, dynamic>>.from(
        currentNotes.where((n) {
          final noteId = n['id'] as String? ?? '';
          return noteId.isNotEmpty && !removedNoteIds.contains(noteId);
        }),
      );

      for (final updatedNote in updatedNoteList) {
        final updatedNoteId = updatedNote['id'] as String? ?? '';
        if (updatedNoteId.isEmpty) continue;
        final index = filteredCurrentNotes
            .indexWhere((n) => (n['id'] as String? ?? '') == updatedNoteId);
        if (index != -1) {
          filteredCurrentNotes[index] = updatedNote;
        }
      }

      if (newerNotes.isNotEmpty) {
        final latestTimestamp = filteredCurrentNotes.isNotEmpty
            ? (filteredCurrentNotes.first['timestamp'] as DateTime? ??
                DateTime.now())
            : DateTime.now();
        final timestampNewerNotes = List<Map<String, dynamic>>.from(
          newerNotes.where((n) {
            final noteTime = n['timestamp'] as DateTime?;
            return noteTime != null && noteTime.isAfter(latestTimestamp);
          }),
        );

        if (timestampNewerNotes.isNotEmpty) {
          filteredCurrentNotes.addAll(timestampNewerNotes);
        }
      }

      return sortNotes(filteredCurrentNotes, sortMode);
    }

    if (hasUpdates || hasNewNotes) {
      final filteredCurrentNotes =
          List<Map<String, dynamic>>.from(currentNotes);

      if (hasUpdates) {
        for (final updatedNote in updatedNoteList) {
          final updatedNoteId = updatedNote['id'] as String? ?? '';
          if (updatedNoteId.isEmpty) continue;
          final index = filteredCurrentNotes
              .indexWhere((n) => (n['id'] as String? ?? '') == updatedNoteId);
          if (index != -1) {
            filteredCurrentNotes[index] = updatedNote;
          }
        }
      }

      final currentNoteIdsSet = filteredCurrentNotes
          .map((n) => n['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final notesToAdd = newerNotes.where((n) {
        final noteId = n['id'] as String? ?? '';
        return noteId.isNotEmpty && !currentNoteIdsSet.contains(noteId);
      }).toList();

      if (notesToAdd.isNotEmpty) {
        filteredCurrentNotes.addAll(notesToAdd);
        return sortNotes(filteredCurrentNotes, sortMode);
      }

      if (hasUpdates) {
        return sortNotes(filteredCurrentNotes, sortMode);
      }
    }

    return currentNotes;
  }

  List<Map<String, dynamic>> mergeProfileNotesWithUpdates(
    List<Map<String, dynamic>> currentNotes,
    List<Map<String, dynamic>> updatedNotes,
  ) {
    if (currentNotes.isEmpty) {
      return filterProfileNotes(updatedNotes);
    }

    final updatedNoteIds = updatedNotes
        .map((n) => n['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final currentNoteIds = currentNotes
        .map((n) => n['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    final removedNoteIds = currentNoteIds.difference(updatedNoteIds);

    if (removedNoteIds.isNotEmpty) {
      final filteredNotes = currentNotes.where((note) {
        final noteId = note['id'] as String? ?? '';
        return noteId.isNotEmpty && !removedNoteIds.contains(noteId);
      }).toList();

      for (final updatedNote in updatedNotes) {
        final updatedNoteId = updatedNote['id'] as String? ?? '';
        if (updatedNoteId.isNotEmpty &&
            currentNoteIds.contains(updatedNoteId)) {
          final index = filteredNotes
              .indexWhere((n) => (n['id'] as String? ?? '') == updatedNoteId);
          if (index != -1) {
            filteredNotes[index] = updatedNote;
          }
        }
      }

      return filterProfileNotes(filteredNotes);
    }

    bool hasUpdates = false;
    for (final updatedNote in updatedNotes) {
      final updatedNoteId = updatedNote['id'] as String? ?? '';
      if (updatedNoteId.isNotEmpty && currentNoteIds.contains(updatedNoteId)) {
        final index = currentNotes
            .indexWhere((n) => (n['id'] as String? ?? '') == updatedNoteId);
        if (index != -1) {
          final existingNote = currentNotes[index];
          final existingReactionCount =
              existingNote['reactionCount'] as int? ?? 0;
          final existingRepostCount = existingNote['repostCount'] as int? ?? 0;
          final existingReplyCount = existingNote['replyCount'] as int? ?? 0;
          final existingZapAmount = existingNote['zapAmount'] as int? ?? 0;
          final updatedReactionCount =
              updatedNote['reactionCount'] as int? ?? 0;
          final updatedRepostCount = updatedNote['repostCount'] as int? ?? 0;
          final updatedReplyCount = updatedNote['replyCount'] as int? ?? 0;
          final updatedZapAmount = updatedNote['zapAmount'] as int? ?? 0;
          if (existingReactionCount != updatedReactionCount ||
              existingRepostCount != updatedRepostCount ||
              existingReplyCount != updatedReplyCount ||
              existingZapAmount != updatedZapAmount) {
            hasUpdates = true;
            break;
          }
        }
      }
    }

    if (hasUpdates) {
      final updatedNotesList = List<Map<String, dynamic>>.from(currentNotes);
      for (final updatedNote in updatedNotes) {
        final updatedNoteId = updatedNote['id'] as String? ?? '';
        if (updatedNoteId.isNotEmpty &&
            currentNoteIds.contains(updatedNoteId)) {
          final index = updatedNotesList
              .indexWhere((n) => (n['id'] as String? ?? '') == updatedNoteId);
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
