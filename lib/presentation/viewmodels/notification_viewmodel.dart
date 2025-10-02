import 'dart:async';

import 'package:flutter/widgets.dart';
import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../core/base/app_error.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/nostr_data_service.dart';
import '../../models/notification_model.dart';
import '../../models/user_model.dart';

/// ViewModel for notification-related screens
/// Handles notification loading, grouping, and user interactions
class NotificationViewModel extends BaseViewModel with CommandMixin {
  final NotificationRepository _notificationRepository;
  final UserRepository _userRepository;
  final NostrDataService _nostrDataService;

  NotificationViewModel({
    required NotificationRepository notificationRepository,
    required UserRepository userRepository,
    required NostrDataService nostrDataService,
  })  : _notificationRepository = notificationRepository,
        _userRepository = userRepository,
        _nostrDataService = nostrDataService;

  // State
  UIState<List<dynamic>> _notificationsState = const InitialState();
  UIState<List<dynamic>> get notificationsState => _notificationsState;

  UIState<int> _unreadCountState = const InitialState();
  UIState<int> get unreadCountState => _unreadCountState;

  final Map<String, UserModel> _userProfiles = {};
  Map<String, UserModel> get userProfiles => Map.unmodifiable(_userProfiles);

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Commands - using nullable fields to prevent late initialization errors
  LoadNotificationsCommand? _loadNotificationsCommand;
  RefreshNotificationsCommand? _refreshNotificationsCommand;
  MarkAllAsReadCommand? _markAllAsReadCommand;

  // Getters for commands
  LoadNotificationsCommand get loadNotificationsCommand => _loadNotificationsCommand ??= LoadNotificationsCommand(this);
  RefreshNotificationsCommand get refreshNotificationsCommand => _refreshNotificationsCommand ??= RefreshNotificationsCommand(this);
  MarkAllAsReadCommand get markAllAsReadCommand => _markAllAsReadCommand ??= MarkAllAsReadCommand(this);

  @override
  void initialize() {
    super.initialize();

    // Register commands lazily
    registerCommand('loadNotifications', loadNotificationsCommand);
    registerCommand('refreshNotifications', refreshNotificationsCommand);
    registerCommand('markAllAsRead', markAllAsReadCommand);

    _subscribeToNotificationUpdates();
    _isInitialized = true;
  }

  /// Load notifications
  Future<void> loadNotifications() async {
    await executeOperation('loadNotifications', () async {
      _notificationsState = const LoadingState();
      safeNotifyListeners();

      final result = await _notificationRepository.getNotifications();

      result.fold(
        (notifications) async {
          // Group notifications
          final groupedNotifications = _notificationRepository.groupNotifications(notifications);

          // Load user profiles for notification authors
          await _loadUserProfiles(notifications);

          // Fetch target events for QuoteWidgets
          await _fetchTargetEvents(notifications);

          _notificationsState = groupedNotifications.isEmpty ? const EmptyState('No notifications yet') : LoadedState(groupedNotifications);
        },
        (error) => _notificationsState = ErrorState(error),
      );

      safeNotifyListeners();
    });
  }

  /// Refresh notifications
  Future<void> refreshNotifications() async {
    await executeOperation('refreshNotifications', () async {
      _notificationsState = const LoadingState(LoadingType.refreshing);
      safeNotifyListeners();

      final result = await _notificationRepository.refreshNotifications();

      result.fold(
        (notifications) async {
          // Group notifications
          final groupedNotifications = _notificationRepository.groupNotifications(notifications);

          // Load user profiles for notification authors
          await _loadUserProfiles(notifications);

          // Fetch target events for QuoteWidgets
          await _fetchTargetEvents(notifications);

          _notificationsState = groupedNotifications.isEmpty ? const EmptyState('No notifications yet') : LoadedState(groupedNotifications);
        },
        (error) => _notificationsState = ErrorState(error),
      );

      safeNotifyListeners();
    });
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    await executeOperation('markAllAsRead', () async {
      final result = await _notificationRepository.markAllAsRead();

      result.fold(
        (_) {
          _unreadCountState = const LoadedState(0);
        },
        (error) => setError(NetworkError(message: 'Failed to mark notifications as read: $error')),
      );

      safeNotifyListeners();
    }, showLoading: false);
  }

  /// Immediately reset unread count to 0 (for instant UI feedback)
  void resetUnreadCountImmediately() {
    _unreadCountState = const LoadedState(0);
    safeNotifyListeners();
  }

  /// Load user profiles for notification authors
  Future<void> _loadUserProfiles(List<NotificationModel> notifications) async {
    final authorNpubs = notifications.map((n) => n.author).toSet();

    for (final npub in authorNpubs) {
      if (!_userProfiles.containsKey(npub)) {
        final result = await _userRepository.getUserProfile(npub);
        result.fold(
          (user) => _userProfiles[npub] = user,
          (_) {}, // Ignore profile loading errors
        );
      }
    }
  }

  /// Fetch target events for notifications to prevent "Event not found" errors in QuoteWidgets
  Future<void> _fetchTargetEvents(List<NotificationModel> notifications) async {
    try {
      debugPrint(' [NotificationViewModel] Fetching target events for ${notifications.length} notifications');

      // Collect all target event IDs
      final targetEventIds = notifications.map((n) => n.targetEventId).where((id) => id.isNotEmpty).toSet().toList();

      if (targetEventIds.isNotEmpty) {
        debugPrint(' [NotificationViewModel] Found ${targetEventIds.length} target events to fetch');

        // Use the enhanced batch fetching method
        await _nostrDataService.fetchSpecificNotes(targetEventIds);

        debugPrint(' [NotificationViewModel] Target events fetch completed');
      } else {
        debugPrint(' [NotificationViewModel] No target events to fetch');
      }
    } catch (e) {
      debugPrint(' [NotificationViewModel] Error fetching target events: $e');
      // Don't throw - this is not critical, QuoteWidgets will handle missing events gracefully
    }
  }

  /// Subscribe to notification updates
  void _subscribeToNotificationUpdates() {
    addSubscription(
      _notificationRepository.notificationsStream.listen((notifications) {
        if (!isDisposed) {
          final groupedNotifications = _notificationRepository.groupNotifications(notifications);
          _notificationsState = groupedNotifications.isEmpty ? const EmptyState('No notifications yet') : LoadedState(groupedNotifications);
          safeNotifyListeners();
        }
      }),
    );

    addSubscription(
      _notificationRepository.unreadCountStream.listen((count) {
        if (!isDisposed) {
          _unreadCountState = LoadedState(count);
          safeNotifyListeners();
        }
      }),
    );
  }

  /// Build title for notification group
  String buildGroupTitle(dynamic item) {
    if (item is NotificationGroup) {
      final notifications = item.notifications;
      final first = notifications.first;
      final count = notifications.length;

      switch (first.type) {
        case 'reaction':
          if (count == 1) {
            final profile = _userProfiles[first.author];
            final name = profile?.name.isNotEmpty == true ? profile!.name : 'Someone';
            return '$name reacted to your post';
          } else {
            final personWord = count == 1 ? 'person' : 'people';
            return '$count $personWord reacted to your post';
          }
        case 'mention':
          if (count == 1) {
            final profile = _userProfiles[first.author];
            final name = profile?.name.isNotEmpty == true ? profile!.name : 'Someone';
            return '$name mentioned you';
          } else {
            final personWord = count == 1 ? 'person' : 'people';
            return '$count $personWord mentioned you';
          }
        case 'repost':
          if (count == 1) {
            final profile = _userProfiles[first.author];
            final name = profile?.name.isNotEmpty == true ? profile!.name : 'Someone';
            return '$name reposted your post';
          } else {
            final personWord = count == 1 ? 'person' : 'people';
            return '$count $personWord reposted your post';
          }
        default:
          return 'Notification';
      }
    } else if (item is NotificationModel) {
      final profile = _userProfiles[item.author];
      final name = profile?.name.isNotEmpty == true ? profile!.name : 'Someone';

      switch (item.type) {
        case 'zap':
          return '$name zapped your post ${item.amount} sats';
        case 'reaction':
          return '$name reacted to your post';
        case 'mention':
          return '$name mentioned you';
        case 'repost':
          return '$name reposted your post';
        default:
          return 'Notification from $name';
      }
    }

    return 'Notification';
  }

  /// Get notifications from last 24 hours
  int get notificationsLast24Hours => _notificationRepository.getNotificationsLast24Hours();

  /// Get current notifications
  List<dynamic> get displayNotifications {
    return _notificationsState.data ?? [];
  }

  /// Get current unread count
  int get unreadCount => _unreadCountState.data ?? _notificationRepository.unreadCount;

  /// Check if notifications are loading
  bool get isNotificationsLoading => _notificationsState.isLoading;

  /// Get notification error message if any
  String? get notificationErrorMessage => _notificationsState.error;

  @override
  void onRetry() {
    loadNotifications();
  }
}

/// Commands for NotificationViewModel
class LoadNotificationsCommand extends ParameterlessCommand {
  final NotificationViewModel _viewModel;

  LoadNotificationsCommand(this._viewModel);

  @override
  Future<void> executeImpl() => _viewModel.loadNotifications();
}

class RefreshNotificationsCommand extends ParameterlessCommand {
  final NotificationViewModel _viewModel;

  RefreshNotificationsCommand(this._viewModel);

  @override
  Future<void> executeImpl() => _viewModel.refreshNotifications();
}

class MarkAllAsReadCommand extends ParameterlessCommand {
  final NotificationViewModel _viewModel;

  MarkAllAsReadCommand(this._viewModel);

  @override
  Future<void> executeImpl() => _viewModel.markAllAsRead();
}
