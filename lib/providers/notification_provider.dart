import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/notification_model.dart';
import '../models/user_model.dart';
import '../services/data_service.dart';
import 'user_provider.dart';

class NotificationGroup {
  final String type;
  final String targetEventId;
  final List<NotificationModel> notifications = [];
  DateTime latest;

  NotificationGroup({
    required this.type,
    required this.targetEventId,
    required this.latest,
  });
}

class NotificationProvider extends ChangeNotifier {
  static NotificationProvider? _instance;
  static NotificationProvider get instance => _instance ??= NotificationProvider._internal();

  NotificationProvider._internal();

  Box<NotificationModel>? _notificationsBox;
  DataService? _dataService;
  UserProvider? _userProvider;
  bool _isInitialized = false;
  String? _errorMessage;

  // Notification data
  List<NotificationModel> _notifications = [];
  List<dynamic> _displayNotifications = [];
  Map<String, UserModel?> _userProfiles = {};
  bool _isLoading = true;
  int _unreadCount = 0;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<NotificationModel> get notifications => List.unmodifiable(_notifications);
  List<dynamic> get displayNotifications => List.unmodifiable(_displayNotifications);
  Map<String, UserModel?> get userProfiles => Map.unmodifiable(_userProfiles);
  int get unreadCount => _unreadCount;

  // Statistics
  int get totalNotifications => _notifications.length;
  int get notificationsLast24Hours {
    final now = DateTime.now();
    final last24Hours = now.subtract(const Duration(hours: 24));

    int count = 0;
    for (final item in _displayNotifications) {
      if (item is NotificationGroup) {
        if (item.latest.isAfter(last24Hours)) {
          count++;
        }
      } else if (item is NotificationModel) {
        if (item.timestamp.isAfter(last24Hours)) {
          count++;
        }
      }
    }
    return count;
  }

  Future<void> initialize(String npub, {DataService? dataService, UserProvider? userProvider}) async {
    if (_isInitialized) return;

    try {
      _dataService = dataService;
      _userProvider = userProvider;

      // Open notifications box
      _notificationsBox = await Hive.openBox<NotificationModel>('notifications_$npub');

      // Load initial notifications
      await _loadNotifications();

      // Set up listener for DataService notifications if available
      if (_dataService != null) {
        _dataService!.notificationsNotifier.addListener(_handleDataServiceUpdate);
      }

      _isInitialized = true;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to initialize notifications: $e';
      debugPrint('[NotificationProvider] Initialization error: $e');
      notifyListeners();
    }
  }

  Future<void> _loadNotifications() async {
    if (_notificationsBox == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      _notifications = _notificationsBox!.values.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      await _updateDisplayData(_notifications, isInitialLoad: true);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load notifications: $e';
      _isLoading = false;
      debugPrint('[NotificationProvider] Load error: $e');
      notifyListeners();
    }
  }

  void _handleDataServiceUpdate() {
    if (_dataService != null) {
      final newNotifications = _dataService!.notificationsNotifier.value;
      _updateDisplayData(newNotifications);
    }
  }

  Future<void> _updateDisplayData(List<NotificationModel> notificationsFromSource, {bool isInitialLoad = false}) async {
    try {
      final filtered = notificationsFromSource.where((n) => ['mention', 'reaction', 'repost', 'zap'].contains(n.type)).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final limited = filtered.take(100).toList();

      // Load user profiles
      await _loadUserProfiles(limited, isInitialLoad);

      // Group notifications
      final grouped = <String, NotificationGroup>{};
      final flatMentions = <NotificationGroup>[];
      final individualZaps = <NotificationModel>[];

      for (final n in limited) {
        if (n.type == 'zap') {
          individualZaps.add(n);
        } else if (n.type == 'mention') {
          flatMentions.add(NotificationGroup(
            type: n.type,
            targetEventId: n.targetEventId,
            latest: n.timestamp,
          )..notifications.add(n));
        } else {
          final key = '${n.targetEventId}_${n.type}';
          grouped.putIfAbsent(
            key,
            () => NotificationGroup(
              type: n.type,
              targetEventId: n.targetEventId,
              latest: n.timestamp,
            ),
          )
            ..notifications.add(n)
            ..latest = n.timestamp.isAfter(grouped[key]!.latest) ? n.timestamp : grouped[key]!.latest;
        }
      }

      final groupedItems = [...flatMentions, ...grouped.values];
      groupedItems.sort((a, b) => b.latest.compareTo(a.latest));
      individualZaps.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final combined = <dynamic>[...groupedItems, ...individualZaps]..sort((a, b) {
          final at = a is NotificationGroup ? a.latest : a.timestamp;
          final bt = b is NotificationGroup ? b.latest : b.timestamp;
          return bt.compareTo(at);
        });

      _notifications = notificationsFromSource;
      _displayNotifications = combined;
      _updateUnreadCount();

      if (isInitialLoad) _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to update display data: $e';
      debugPrint('[NotificationProvider] Update display data error: $e');
      notifyListeners();
    }
  }

  Future<void> _loadUserProfiles(List<NotificationModel> notifications, bool isInitialLoad) async {
    final npubs = notifications.map((n) => n.author).toSet();
    final loadedProfiles = <String, UserModel?>{};

    await Future.wait(npubs.map((npub) async {
      if (!_userProfiles.containsKey(npub) || isInitialLoad) {
        try {
          UserModel? profile;

          // Try to get from UserProvider first
          if (_userProvider != null) {
            profile = _userProvider!.getUser(npub);
            if (profile == null) {
              profile = await _userProvider!.loadUser(npub);
            }
          } else if (_dataService != null) {
            // Fallback to DataService
            final profileData = await _dataService!.getCachedUserProfile(npub);
            profile = UserModel.fromCachedProfile(npub, profileData);
          }

          loadedProfiles[npub] = profile;
        } catch (e) {
          debugPrint('[NotificationProvider] Error loading profile for $npub: $e');
          loadedProfiles[npub] = null;
        }
      } else {
        loadedProfiles[npub] = _userProfiles[npub];
      }
    }));

    _userProfiles = {..._userProfiles, ...loadedProfiles};
  }

  void _updateUnreadCount() {
    // Count unread notifications (this could be enhanced with read status tracking)
    _unreadCount = _notifications.where((n) => !n.isRead).length;
  }

  // Notification management methods
  Future<void> addNotification(NotificationModel notification) async {
    try {
      if (_notificationsBox != null) {
        await _notificationsBox!.put(notification.id, notification);
        await _loadNotifications();
      }
    } catch (e) {
      _errorMessage = 'Failed to add notification: $e';
      debugPrint('[NotificationProvider] Add notification error: $e');
      notifyListeners();
    }
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      if (_notificationsBox != null) {
        final notification = _notificationsBox!.get(notificationId);
        if (notification != null) {
          final updatedNotification = NotificationModel(
            id: notification.id,
            type: notification.type,
            author: notification.author,
            targetEventId: notification.targetEventId,
            content: notification.content,
            timestamp: notification.timestamp,
            amount: notification.amount,
            isRead: true,
            fetchedAt: notification.fetchedAt,
          );
          await _notificationsBox!.put(notificationId, updatedNotification);
          await _loadNotifications();
        }
      }
    } catch (e) {
      _errorMessage = 'Failed to mark notification as read: $e';
      debugPrint('[NotificationProvider] Mark as read error: $e');
      notifyListeners();
    }
  }

  Future<void> markAllAsRead() async {
    try {
      if (_notificationsBox != null && _dataService != null) {
        await _dataService!.markAllUserNotificationsAsRead();
        await _loadNotifications();
      }
    } catch (e) {
      _errorMessage = 'Failed to mark all as read: $e';
      debugPrint('[NotificationProvider] Mark all as read error: $e');
      notifyListeners();
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    try {
      if (_notificationsBox != null) {
        await _notificationsBox!.delete(notificationId);
        await _loadNotifications();
      }
    } catch (e) {
      _errorMessage = 'Failed to delete notification: $e';
      debugPrint('[NotificationProvider] Delete notification error: $e');
      notifyListeners();
    }
  }

  Future<void> clearAllNotifications() async {
    try {
      if (_notificationsBox != null) {
        await _notificationsBox!.clear();
        _notifications.clear();
        _displayNotifications.clear();
        _userProfiles.clear();
        _unreadCount = 0;
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Failed to clear notifications: $e';
      debugPrint('[NotificationProvider] Clear all error: $e');
      notifyListeners();
    }
  }

  // Helper methods for UI
  String buildGroupTitle(NotificationGroup group) {
    final first = group.notifications.first;
    final names = group.notifications
        .map((n) {
          final profile = _userProfiles[n.author];
          return profile?.name.isNotEmpty == true ? profile!.name : 'Anonymous';
        })
        .toSet()
        .toList();

    if (names.isEmpty) return 'Someone interacted';
    final mainName = names.first;
    final othersCount = names.length - 1;

    switch (first.type) {
      case 'mention':
        return '$mainName mentioned you';
      case 'reaction':
        return othersCount > 0 ? '$mainName and $othersCount others reacted to your post' : '$mainName reacted to your post';
      case 'repost':
        return othersCount > 0 ? '$mainName and $othersCount others reposted your post' : '$mainName reposted your post';
      default:
        return '$mainName interacted with your post';
    }
  }

  Future<void> refresh() async {
    await _loadNotifications();
  }

  @override
  void dispose() {
    _dataService?.notificationsNotifier.removeListener(_handleDataServiceUpdate);
    super.dispose();
  }
}
