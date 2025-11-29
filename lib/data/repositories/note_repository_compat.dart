import 'dart:async';
import '../../core/base/result.dart';
import '../../models/note_model.dart';
import '../filters/feed_filters.dart';
import '../services/follow_cache_service.dart';
import 'note_repository.dart';

extension NoteRepositoryCompat on NoteRepository {
  Future<Result<List<NoteModel>>> _getFeedNotesForAuthors({
    required BaseFeedFilter filter,
    required List<String> authorNpubs,
    int limit = 50,
    DateTime? until,
    DateTime? since,
    bool isProfileMode = false,
    bool skipCache = false,
  }) async {
    try {
      if (!skipCache) {
        final cachedResult = await getFilteredNotes(filter);
        List<NoteModel>? cachedNotes;
        
        if (cachedResult.isSuccess && cachedResult.data!.isNotEmpty) {
          cachedNotes = cachedResult.data!;
          
          if (until != null) {
            cachedNotes = cachedNotes.where((note) {
              final noteTime = note.isRepost ? (note.repostTimestamp ?? note.timestamp) : note.timestamp;
              return noteTime.isBefore(until);
            }).toList();
          }
        }
        
        if (cachedNotes != null && cachedNotes.isNotEmpty) {
          fetchNotesFromRelays(
            authorNpubs: authorNpubs,
            limit: limit,
            until: until,
            since: since,
            isProfileMode: isProfileMode,
          ).then((_) {}).catchError((e) {
            logger.error('Error fetching notes in background', 'NoteRepository', e);
          });
          
          return Result.success(cachedNotes);
        }
      }
      
      await fetchNotesFromRelays(
        authorNpubs: authorNpubs,
        limit: limit,
        until: until,
        since: since,
        isProfileMode: isProfileMode,
      );
      
      if (skipCache && isProfileMode) {
        await Future.delayed(const Duration(milliseconds: 1500));
      }
      
      final result = await getFilteredNotes(filter);
      
      if (result.isSuccess && until != null && result.data!.isNotEmpty) {
        final filteredNotes = result.data!.where((note) {
          final noteTime = note.isRepost ? (note.repostTimestamp ?? note.timestamp) : note.timestamp;
          return noteTime.isBefore(until);
        }).toList();
        return Result.success(filteredNotes);
      }
      
      return result;
    } catch (e) {
      logger.error('Exception in _getFeedNotesForAuthors', 'NoteRepository', e);
      return Result.error('Failed to get feed notes: ${e.toString()}');
    }
  }

  Future<Result<List<NoteModel>>> getFeedNotesFromFollowList({
    required String currentUserNpub,
    int limit = 50,
    DateTime? until,
    DateTime? since,
    bool skipCache = false,
  }) async {
    try {
      final nostrService = nostrDataService;
      final currentUserHex = nostrService.authService.npubToHex(currentUserNpub) ?? currentUserNpub;
      
      final followCacheService = FollowCacheService.instance;
      final cachedFollowList = followCacheService.getSync(currentUserHex);
      
      Set<String> followedNpubs;
      
      if (cachedFollowList == null || cachedFollowList.isEmpty) {
        await fetchNotesFromRelays(
          authorNpubs: [currentUserNpub],
          limit: limit,
          until: until,
          since: since,
        );
        
        final followingResult = await nostrService.getFollowingList(currentUserNpub);
        
        if (followingResult.isError || followingResult.data == null || followingResult.data!.isEmpty) {
          return Result.success([]);
        }
        
        final followedHexKeys = followingResult.data!;
        followedNpubs = followedHexKeys
            .map((hex) => nostrService.authService.hexToNpub(hex))
            .where((npub) => npub != null)
            .cast<String>()
            .toSet();
      } else {
        fetchNotesFromRelays(
          authorNpubs: [currentUserNpub],
          limit: limit,
          until: until,
          since: since,
        ).then((_) {}).catchError((e) {
          logger.error('Error fetching notes in background', 'NoteRepository', e);
        });
        
        final followedHexKeys = cachedFollowList;
        followedNpubs = followedHexKeys
            .map((hex) => nostrService.authService.hexToNpub(hex))
            .where((npub) => npub != null)
            .cast<String>()
            .toSet();
      }
      
      final filter = HomeFeedFilter(
        currentUserNpub: currentUserNpub,
        followedUsers: followedNpubs,
        showReplies: false,
      );
      
      return await _getFeedNotesForAuthors(
        filter: filter,
        authorNpubs: followedNpubs.toList(),
        limit: limit,
        until: until,
        since: since,
        skipCache: skipCache,
      );
    } catch (e) {
      logger.error('Exception in getFeedNotesFromFollowList', 'NoteRepository', e);
      return Result.error('Failed to get feed notes: ${e.toString()}');
    }
  }
  
  Future<Result<List<NoteModel>>> getProfileNotes({
    required String authorNpub,
    int limit = 50,
    DateTime? until,
    DateTime? since,
    bool skipCache = false,
  }) async {
    final filter = ProfileFeedFilter(
      targetUserNpub: authorNpub,
      currentUserNpub: authorNpub,
      showReplies: false,
    );
    
    return await _getFeedNotesForAuthors(
      filter: filter,
      authorNpubs: [authorNpub],
      limit: limit,
      until: until,
      since: since,
      isProfileMode: true,
      skipCache: skipCache,
    );
  }
  
  Future<Result<List<NoteModel>>> getHashtagNotes({
    required String hashtag,
    int limit = 20,
    DateTime? until,
    DateTime? since,
  }) async {
    try {
      final result = await nostrDataService.fetchHashtagNotes(
        hashtag: hashtag,
        limit: limit,
        until: until,
        since: since,
      );
      
      return result;
    } catch (e) {
      logger.error('Exception in getHashtagNotes', 'NoteRepository', e);
      return Result.error('Failed to get hashtag notes: ${e.toString()}');
    }
  }
  
}
