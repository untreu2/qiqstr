import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/base/result.dart';
import '../../models/notification_model.dart';
import '../../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/network_service.dart';
import '../services/validation_service.dart';
import '../services/nostr_data_service.dart';

class NotificationRepository {
  final AuthService _authService;
  final NostrDataService _nostrDataService;

  final StreamController<List<NotificationModel>> _notificationsController = StreamController<List<NotificationModel>>.broadcast();
  final StreamController<int> _unreadCountController = StreamController<int>.broadcast();
  final Map<String, UserModel> _userProfilesCache = {};
  final List<NotificationModel> _notifications = [];
  int _unreadCount = 0;

  StreamSubscription<List<NotificationModel>>? _notificationStreamSubscription;

  NotificationRepository({
    required AuthService authService,
    required NetworkService networkService,
    required ValidationService validationService,
    required NostrDataService nostrDataService,
  })  : _authService = authService,
        _nostrDataService = nostrDataService {
    _setupRealTimeNotifications();
  }

  Stream<List<NotificationModel>> get notificationsStream => _notificationsController.stream;
  Stream<int> get unreadCountStream => _unreadCountController.stream;

  void _setupRealTimeNotifications() {
    debugPrint('[NotificationRepository] Setting up real-time notification updates');
    
    _notificationStreamSubscription = _nostrDataService.notificationsStream.listen((newNotifications) async {
      debugPrint('[NotificationRepository] Stream received ${newNotifications.length} notifications');

      // Get current user to filter out self-interactions
      final userResult = await _authService.getCurrentUserPublicKeyHex();
      if (userResult.isError || userResult.data == null) {
        debugPrint('[NotificationRepository] Could not get current user, skipping filtering');
        return;
      }

      final userHexPubkey = userResult.data!;
      
      // Filter out notifications from the current user
      final filteredNotifications = newNotifications.where((notification) {
        return notification.author != userHexPubkey;
      }).toList();

      int addedCount = 0;
      for (final notification in filteredNotifications) {
        if (!_notifications.any((n) => n.id == notification.id)) {
          _notifications.add(notification);
          addedCount++;
          _unreadCount++;
        }
      }

      if (addedCount > 0) {
        debugPrint('[NotificationRepository] Added $addedCount new notifications (filtered from ${newNotifications.length}), total: ${_notifications.length}');

        _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        _notificationsController.add(_notifications);
        _unreadCountController.add(_unreadCount);

        debugPrint('[NotificationRepository] Emitted update to subscribers');
      }
    });

    debugPrint('[NotificationRepository] Real-time notification stream is now active');
  }

  Future<Result<List<NotificationModel>>> getNotifications({
    int limit = 50,
    DateTime? since,
  }) async {
    try {
      debugPrint('[NotificationRepository] getNotifications called with limit: $limit');

      final userResult = await _authService.getCurrentUserPublicKeyHex();

      if (userResult.isError) {
        return Result.error(userResult.error!);
      }

      final userHexPubkey = userResult.data;
      if (userHexPubkey == null || userHexPubkey.isEmpty) {
        return const Result.error('No authenticated user hex pubkey');
      }

      final result = await _nostrDataService.fetchNotifications(
        limit: limit,
        since: since,
      );

      if (result.isSuccess && result.data != null) {
        // Filter out notifications where the author is the current user
        final filteredNotifications = result.data!.where((notification) {
          return notification.author != userHexPubkey;
        }).toList();

        _notifications.clear();
        _notifications.addAll(filteredNotifications);

        _unreadCount = filteredNotifications.length;

        debugPrint('[NotificationRepository] Loaded ${_notifications.length} notifications (filtered from ${result.data!.length})');

        _notificationsController.add(_notifications);
        _unreadCountController.add(_unreadCount);
      }

      return result;
    } catch (e) {
      debugPrint('[NotificationRepository] Error getting notifications: $e');
      return Result.error('Failed to get notifications: $e');
    }
  }

  List<dynamic> groupNotifications(List<NotificationModel> notifications) {
    final groups = <String, List<NotificationModel>>{};
    final standaloneNotifications = <NotificationModel>[];

    for (final notification in notifications) {
      if (notification.type == 'zap' || notification.type == 'mention') {
        // Show zaps and mentions individually
        standaloneNotifications.add(notification);
      } else {
        // Group other types (reactions, reposts) by type and target event
        final key = '${notification.type}_${notification.targetEventId}';
        groups[key] = groups[key] ?? [];
        groups[key]!.add(notification);
      }
    }

    final result = <dynamic>[];

    for (final group in groups.values) {
      if (group.length == 1) {
        result.add(group.first);
      } else {
        result.add(NotificationGroup(notifications: group));
      }
    }

    result.addAll(standaloneNotifications);

    result.sort((a, b) {
      final aTime = a is NotificationGroup ? a.notifications.first.timestamp : (a as NotificationModel).timestamp;
      final bTime = b is NotificationGroup ? b.notifications.first.timestamp : (b as NotificationModel).timestamp;
      return bTime.compareTo(aTime);
    });

    return result;
  }

  Future<Result<void>> markAllAsRead() async {
    try {
      _unreadCount = 0;
      _unreadCountController.add(_unreadCount);

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to mark notifications as read: $e');
    }
  }

  Future<Result<UserModel?>> getUserProfile(String npub) async {
    try {
      if (_userProfilesCache.containsKey(npub)) {
        return Result.success(_userProfilesCache[npub]);
      }

      final user = UserModel(
        pubkeyHex: npub,
        name: npub.substring(0, 8),
        about: '',
        nip05: '',
        banner: '',
        profileImage: '',
        lud16: '',
        website: '',
        updatedAt: DateTime.now(),
      );

      _userProfilesCache[npub] = user;
      return Result.success(user);
    } catch (e) {
      return Result.error('Failed to get user profile: $e');
    }
  }

  int getNotificationsLast24Hours() {
    final twentyFourHoursAgo = DateTime.now().subtract(const Duration(hours: 24));
    return _notifications.where((n) => n.timestamp.isAfter(twentyFourHoursAgo)).length;
  }

  int get unreadCount => _unreadCount;

  Map<String, UserModel> get userProfiles => Map.unmodifiable(_userProfilesCache);

  Future<Result<List<NotificationModel>>> refreshNotifications() async {
    _notifications.clear();
    return getNotifications();
  }

  void clearCache() {
    _notifications.clear();
    _userProfilesCache.clear();
    _unreadCount = 0;
  }

  void dispose() {
    debugPrint('[NotificationRepository] Disposing notification repository');
    _notificationStreamSubscription?.cancel();
    _notificationsController.close();
    _unreadCountController.close();
    _notifications.clear();
    _userProfilesCache.clear();
  }
}

class NotificationGroup {
  final List<NotificationModel> notifications;

  NotificationGroup({required this.notifications});

  String get type => notifications.first.type;
  DateTime get timestamp => notifications.first.timestamp;
  String get targetEventId => notifications.first.targetEventId;
}
