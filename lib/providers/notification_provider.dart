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

  List<NotificationModel> _notifications = [];
  List<dynamic> _displayNotifications = [];
  Map<String, UserModel?> _userProfiles = {};
  bool _isLoading = true;
  int _unreadCount = 0;

  DateTime _lastCleanup = DateTime.now();
  bool _processingUpdate = false;
  final Map<String, DateTime> _profileLoadTimes = {};

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<NotificationModel> get notifications => List.unmodifiable(_notifications);
  List<dynamic> get displayNotifications => List.unmodifiable(_displayNotifications);
  Map<String, UserModel?> get userProfiles => Map.unmodifiable(_userProfiles);
  int get unreadCount => _unreadCount;

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

      _notificationsBox = await Hive.openBox<NotificationModel>('notifications_$npub');

      await _loadNotifications();

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

      final allNotifications = _notificationsBox!.values.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      _notifications = allNotifications.take(500).toList();

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
    if (_processingUpdate) return;

    try {
      _processingUpdate = true;

      _performPeriodicCleanup();

      final filtered = notificationsFromSource.where((n) => ['mention', 'reaction', 'repost', 'zap'].contains(n.type)).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final limited = filtered.take(75).toList();

      await _loadUserProfiles(limited, isInitialLoad);

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

      Future.microtask(() => notifyListeners());
    } catch (e) {
      _errorMessage = 'Failed to update display data: $e';
      debugPrint('[NotificationProvider] Update display data error: $e');
      notifyListeners();
    } finally {
      _processingUpdate = false;
    }
  }

  Future<void> _loadUserProfiles(List<NotificationModel> notifications, bool isInitialLoad) async {
    final npubs = notifications.map((n) => n.author).toSet();
    final loadedProfiles = <String, UserModel?>{};
    final now = DateTime.now();

    final npubsToLoad = npubs.where((npub) {
      if (_userProfiles.containsKey(npub) && !isInitialLoad) {
        final lastLoadTime = _profileLoadTimes[npub];
        if (lastLoadTime != null && now.difference(lastLoadTime).inMinutes < 10) {
          return false;
        }
      }
      return true;
    }).toList();

    final chunks = <List<String>>[];
    for (int i = 0; i < npubsToLoad.length; i += 10) {
      chunks.add(npubsToLoad.skip(i).take(10).toList());
    }

    for (final chunk in chunks) {
      await Future.wait(chunk.map((npub) async {
        try {
          UserModel? profile;

          if (_userProvider != null) {
            profile = _userProvider!.getUser(npub);
            if (profile == null) {
              profile = await _userProvider!.loadUser(npub);
            }
          } else if (_dataService != null) {
            final profileData = await _dataService!.getCachedUserProfile(npub);
            profile = UserModel.fromCachedProfile(npub, profileData);
          }

          loadedProfiles[npub] = profile;
          _profileLoadTimes[npub] = now;
        } catch (e) {
          debugPrint('[NotificationProvider] Error loading profile for $npub: $e');
          loadedProfiles[npub] = null;
        }
      }));
    }

    _userProfiles = {..._userProfiles, ...loadedProfiles};
  }

  void _performPeriodicCleanup() {
    final now = DateTime.now();
    if (now.difference(_lastCleanup).inMinutes < 5) return;

    _lastCleanup = now;

    final oldLoadTimes = <String>[];
    for (final entry in _profileLoadTimes.entries) {
      if (now.difference(entry.value).inHours > 1) {
        oldLoadTimes.add(entry.key);
      }
    }
    for (final key in oldLoadTimes) {
      _profileLoadTimes.remove(key);
    }

    if (_userProfiles.length > 200) {
      final sortedByTime = _profileLoadTimes.entries.toList()..sort((a, b) => a.value.compareTo(b.value));

      final keysToRemove = sortedByTime.take(_userProfiles.length - 150).map((e) => e.key).toList();

      for (final key in keysToRemove) {
        _userProfiles.remove(key);
        _profileLoadTimes.remove(key);
      }
    }

    debugPrint('[NotificationProvider] Periodic cleanup completed');
  }

  void _updateUnreadCount() {
    _unreadCount = _notifications.where((n) => !n.isRead).length;
  }

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
    if (_processingUpdate) return;
    await _loadNotifications();
  }

  void optimizeMemory() {
    if (_notifications.length > 300) {
      _notifications = _notifications.take(300).toList();
    }

    if (_userProfiles.length > 100) {
      final sortedByTime = _profileLoadTimes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

      final keysToKeep = sortedByTime.take(100).map((e) => e.key).toSet();
      _userProfiles.removeWhere((key, value) => !keysToKeep.contains(key));
      _profileLoadTimes.removeWhere((key, value) => !keysToKeep.contains(key));
    }

    debugPrint('[NotificationProvider] Memory optimization completed');
  }

  Map<String, int> getMemoryStats() {
    return {
      'notifications': _notifications.length,
      'displayNotifications': _displayNotifications.length,
      'userProfiles': _userProfiles.length,
      'profileLoadTimes': _profileLoadTimes.length,
    };
  }

  @override
  void dispose() {
    _dataService?.notificationsNotifier.removeListener(_handleDataServiceUpdate);
    super.dispose();
  }
}
