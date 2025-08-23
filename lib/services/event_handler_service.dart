import 'dart:async';
import 'dart:convert';
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

  final Function(String, List<ReactionModel>)? onReactionsUpdated;
  final Function(String, List<ReplyModel>)? onRepliesUpdated;
  final Function(String, List<RepostModel>)? onRepostsUpdated;
  final Function(NoteModel)? onNewNote;

  final Set<String> _processedEventIds = {};

  EventHandlerService({
    required CacheService cacheService,
    required ProfileService profileService,
    required this.npub,
    this.onReactionsUpdated,
    this.onRepliesUpdated,
    this.onRepostsUpdated,
    this.onNewNote,
  })  : _cacheService = cacheService,
        _profileService = profileService;

  Future<void> processEvent(Map<String, dynamic> eventData) async {
    final eventId = eventData['id'] as String?;
    final kind = eventData['kind'] as int?;

    if (eventId == null || kind == null || _processedEventIds.contains(eventId)) {
      return;
    }

    _processedEventIds.add(eventId);

    switch (kind) {
      case 7:
        await handleReactionEvent(eventData);
        break;
      case 6:
        await handleRepostEvent(eventData);
        break;
      case 1:
        await _handleNoteOrReply(eventData);
        break;
      case 9735:
        await handleZapEvent(eventData);
        break;
      case 0:
        await handleProfileEvent(eventData);
        break;
      case 3:
        await handleFollowingEvent(eventData);
        break;
    }
  }

  Future<void> _handleNoteOrReply(Map<String, dynamic> eventData) async {
    final tags = eventData['tags'] as List<dynamic>? ?? [];
    String? parentEventId;

    for (var tag in tags) {
      if (tag is List && tag.length >= 2 && tag[0] == 'e') {
        parentEventId = tag[1] as String;
        break;
      }
    }

    if (parentEventId != null) {
      await handleReplyEvent(eventData, parentEventId);
    }
  }

  Future<void> handleReactionEvent(Map<String, dynamic> eventData) async {
    try {
      String? targetEventId;
      final tags = eventData['tags'] as List<dynamic>? ?? [];

      for (var tag in tags) {
        if (tag is List && tag.length >= 2 && tag[0] == 'e') {
          targetEventId = tag[1] as String;
          break;
        }
      }
      if (targetEventId == null) return;

      final reaction = ReactionModel.fromEvent(eventData);

      final existingReactions = _cacheService.reactionsMap[targetEventId];
      if (existingReactions != null && existingReactions.any((r) => r.id == reaction.id)) {
        return;
      }

      _cacheService.reactionsMap.putIfAbsent(targetEventId, () => []);
      _cacheService.reactionsMap[targetEventId]!.add(reaction);

      final reactionsBox = _cacheService.reactionsBox;
      if (reactionsBox != null) {
        _saveAsync(() => reactionsBox.put(reaction.id, reaction));
      }

      onReactionsUpdated?.call(targetEventId, _cacheService.reactionsMap[targetEventId]!);
      _profileService.batchFetchProfiles([reaction.author]);
    } catch (e) {
      print('[EventHandler ERROR] Error handling reaction event: $e');
    }
  }

  Future<void> handleRepostEvent(Map<String, dynamic> eventData) async {
    try {
      String? originalNoteId;
      final tags = eventData['tags'] as List<dynamic>? ?? [];

      for (var tag in tags) {
        if (tag is List && tag.length >= 2 && tag[0] == 'e') {
          originalNoteId = tag[1] as String;
          break;
        }
      }
      if (originalNoteId == null) return;

      final repost = RepostModel.fromEvent(eventData, originalNoteId);

      final existingReposts = _cacheService.repostsMap[originalNoteId];
      if (existingReposts != null && existingReposts.any((r) => r.id == repost.id)) {
        return;
      }

      _cacheService.repostsMap.putIfAbsent(originalNoteId, () => []);
      _cacheService.repostsMap[originalNoteId]!.add(repost);

      final repostsBox = _cacheService.repostsBox;
      if (repostsBox != null) {
        _saveAsync(() => repostsBox.put(repost.id, repost));
      }

      onRepostsUpdated?.call(originalNoteId, _cacheService.repostsMap[originalNoteId]!);
      _profileService.batchFetchProfiles([repost.repostedBy]);
    } catch (e) {
      print('[EventHandler ERROR] Error handling repost event: $e');
    }
  }

  Future<void> handleReplyEvent(Map<String, dynamic> eventData, String parentEventId) async {
    try {
      final reply = ReplyModel.fromEvent(eventData);

      final existingReplies = _cacheService.repliesMap[parentEventId];
      if (existingReplies != null && existingReplies.any((r) => r.id == reply.id)) {
        return;
      }

      _cacheService.repliesMap.putIfAbsent(parentEventId, () => []);
      _cacheService.repliesMap[parentEventId]!.add(reply);

      final repliesBox = _cacheService.repliesBox;
      if (repliesBox != null) {
        _saveAsync(() => repliesBox.put(reply.id, reply));
      }

      onRepliesUpdated?.call(parentEventId, _cacheService.repliesMap[parentEventId]!);

      if (reply.author == npub) {
        final noteModel = NoteModel(
          id: reply.id,
          content: reply.content,
          author: reply.author,
          timestamp: reply.timestamp,
          isReply: true,
          parentId: parentEventId,
          rootId: reply.rootEventId,
          rawWs: jsonEncode(eventData),
        );

        final notesBox = _cacheService.notesBox;
        if (notesBox != null) {
          _saveAsync(() => notesBox.put(noteModel.id, noteModel));
        }
        onNewNote?.call(noteModel);
      }

      _profileService.batchFetchProfiles([reply.author]);
    } catch (e) {
      print('[EventHandler ERROR] Error handling reply event: $e');
    }
  }

  Future<void> handleZapEvent(Map<String, dynamic> eventData) async {
    try {
      final zap = ZapModel.fromEvent(eventData);
      final key = zap.targetEventId;

      if (key.isEmpty) return;

      final existingZaps = _cacheService.zapsMap[key];
      if (existingZaps != null && existingZaps.any((z) => z.id == zap.id)) {
        return;
      }

      _cacheService.zapsMap.putIfAbsent(key, () => []);
      _cacheService.zapsMap[key]!.add(zap);

      final zapsBox = _cacheService.zapsBox;
      if (zapsBox != null) {
        _saveAsync(() => zapsBox.put(zap.id, zap));
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

      Map<String, dynamic> profileContent = {};
      if (contentRaw is String && contentRaw.isNotEmpty) {
        try {
          profileContent = jsonDecode(contentRaw) as Map<String, dynamic>;
        } catch (e) {
          profileContent = {};
        }
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
        _saveAsync(() => _cacheService.usersBox!.put(author, userModel));
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
        final model = FollowingModel(pubkeys: newFollowing, updatedAt: DateTime.now(), npub: npub);
        _saveAsync(() => _cacheService.followingBox!.put('following', model));
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
          _saveAsync(() => _cacheService.notificationsBox!.put(notification.id, notification));
        }
      }
    } catch (e) {
      print('[EventHandler ERROR] Error handling notification event: $e');
    }
  }

  void _saveAsync(Future<void> Function() saveOperation) {
    Future.microtask(() async {
      try {
        await saveOperation();
      } catch (e) {
        print('[EventHandler] Background save failed: $e');
      }
    });
  }

  void dispose() {
    _processedEventIds.clear();
  }
}
