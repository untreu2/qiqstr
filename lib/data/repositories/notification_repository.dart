import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/base/result.dart';
import '../../models/notification_model.dart';
import '../../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/network_service.dart';
import '../services/validation_service.dart';
import '../services/data_service.dart';

class NotificationRepository {
  final AuthService _authService;
  final DataService _nostrDataService;

  final StreamController<List<NotificationModel>> _notificationsController = StreamController<List<NotificationModel>>.broadcast();
  final StreamController<int> _unreadCountController = StreamController<int>.broadcast();
  final Map<String, UserModel> _userProfilesCache = {};
  final List<NotificationModel> _notifications = [];
  int _unreadCount = 0;
  String? _currentUserHex;

  StreamSubscription<List<NotificationModel>>? _notificationStreamSubscription;
  DateTime? _lastDebounceTime;
  static const Duration _debounceDelay = Duration(milliseconds: 2000);

  NotificationRepository({
    required AuthService authService,
    required NetworkService networkService,
    required ValidationService validationService,
    required DataService nostrDataService,
  })  : _authService = authService,
        _nostrDataService = nostrDataService {
    _setupRealTimeNotifications();
  }

  Stream<List<NotificationModel>> get notificationsStream => _notificationsController.stream;
  Stream<int> get unreadCountStream => _unreadCountController.stream;

  void _setupRealTimeNotifications() {
    debugPrint('[NotificationRepository] Setting up real-time notification updates');
    _initializeCurrentUser();

    _notificationStreamSubscription = _nostrDataService.notificationsStream.listen((newNotifications) async {
      _debouncedProcessNotifications(newNotifications);
    });

    debugPrint('[NotificationRepository] Real-time notification stream is now active');
  }

  Future<void> _initializeCurrentUser() async {
    if (_currentUserHex == null) {
      final userResult = await _authService.getCurrentUserPublicKeyHex();
      if (userResult.isSuccess && userResult.data != null) {
        _currentUserHex = userResult.data;
      }
    }
  }

  void _debouncedProcessNotifications(List<NotificationModel> newNotifications) {
    final debounceTime = DateTime.now();
    _lastDebounceTime = debounceTime;

    Future.delayed(_debounceDelay, () async {
      if (_lastDebounceTime == debounceTime) {
        await _processNotifications(newNotifications);
      }
    });
  }

  Future<void> _processNotifications(List<NotificationModel> newNotifications) async {
    debugPrint('[NotificationRepository] Processing ${newNotifications.length} notifications');

    if (_currentUserHex == null) {
      await _initializeCurrentUser();
      if (_currentUserHex == null) {
        debugPrint('[NotificationRepository] Could not get current user, skipping filtering');
        return;
      }
    }

    final filteredNotifications = _filterSelfNotifications(newNotifications);
    final addedNotifications = _addNewNotifications(filteredNotifications);

    if (addedNotifications.isNotEmpty) {
      _sortAndEmitNotifications(addedNotifications.length);
    }
  }

  List<NotificationModel> _filterSelfNotifications(List<NotificationModel> notifications) {
    return notifications.where((notification) => notification.author != _currentUserHex).toList();
  }

  List<NotificationModel> _addNewNotifications(List<NotificationModel> filteredNotifications) {
    final existingIds = _notifications.map((n) => n.id).toSet();
    final newNotifications = filteredNotifications.where((notification) => !existingIds.contains(notification.id)).toList();

    for (final notification in newNotifications) {
      _insertSortedNotification(notification);
    }
    _unreadCount += newNotifications.length;

    return newNotifications;
  }

  void _insertSortedNotification(NotificationModel notification) {
    int left = 0;
    int right = _notifications.length;

    while (left < right) {
      final mid = (left + right) ~/ 2;
      if (_notifications[mid].timestamp.isAfter(notification.timestamp)) {
        left = mid + 1;
      } else {
        right = mid;
      }
    }

    _notifications.insert(left, notification);
  }

  void _sortAndEmitNotifications(int addedCount) {
    debugPrint('[NotificationRepository] Added $addedCount new notifications, total: ${_notifications.length}');

    _notificationsController.add(List.unmodifiable(_notifications));
    _unreadCountController.add(_unreadCount);

    debugPrint('[NotificationRepository] Emitted update to subscribers');
  }

  Future<Result<List<NotificationModel>>> getNotifications({
    DateTime? since,
  }) async {
    try {
      if (_currentUserHex == null) {
        await _initializeCurrentUser();
        if (_currentUserHex == null) {
          return const Result.error('No authenticated user hex pubkey');
        }
      }

      final result = await _nostrDataService.fetchNotifications(
        since: since,
      );

      if (result.isSuccess && result.data != null) {
        final filteredNotifications = _filterSelfNotifications(result.data!);

        _notifications.clear();
        _notifications.addAll(filteredNotifications);
        _unreadCount = filteredNotifications.length;

        _notificationsController.add(List.unmodifiable(_notifications));
        _unreadCountController.add(_unreadCount);

        return Result.success(filteredNotifications);
      }

      return result;
    } catch (e) {
      return Result.error('Failed to get notifications: $e');
    }
  }

  List<dynamic> groupNotifications(List<NotificationModel> notifications) {
    final groups = <String, List<NotificationModel>>{};
    final standaloneNotifications = <NotificationModel>[];

    for (final notification in notifications) {
      if (notification.type == 'zap' || notification.type == 'mention') {
        standaloneNotifications.add(notification);
      } else {
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

      final user = UserModel.create(
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

  Future<Result<int>> pruneOldNotifications(Duration retentionPeriod) async {
    try {
      final cutoffTime = DateTime.now().subtract(retentionPeriod);
      int removedCount = 0;

      _notifications.removeWhere((notification) {
        if (notification.timestamp.isBefore(cutoffTime)) {
          if (!notification.isRead) {
            _unreadCount = (_unreadCount - 1).clamp(0, double.infinity).toInt();
          }
          removedCount++;
          return true;
        }
        return false;
      });

      if (removedCount > 0) {
        debugPrint('[NotificationRepository] Pruned $removedCount old notifications');
        _notificationsController.add(List.unmodifiable(_notifications));
        _unreadCountController.add(_unreadCount);
      }

      return Result.success(removedCount);
    } catch (e) {
      debugPrint('[NotificationRepository] Error pruning notifications: $e');
      return Result.error('Failed to prune notifications: ${e.toString()}');
    }
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
