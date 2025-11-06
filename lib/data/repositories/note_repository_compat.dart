import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/base/result.dart';
import '../../models/note_model.dart';
import '../filters/feed_filters.dart';
import 'note_repository.dart';

extension NoteRepositoryCompat on NoteRepository {
  Future<Result<List<NoteModel>>> getFeedNotesFromFollowList({
    required String currentUserNpub,
    int limit = 50,
    DateTime? until,
    DateTime? since,
  }) async {
    try {
      debugPrint('[NoteRepository] getFeedNotesFromFollowList for user: $currentUserNpub');
      
      await fetchNotesFromRelays(
        authorNpubs: [currentUserNpub],
        limit: limit,
        until: until,
        since: since,
      );
      
      final nostrService = nostrDataService;
      final followingResult = await nostrService.getFollowingList(currentUserNpub);
      
      if (followingResult.isError || followingResult.data == null || followingResult.data!.isEmpty) {
        debugPrint('[NoteRepository] No following list, returning empty');
        return Result.success([]);
      }
      
      final followedHexKeys = followingResult.data!;
      final followedNpubs = followedHexKeys
          .map((hex) => nostrService.authService.hexToNpub(hex))
          .where((npub) => npub != null)
          .cast<String>()
          .toSet();
      
      final filter = HomeFeedFilter(
        currentUserNpub: currentUserNpub,
        followedUsers: followedNpubs,
        showReplies: false,
      );
      
      return await getFilteredNotes(filter);
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
  }) async {
    try {
      debugPrint('[NoteRepository] getProfileNotes for $authorNpub');
      
      await fetchNotesFromRelays(
        authorNpubs: [authorNpub],
        limit: limit,
        until: until,
        since: since,
        isProfileMode: true,
      );
      
      final filter = ProfileFeedFilter(
        targetUserNpub: authorNpub,
        currentUserNpub: authorNpub,
        showReplies: false,
      );
      
      return await getFilteredNotes(filter);
    } catch (e) {
      debugPrint('[NoteRepository] Exception in getProfileNotes: $e');
      return Result.error('Failed to get profile notes: ${e.toString()}');
    }
  }
  
  Future<Result<List<NoteModel>>> getHashtagNotes({
    required String hashtag,
    int limit = 20,
    DateTime? until,
    DateTime? since,
  }) async {
    try {
      debugPrint('[NoteRepository] getHashtagNotes for #$hashtag');
      
      await fetchNotesFromRelays(
        hashtag: hashtag,
        limit: limit,
        until: until,
        since: since,
      );
      
      final filter = HashtagFilter(
        hashtag: hashtag,
        currentUserNpub: '',
      );
      
      return await getFilteredNotes(filter);
    } catch (e) {
      debugPrint('[NoteRepository] Exception in getHashtagNotes: $e');
      return Result.error('Failed to get hashtag notes: ${e.toString()}');
    }
  }
  
}

