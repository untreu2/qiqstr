import 'dart:async';
import 'dart:convert';
import 'package:collection/collection.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../models/repost_model.dart';
import '../models/zap_model.dart';
import '../models/notification_model.dart';
import '../models/following_model.dart';
import '../models/user_model.dart';
import 'cache_service.dart';
import 'profile_service.dart';

class EventHandlerService {
  final CacheService _cacheService;
  final ProfileService _profileService;
  final String npub;
  
  // Callbacks
  final Function(String, List<ReactionModel>)? onReactionsUpdated;
  final Function(String, List<ReplyModel>)? onRepliesUpdated;
  final Function(String, List<RepostModel>)? onRepostsUpdated;
  final Function(NoteModel)? onNewNote;

  EventHandlerService({
    required CacheService cacheService,
    required ProfileService profileService,
    required this.npub,
    this.onReactionsUpdated,
    this.onRepliesUpdated,
    this.onRepostsUpdated,
    this.onNewNote,
  }) : _cacheService = cacheService,
       _profileService = profileService;

  Future<void> handleReactionEvent(Map<String, dynamic> eventData) async {
    try {
      String? targetEventId;
      for (var tag in eventData['tags']) {
        if (tag is List && tag.length >= 2 && tag[0] == 'e') {
          targetEventId = tag[1] as String;
          break;
        }
      }
      if (targetEventId == null) return;

      final reaction = ReactionModel.fromEvent(eventData);
      _cacheService.reactionsMap.putIfAbsent(targetEventId, () => []);

      if (!_cacheService.reactionsMap[targetEventId]!.any((r) => r.id == reaction.id)) {
        _cacheService.reactionsMap[targetEventId]!.add(reaction);
        await _cacheService.reactionsBox?.put(reaction.id, reaction);

        onReactionsUpdated?.call(targetEventId, _cacheService.reactionsMap[targetEventId]!);
        
        // Fetch profile in background
        unawaited(_profileService.batchFetchProfiles([reaction.author]));
      }
    } catch (e) {
      print('[EventHandler ERROR] Error handling reaction event: $e');
    }
  }

  Future<void> handleRepostEvent(Map<String, dynamic> eventData) async {
    try {
      String? originalNoteId;
      for (var tag in eventData['tags']) {
        if (tag is List && tag.length >= 2 && tag[0] == 'e') {
          originalNoteId = tag[1] as String;
          break;
        }
      }
      if (originalNoteId == null) return;

      final repost = RepostModel.fromEvent(eventData, originalNoteId);
      _cacheService.repostsMap.putIfAbsent(originalNoteId, () => []);

      if (!_cacheService.repostsMap[originalNoteId]!.any((r) => r.id == repost.id)) {
        _cacheService.repostsMap[originalNoteId]!.add(repost);
        await _cacheService.repostsBox?.put(repost.id, repost);

        onRepostsUpdated?.call(originalNoteId, _cacheService.repostsMap[originalNoteId]!);
        
        // Fetch profile in background
        unawaited(_profileService.batchFetchProfiles([repost.repostedBy]));
      }
    } catch (e) {
      print('[EventHandler ERROR] Error handling repost event: $e');
    }
  }

  Future<void> handleReplyEvent(Map<String, dynamic> eventData, String parentEventId) async {
    try {
      final reply = ReplyModel.fromEvent(eventData);
      _cacheService.repliesMap.putIfAbsent(parentEventId, () => []);

      if (!_cacheService.repliesMap[parentEventId]!.any((r) => r.id == reply.id)) {
        _cacheService.repliesMap[parentEventId]!.add(reply);
        await _cacheService.repliesBox?.put(reply.id, reply);

        onRepliesUpdated?.call(parentEventId, _cacheService.repliesMap[parentEventId]!);

        // Create note model for the reply
        final isRepost = eventData['kind'] == 6;
        final repostTimestamp = isRepost 
            ? DateTime.fromMillisecondsSinceEpoch((eventData['created_at'] as int) * 1000) 
            : null;

        final noteModel = NoteModel(
          id: reply.id,
          content: reply.content,
          author: reply.author,
          timestamp: reply.timestamp,
          isReply: true,
          isRepost: isRepost,
          repostedBy: isRepost ? reply.author : null,
          repostTimestamp: repostTimestamp,
          parentId: parentEventId,
          rootId: reply.rootEventId,
          rawWs: jsonEncode(eventData),
        );

        await _cacheService.notesBox?.put(noteModel.id, noteModel);
        
        if (reply.author == npub) {
          onNewNote?.call(noteModel);
        }
        
        // Fetch profile in background
        unawaited(_profileService.batchFetchProfiles([reply.author]));
      }
    } catch (e) {
      print('[EventHandler ERROR] Error handling reply event: $e');
    }
  }

  Future<void> handleZapEvent(Map<String, dynamic> eventData) async {
    try {
      final zap = ZapModel.fromEvent(eventData);
      final key = zap.targetEventId;

      if (key.isEmpty) return;

      _cacheService.zapsMap.putIfAbsent(key, () => []);

      if (!_cacheService.zapsMap[key]!.any((z) => z.id == zap.id)) {
        _cacheService.zapsMap[key]!.add(zap);
        await _cacheService.zapsBox?.put(zap.id, zap);
      }
    } catch (e) {
      print('[EventHandler ERROR] Error handling zap event: $e');
    }
  }

  Future<void> handleProfileEvent(Map<String, dynamic> eventData) async {
    try {
      final author = eventData['pubkey'] as String;
      final createdAt = DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000);
      final contentRaw = eventData['content'];

      Map<String, dynamic> profileContent;
      if (contentRaw is String && contentRaw.isNotEmpty) {
        try {
          profileContent = jsonDecode(contentRaw) as Map<String, dynamic>;
        } catch (e) {
          profileContent = {};
        }
      } else {
        profileContent = {};
      }

      final profileData = {
        'name': profileContent['name'] as String? ?? 'Anonymous',
        'profileImage': profileContent['picture'] as String? ?? '',
        'about': profileContent['about'] as String? ?? '',
        'nip05': profileContent['nip05'] as String? ?? '',
        'banner': profileContent['banner'] as String? ?? '',
        'lud16': profileContent['lud16'] as String? ?? '',
        'website': profileContent['website'] as String? ?? '',
      };

      // Update profile cache
      await _profileService.getCachedUserProfile(author);

      if (_cacheService.usersBox != null && _cacheService.usersBox!.isOpen) {
        final userModel = UserModel(
          npub: author,
          name: profileData['name']!,
          about: profileData['about']!,
          nip05: profileData['nip05']!,
          banner: profileData['banner']!,
          profileImage: profileData['profileImage']!,
          lud16: profileData['lud16']!,
          website: profileData['website']!,
          updatedAt: createdAt,
        );
        await _cacheService.usersBox!.put(author, userModel);
      }
    } catch (e) {
      print('[EventHandler ERROR] Error handling profile event: $e');
    }
  }

  Future<void> handleFollowingEvent(Map<String, dynamic> eventData) async {
    try {
      List<String> newFollowing = [];
      final tags = eventData['tags'] as List<dynamic>;
      
      for (var tag in tags) {
        if (tag is List && tag.isNotEmpty && tag[0] == 'p') {
          if (tag.length > 1) {
            newFollowing.add(tag[1] as String);
          }
        }
      }
      
      if (_cacheService.followingBox != null && _cacheService.followingBox!.isOpen) {
        final model = FollowingModel(
          pubkeys: newFollowing, 
          updatedAt: DateTime.now(), 
          npub: npub
        );
        await _cacheService.followingBox!.put('following', model);
      }
    } catch (e) {
      print('[EventHandler ERROR] Error handling following event: $e');
    }
  }

  Future<void> handleNotificationEvent(Map<String, dynamic> eventData, String notificationType) async {
    try {
      final notification = NotificationModel.fromEvent(eventData, notificationType);

      if (_cacheService.notificationsBox != null && _cacheService.notificationsBox!.isOpen) {
        if (!_cacheService.notificationsBox!.containsKey(notification.id)) {
          await _cacheService.notificationsBox!.put(notification.id, notification);
        }
      }
    } catch (e) {
      print('[EventHandler ERROR] Error handling notification event: $e');
    }
  }
}

// Helper function for fire-and-forget operations
void unawaited(Future<void> future) {
  future.catchError((error) {
    print('[EventHandler] Background operation failed: $error');
  });
}