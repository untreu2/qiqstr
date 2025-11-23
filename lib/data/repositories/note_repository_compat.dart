import 'dart:async';
import 'package:flutter/material.dart';

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
        if (cachedResult.isSuccess && cachedResult.data!.isNotEmpty) {
          List<NoteModel> filteredCachedNotes = cachedResult.data!;
          
          if (until != null) {
            filteredCachedNotes = filteredCachedNotes.where((note) {
              final noteTime = note.isRepost ? (note.repostTimestamp ?? note.timestamp) : note.timestamp;
              return noteTime.isBefore(until);
            }).toList();
          }
          
          if (filteredCachedNotes.isNotEmpty) {
            debugPrint('[NoteRepository] Found ${filteredCachedNotes.length} cached notes (after until filter: ${until != null})');
            
            fetchNotesFromRelays(
              authorNpubs: authorNpubs,
              limit: limit,
              until: until,
              since: since,
              isProfileMode: isProfileMode,
            ).then((_) {}).catchError((e) {
              debugPrint('[NoteRepository] Error fetching notes in background: $e');
            });
            
            return Result.success(filteredCachedNotes);
          }
        }
      } else {
        debugPrint('[NoteRepository] Skipping cache, fetching directly from relays');
      }
      
      await fetchNotesFromRelays(
        authorNpubs: authorNpubs,
        limit: limit,
        until: until,
        since: since,
        isProfileMode: isProfileMode,
      );
      
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
      debugPrint('[NoteRepository] Exception in _getFeedNotesForAuthors: $e');
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
      debugPrint('[NoteRepository] getFeedNotesFromFollowList for user: $currentUserNpub');
      
      final nostrService = nostrDataService;
      final currentUserHex = nostrService.authService.npubToHex(currentUserNpub) ?? currentUserNpub;
      
      final followCacheService = FollowCacheService.instance;
      final cachedFollowList = followCacheService.getSync(currentUserHex);
      
      Set<String> followedNpubs;
      
      if (cachedFollowList == null || cachedFollowList.isEmpty) {
        debugPrint('[NoteRepository] No cached following list, fetching from relays');
        await fetchNotesFromRelays(
          authorNpubs: [currentUserNpub],
          limit: limit,
          until: until,
          since: since,
        );
        
        final followingResult = await nostrService.getFollowingList(currentUserNpub);
        
        if (followingResult.isError || followingResult.data == null || followingResult.data!.isEmpty) {
          debugPrint('[NoteRepository] No following list, returning empty');
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
          debugPrint('[NoteRepository] Error fetching notes in background: $e');
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
      debugPrint('[NoteRepository] Exception in getFeedNotesFromFollowList: $e');
      return Result.error('Failed to get feed notes: ${e.toString()}');
    }
  }
  
  Future<Result<List<NoteModel>>> getProfileNotes({
    required String authorNpub,
    int limit = 50,
    DateTime? until,
    DateTime? since,
    bool skipCache = true,
  }) async {
    debugPrint('[NoteRepository] getProfileNotes for $authorNpub (skipCache: $skipCache)');
    
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
      debugPrint('[NoteRepository] getHashtagNotes for #$hashtag');
      
      final result = await nostrDataService.fetchHashtagNotes(
        hashtag: hashtag,
        limit: limit,
        until: until,
        since: since,
      );
      
      return result;
    } catch (e) {
      debugPrint('[NoteRepository] Exception in getHashtagNotes: $e');
      return Result.error('Failed to get hashtag notes: ${e.toString()}');
    }
  }
  
}

