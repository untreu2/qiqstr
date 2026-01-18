import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/base/result.dart';
import '../services/auth_service.dart';
import '../services/network_service.dart';
import '../services/validation_service.dart';
import '../services/data_service.dart';
import '../services/event_cache_service.dart';

class NotificationRepository {
  final AuthService _authService;
  final DataService _nostrDataService;
  final EventCacheService _eventCacheService = EventCacheService.instance;

  final StreamController<List<Map<String, dynamic>>> _notificationsController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<int> _unreadCountController = StreamController<int>.broadcast();
  final StreamController<bool> _hasNewNotificationsController = StreamController<bool>.broadcast();
  final Map<String, Map<String, dynamic>> _userProfilesCache = {};
  final List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;
  String? _currentUserHex;

  StreamSubscription<List<Map<String, dynamic>>>? _notificationStreamSubscription;
  DateTime? _lastDebounceTime;
  static const Duration _debounceDelay = Duration(milliseconds: 2000);
  static const String _lastVisitTimestampKey = 'last_visit_notification_page_timestamp';

  NotificationRepository({
    required AuthService authService,
    required NetworkService networkService,
    required ValidationService validationService,
    required DataService nostrDataService,
  })  : _authService = authService,
        _nostrDataService = nostrDataService {
    _setupRealTimeNotifications();
  }

  Stream<List<Map<String, dynamic>>> get notificationsStream => _notificationsController.stream;
  Stream<int> get unreadCountStream => _unreadCountController.stream;
  Stream<bool> get hasNewNotificationsStream => _hasNewNotificationsController.stream;

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

  void _debouncedProcessNotifications(List<Map<String, dynamic>> newNotifications) {
    final debounceTime = DateTime.now();
    _lastDebounceTime = debounceTime;

    Future.delayed(_debounceDelay, () async {
      if (_lastDebounceTime == debounceTime) {
        await _processNotifications(newNotifications);
      }
    });
  }

  Future<void> _processNotifications(List<Map<String, dynamic>> newNotifications) async {
    debugPrint('[NotificationRepository] Processing ${newNotifications.length} notifications');

    if (_currentUserHex == null) {
      await _initializeCurrentUser();
      if (_currentUserHex == null) {
        debugPrint('[NotificationRepository] Could not get current user, skipping filtering');
        return;
      }
    }

    final filteredNotifications = _filterSelfNotifications(newNotifications);
    final addedNotifications = await _addNewNotifications(filteredNotifications);

    if (addedNotifications.isNotEmpty) {
      _sortAndEmitNotifications(addedNotifications.length);
    }
  }

  List<Map<String, dynamic>> _filterSelfNotifications(List<Map<String, dynamic>> notifications) {
    return notifications.where((notification) {
      final author = notification['author'] as String? ?? '';
      return author != _currentUserHex;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _addNewNotifications(List<Map<String, dynamic>> filteredNotifications) async {
    final existingIds = _notifications.map((n) => n['id'] as String? ?? '').where((id) => id.isNotEmpty).toSet();
    final newNotifications = filteredNotifications.where((notification) {
      final notificationId = notification['id'] as String? ?? '';
      return notificationId.isNotEmpty && !existingIds.contains(notificationId);
    }).toList();

    if (newNotifications.isNotEmpty) {
      final lastVisitTimestamp = await _getLastVisitTimestamp();
      bool hasNewAfterVisit = false;

      if (lastVisitTimestamp == null) {
        hasNewAfterVisit = true;
        debugPrint('[NotificationRepository] _addNewNotifications: hasNew=true (no visit timestamp)');
      } else {
        hasNewAfterVisit = newNotifications.any((notification) {
          final notificationTime = _getNotificationTimestamp(notification);
          final isNew = notificationTime.isAfter(lastVisitTimestamp);
          if (isNew) {
            debugPrint('[NotificationRepository] _addNewNotifications: found new notification after visit (time: $notificationTime, visit: $lastVisitTimestamp)');
          }
          return isNew;
        });
        debugPrint('[NotificationRepository] _addNewNotifications: hasNew=$hasNewAfterVisit (checked ${newNotifications.length} new notifications)');
      }

      for (final notification in newNotifications) {
        _insertSortedNotification(notification);
      }
      _unreadCount += newNotifications.length;

      if (hasNewAfterVisit) {
        _hasNewNotificationsController.add(true);
      } else {
        final hasNew = await hasNewNotifications();
        debugPrint('[NotificationRepository] _addNewNotifications: hasNew=$hasNew (from full check), emitting to stream');
        _hasNewNotificationsController.add(hasNew);
      }
    }

    return newNotifications;
  }

  DateTime _getNotificationTimestamp(Map<String, dynamic> notification) {
    final timestamp = notification['timestamp'];
    if (timestamp is DateTime) {
      return timestamp;
    }
    if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    final createdAt = notification['created_at'] as int? ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
  }

  void _insertSortedNotification(Map<String, dynamic> notification) {
    int left = 0;
    int right = _notifications.length;
    final notificationTime = _getNotificationTimestamp(notification);

    while (left < right) {
      final mid = (left + right) ~/ 2;
      if (_getNotificationTimestamp(_notifications[mid]).isAfter(notificationTime)) {
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

  Future<Result<List<Map<String, dynamic>>>> getNotifications({
    DateTime? since,
  }) async {
    try {
      if (_currentUserHex == null) {
        await _initializeCurrentUser();
        if (_currentUserHex == null) {
          return const Result.error('No authenticated user hex pubkey');
        }
      }

      final cachedEvents = await _eventCacheService.getEventsByPTags(
        [_currentUserHex!],
        [1, 6, 7, 9735],
        since: since,
        limit: 100,
      );

      final notifications = <Map<String, dynamic>>[];

      for (final event in cachedEvents) {
        final eventData = event.toEventData();
        final notification = _processNotificationEvent(eventData);
        if (notification != null) {
          notifications.add(notification);
        }
      }

      notifications.sort((a, b) {
        final aTime = a['timestamp'] as DateTime? ?? DateTime(2000);
        final bTime = b['timestamp'] as DateTime? ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });

      final filteredNotifications = _filterSelfNotifications(notifications);

      _notifications.clear();
      _notifications.addAll(filteredNotifications);
      _unreadCount = filteredNotifications.length;

      final hasNew = await hasNewNotifications();
      debugPrint('[NotificationRepository] getNotifications: hasNew=$hasNew, emitting to stream');
      _hasNewNotificationsController.add(hasNew);

      _notificationsController.add(List.unmodifiable(_notifications));
      _unreadCountController.add(_unreadCount);

      return Result.success(filteredNotifications);
    } catch (e) {
      return Result.error('Failed to get notifications: $e');
    }
  }


  List<dynamic> groupNotifications(List<Map<String, dynamic>> notifications) {
    final groups = <String, List<Map<String, dynamic>>>{};
    final standaloneNotifications = <Map<String, dynamic>>[];

    for (final notification in notifications) {
      final type = notification['type'] as String? ?? '';
      if (type == 'zap' || type == 'mention' || type == 'follow' || type == 'unfollow') {
        standaloneNotifications.add(notification);
      } else {
        final targetEventId = notification['targetEventId'] as String? ?? '';
        final key = '${type}_$targetEventId';
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
      final aTime = a is NotificationGroup 
          ? _getNotificationTimestamp(a.notifications.first) 
          : _getNotificationTimestamp(a as Map<String, dynamic>);
      final bTime = b is NotificationGroup 
          ? _getNotificationTimestamp(b.notifications.first) 
          : _getNotificationTimestamp(b as Map<String, dynamic>);
      return bTime.compareTo(aTime);
    });

    return result;
  }

  Future<Result<void>> markAllAsRead() async {
    try {
      _unreadCount = 0;
      _unreadCountController.add(_unreadCount);

      await saveLastVisitTimestamp();

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to mark notifications as read: $e');
    }
  }


  Future<bool> hasNewNotifications() async {
    if (_notifications.isEmpty) {
      debugPrint('[NotificationRepository] hasNewNotifications: false (no notifications)');
      return false;
    }

    final lastVisitTimestamp = await _getLastVisitTimestamp();
    if (lastVisitTimestamp == null) {
      debugPrint('[NotificationRepository] hasNewNotifications: true (no visit timestamp, ${_notifications.length} notifications)');
      return _notifications.isNotEmpty;
    }

    final hasNew = _notifications.any((notification) {
      final notificationTime = _getNotificationTimestamp(notification);
      return notificationTime.isAfter(lastVisitTimestamp);
    });
    
    debugPrint('[NotificationRepository] hasNewNotifications: $hasNew (lastVisit: $lastVisitTimestamp, notifications: ${_notifications.length})');
    return hasNew;
  }

  Future<void> saveLastVisitTimestamp() async {
    try {
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastVisitTimestampKey, now.millisecondsSinceEpoch);
      debugPrint('[NotificationRepository] saveLastVisitTimestamp: saved $now');
      final hasNew = await hasNewNotifications();
      debugPrint('[NotificationRepository] saveLastVisitTimestamp: hasNew=$hasNew, emitting to stream');
      _hasNewNotificationsController.add(hasNew);
    } catch (e) {
      debugPrint('[NotificationRepository] Error saving last visit timestamp: $e');
    }
  }

  Future<DateTime?> _getLastVisitTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestampMs = prefs.getInt(_lastVisitTimestampKey);
      if (timestampMs != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestampMs);
      }
      return null;
    } catch (e) {
      debugPrint('[NotificationRepository] Error getting last visit timestamp: $e');
      return null;
    }
  }

  Future<Result<Map<String, dynamic>?>> getUserProfile(String npub) async {
    try {
      if (_userProfilesCache.containsKey(npub)) {
        return Result.success(_userProfilesCache[npub]);
      }

      final user = {
        'pubkeyHex': npub,
        'name': npub.length > 8 ? npub.substring(0, 8) : npub,
        'about': '',
        'nip05': '',
        'banner': '',
        'profileImage': '',
        'lud16': '',
        'website': '',
        'updatedAt': DateTime.now(),
      };

      _userProfilesCache[npub] = user;
      return Result.success(user);
    } catch (e) {
      return Result.error('Failed to get user profile: $e');
    }
  }

  int getNotificationsLast24Hours() {
    final twentyFourHoursAgo = DateTime.now().subtract(const Duration(hours: 24));
    return _notifications.where((n) => _getNotificationTimestamp(n).isAfter(twentyFourHoursAgo)).length;
  }

  int get unreadCount => _unreadCount;

  Map<String, Map<String, dynamic>> get userProfiles => Map.unmodifiable(_userProfilesCache);

  Future<Result<List<Map<String, dynamic>>>> refreshNotifications() async {
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
        final notificationTime = _getNotificationTimestamp(notification);
        if (notificationTime.isBefore(cutoffTime)) {
          final isRead = notification['isRead'] as bool? ?? false;
          if (!isRead) {
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

  Map<String, dynamic>? _processNotificationEvent(Map<String, dynamic> eventData) {
    try {
      final eventId = eventData['id'] as String? ?? '';
      final eventKind = eventData['kind'] as int? ?? 0;
      final eventPubkey = eventData['pubkey'] as String? ?? '';
      final eventCreatedAt = eventData['created_at'] as int? ?? 0;
      final eventTags = eventData['tags'] as List<dynamic>? ?? [];
      final eventContent = eventData['content'] as String? ?? '';

      if (eventId.isEmpty || eventPubkey.isEmpty || _currentUserHex == null) {
        return null;
      }

      if (eventPubkey == _currentUserHex) {
        return null;
      }

      String? targetEventId;
      String notificationType = 'mention';
      int zapAmount = 0;
      String actualAuthor = eventPubkey;

      if (eventKind == 1) {
        final mentionedUser = _getTagValue(eventTags, 'p');
        if (mentionedUser == _currentUserHex) {
          notificationType = 'mention';
          targetEventId = _getTagValue(eventTags, 'e') ?? eventId;
        } else {
          return null;
        }
      } else if (eventKind == 6) {
        notificationType = 'repost';
        targetEventId = _getTagValue(eventTags, 'e');
      } else if (eventKind == 7) {
        notificationType = 'reaction';
        targetEventId = _getTagValue(eventTags, 'e');
      } else if (eventKind == 9735) {
        notificationType = 'zap';
        targetEventId = _getTagValue(eventTags, 'e');

        final bolt11 = _getTagValue(eventTags, 'bolt11') ?? '';
        final descriptionJson = _getTagValue(eventTags, 'description') ?? '';

        zapAmount = _parseAmountFromBolt11(bolt11);

        try {
          final decoded = jsonDecode(descriptionJson);
          if (decoded is Map<String, dynamic> &&
              decoded.containsKey('pubkey')) {
            actualAuthor = decoded['pubkey'] as String;
          }
        } catch (e) {}
      } else {
        return null;
      }

      final timestamp =
          DateTime.fromMillisecondsSinceEpoch(eventCreatedAt * 1000);
      targetEventId ??= eventId;

      final authorNpub = _authService.hexToNpub(actualAuthor) ?? actualAuthor;

      return <String, dynamic>{
        'id': eventId,
        'type': notificationType,
        'author': authorNpub,
        'targetEventId': targetEventId,
        'timestamp': timestamp,
        'content': eventContent,
        'fetchedAt': DateTime.now(),
        'isRead': false,
        'amount': zapAmount,
      };
    } catch (e) {
      return null;
    }
  }

  String? _getTagValue(List<dynamic> tags, String tagType, {int index = 1}) {
    for (final tag in tags) {
      if (tag is List &&
          tag.isNotEmpty &&
          tag[0] == tagType &&
          tag.length > index) {
        return tag[index] as String?;
      }
    }
    return null;
  }

  int _parseAmountFromBolt11(String bolt11) {
    final match =
        RegExp(r'^lnbc(\d+)([munp]?)', caseSensitive: false).firstMatch(bolt11);
    if (match == null) return 0;

    final number = int.tryParse(match.group(1) ?? '') ?? 0;
    final unit = match.group(2)?.toLowerCase();

    switch (unit) {
      case 'm':
        return number * 100000;
      case 'u':
        return number * 100;
      case 'n':
        return (number * 0.1).round();
      case 'p':
        return (number * 0.001).round();
      default:
        return number * 1000;
    }
  }

  void dispose() {
    debugPrint('[NotificationRepository] Disposing notification repository');
    _notificationStreamSubscription?.cancel();
    _notificationsController.close();
    _unreadCountController.close();
    _hasNewNotificationsController.close();
    _notifications.clear();
    _userProfilesCache.clear();
  }
}

class NotificationGroup {
  final List<Map<String, dynamic>> notifications;

  NotificationGroup({required this.notifications});

  String get type => notifications.first['type'] as String? ?? '';
  DateTime get timestamp {
    final timestamp = notifications.first['timestamp'];
    if (timestamp is DateTime) {
      return timestamp;
    }
    if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    final createdAt = notifications.first['created_at'] as int? ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
  }
  String get targetEventId => notifications.first['targetEventId'] as String? ?? '';
}
