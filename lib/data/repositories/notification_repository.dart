import 'dart:async';

import '../../core/base/result.dart';
import '../../models/notification_model.dart';
import '../../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/network_service.dart';
import '../services/validation_service.dart';
import '../services/nostr_data_service.dart';

/// Repository for notification-related operations
/// Handles notification fetching, grouping, and management
class NotificationRepository {
  final AuthService _authService;
  final NostrDataService _nostrDataService;

  // Internal state
  final StreamController<List<NotificationModel>> _notificationsController = StreamController<List<NotificationModel>>.broadcast();
  final StreamController<int> _unreadCountController = StreamController<int>.broadcast();
  final Map<String, UserModel> _userProfilesCache = {};
  final List<NotificationModel> _notifications = [];
  int _unreadCount = 0;

  NotificationRepository({
    required AuthService authService,
    required NetworkService networkService,
    required ValidationService validationService,
    required NostrDataService nostrDataService,
  })  : _authService = authService,
        _nostrDataService = nostrDataService;

  // Streams
  Stream<List<NotificationModel>> get notificationsStream => _notificationsController.stream;
  Stream<int> get unreadCountStream => _unreadCountController.stream;

  /// Get notifications for current user
  /// Fetches kind 1, 6, 7, 9735 events where the logged-in user's hex pubkey is mentioned
  Future<Result<List<NotificationModel>>> getNotifications({
    int limit = 50,
    DateTime? since,
  }) async {
    try {
      // Get current user's hex pubkey
      final userResult = await _authService.getCurrentUserPublicKeyHex();

      if (userResult.isError) {
        return Result.error(userResult.error!);
      }

      final userHexPubkey = userResult.data;
      if (userHexPubkey == null || userHexPubkey.isEmpty) {
        return const Result.error('No authenticated user hex pubkey');
      }

      // Use NostrDataService to fetch notifications for the user's hex pubkey
      // This will look for kind 1, 6, 7, 9735 events mentioning the user
      final result = await _nostrDataService.fetchNotifications(
        limit: limit,
        since: since,
      );

      if (result.isSuccess && result.data != null) {
        // Update internal notifications list
        _notifications.clear();
        _notifications.addAll(result.data!);

        // Calculate unread count (all notifications are unread by default)
        _unreadCount = result.data!.length;

        // Emit to streams
        _notificationsController.add(_notifications);
        _unreadCountController.add(_unreadCount);
      }

      return result;
    } catch (e) {
      return Result.error('Failed to get notifications: $e');
    }
  }

  /// Group notifications by type and event
  List<dynamic> groupNotifications(List<NotificationModel> notifications) {
    final groups = <String, List<NotificationModel>>{};
    final standaloneNotifications = <NotificationModel>[];

    for (final notification in notifications) {
      if (notification.type == 'zap') {
        // Zaps are standalone
        standaloneNotifications.add(notification);
      } else {
        // Group by target event ID
        final key = '${notification.type}_${notification.targetEventId}';
        groups[key] = groups[key] ?? [];
        groups[key]!.add(notification);
      }
    }

    final result = <dynamic>[];

    // Add grouped notifications
    for (final group in groups.values) {
      if (group.length == 1) {
        result.add(group.first);
      } else {
        result.add(NotificationGroup(notifications: group));
      }
    }

    // Add standalone notifications
    result.addAll(standaloneNotifications);

    // Sort by timestamp (most recent first)
    result.sort((a, b) {
      final aTime = a is NotificationGroup ? a.notifications.first.timestamp : (a as NotificationModel).timestamp;
      final bTime = b is NotificationGroup ? b.notifications.first.timestamp : (b as NotificationModel).timestamp;
      return bTime.compareTo(aTime);
    });

    return result;
  }

  /// Mark all notifications as read
  Future<Result<void>> markAllAsRead() async {
    try {
      _unreadCount = 0;
      _unreadCountController.add(_unreadCount);

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to mark notifications as read: $e');
    }
  }

  /// Get user profile for notification author
  Future<Result<UserModel?>> getUserProfile(String npub) async {
    try {
      // Check cache first
      if (_userProfilesCache.containsKey(npub)) {
        return Result.success(_userProfilesCache[npub]);
      }

      // For now, create a basic profile
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

  /// Get notifications from last 24 hours count
  int getNotificationsLast24Hours() {
    final twentyFourHoursAgo = DateTime.now().subtract(const Duration(hours: 24));
    return _notifications.where((n) => n.timestamp.isAfter(twentyFourHoursAgo)).length;
  }

  /// Get current unread count
  int get unreadCount => _unreadCount;

  /// Get cached user profiles
  Map<String, UserModel> get userProfiles => Map.unmodifiable(_userProfilesCache);

  /// Refresh notifications
  Future<Result<List<NotificationModel>>> refreshNotifications() async {
    // Clear cache and fetch fresh data
    _notifications.clear();
    return getNotifications();
  }

  /// Clear notifications cache
  void clearCache() {
    _notifications.clear();
    _userProfilesCache.clear();
    _unreadCount = 0;
  }

  /// Dispose repository
  void dispose() {
    _notificationsController.close();
    _unreadCountController.close();
    _notifications.clear();
    _userProfilesCache.clear();
  }
}

/// Notification group for grouping similar notifications
class NotificationGroup {
  final List<NotificationModel> notifications;

  NotificationGroup({required this.notifications});

  String get type => notifications.first.type;
  DateTime get timestamp => notifications.first.timestamp;
  String get targetEventId => notifications.first.targetEventId;
}
