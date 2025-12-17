import 'dart:async';

import 'package:flutter/widgets.dart';
import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../core/base/app_error.dart';
import '../../core/base/result.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/data_service.dart';
import '../../data/services/user_batch_fetcher.dart';
import '../../models/notification_model.dart';
import '../../models/user_model.dart';

class NotificationViewModel extends BaseViewModel with CommandMixin {
  final NotificationRepository _notificationRepository;
  final UserRepository _userRepository;
  final AuthRepository _authRepository;
  final DataService _nostrDataService;

  NotificationViewModel({
    required NotificationRepository notificationRepository,
    required UserRepository userRepository,
    required AuthRepository authRepository,
    required DataService nostrDataService,
  })  : _notificationRepository = notificationRepository,
        _userRepository = userRepository,
        _authRepository = authRepository,
        _nostrDataService = nostrDataService;

  UIState<List<dynamic>> _notificationsState = const InitialState();
  UIState<List<dynamic>> get notificationsState => _notificationsState;

  UIState<int> _unreadCountState = const InitialState();
  UIState<int> get unreadCountState => _unreadCountState;

  final Map<String, UserModel> _userProfiles = {};
  Map<String, UserModel> get userProfiles => Map.unmodifiable(_userProfiles);

  String _currentUserNpub = '';
  String get currentUserNpub => _currentUserNpub;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  LoadNotificationsCommand? _loadNotificationsCommand;
  RefreshNotificationsCommand? _refreshNotificationsCommand;
  MarkAllAsReadCommand? _markAllAsReadCommand;

  LoadNotificationsCommand get loadNotificationsCommand => _loadNotificationsCommand ??= LoadNotificationsCommand(this);
  RefreshNotificationsCommand get refreshNotificationsCommand => _refreshNotificationsCommand ??= RefreshNotificationsCommand(this);
  MarkAllAsReadCommand get markAllAsReadCommand => _markAllAsReadCommand ??= MarkAllAsReadCommand(this);

  @override
  void initialize() {
    super.initialize();

    registerCommand('loadNotifications', loadNotificationsCommand);
    registerCommand('refreshNotifications', refreshNotificationsCommand);
    registerCommand('markAllAsRead', markAllAsReadCommand);

    _loadCurrentUser();
    _subscribeToNotificationUpdates();
    _isInitialized = true;
  }

  Future<void> _loadCurrentUser() async {
    try {
      final result = await _authRepository.getCurrentUserNpub();
      result.fold(
        (npub) {
          _currentUserNpub = npub ?? '';
        },
        (_) {
          _currentUserNpub = '';
        },
      );
    } catch (e) {
      debugPrint('[NotificationViewModel] Error loading current user: $e');
      _currentUserNpub = '';
    }
  }

  Future<Result<UserModel>> getUserProfile(String npub) async {
    return await _userRepository.getUserProfile(npub);
  }

  Future<void> loadNotifications({int limit = 20}) async {
    await executeOperation('loadNotifications', () async {
      _notificationsState = const LoadingState();
      safeNotifyListeners();

      final result = await _notificationRepository.getNotifications(limit: limit);

      result.fold(
        (notifications) async {
          final groupedNotifications = _notificationRepository.groupNotifications(notifications);

          unawaited(_loadUserProfilesInBackground(notifications));
          unawaited(_fetchTargetEventsInBackground(notifications));

          _notificationsState = groupedNotifications.isEmpty ? const EmptyState('No notifications yet') : LoadedState(groupedNotifications);
        },
        (error) => _notificationsState = ErrorState(error),
      );

      safeNotifyListeners();
    });
  }

  Future<void> refreshNotifications({int limit = 20}) async {
    await executeOperation('refreshNotifications', () async {
      _notificationsState = const LoadingState(LoadingType.refreshing);
      safeNotifyListeners();

      final result = await _notificationRepository.refreshNotifications();

      result.fold(
        (notifications) async {
          final groupedNotifications = _notificationRepository.groupNotifications(notifications);

          unawaited(_loadUserProfilesInBackground(notifications));
          unawaited(_fetchTargetEventsInBackground(notifications));

          _notificationsState = groupedNotifications.isEmpty ? const EmptyState('No notifications yet') : LoadedState(groupedNotifications);
        },
        (error) => _notificationsState = ErrorState(error),
      );

      safeNotifyListeners();
    });
  }

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

  void resetUnreadCountImmediately() {
    _unreadCountState = const LoadedState(0);
    safeNotifyListeners();
  }

  Future<void> _loadUserProfilesInBackground(List<NotificationModel> notifications) async {
    try {
      final authorNpubs = notifications.map((n) => n.author).toSet().toList();
      final missingNpubs = authorNpubs.where((npub) => !_userProfiles.containsKey(npub)).toList();

      if (missingNpubs.isEmpty) return;

      final results = await _userRepository.getUserProfiles(
        missingNpubs,
        priority: FetchPriority.low,
      );

      for (final entry in results.entries) {
        entry.value.fold(
          (user) => _userProfiles[entry.key] = user,
          (_) {},
        );
      }

      safeNotifyListeners();
    } catch (e) {}
  }

  Future<void> _fetchTargetEventsInBackground(List<NotificationModel> notifications) async {
    try {
      final targetEventIds = notifications.map((n) => n.targetEventId).where((id) => id.isNotEmpty).toSet().toList();

      if (targetEventIds.isNotEmpty) {
        await _nostrDataService.fetchSpecificNotes(targetEventIds);
      }
    } catch (e) {}
  }

  void _subscribeToNotificationUpdates() {
    addSubscription(
      _notificationRepository.notificationsStream.listen((notifications) {
        if (!isDisposed) {
          final groupedNotifications = _notificationRepository.groupNotifications(notifications);

          unawaited(_loadUserProfilesInBackground(notifications));
          unawaited(_fetchTargetEventsInBackground(notifications));

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

  void unawaited(Future<void> future) {
    future.catchError((error) {});
  }

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

  int get notificationsLast24Hours => _notificationRepository.getNotificationsLast24Hours();

  List<dynamic> get displayNotifications {
    return _notificationsState.data ?? [];
  }

  int get unreadCount => _unreadCountState.data ?? _notificationRepository.unreadCount;

  bool get isNotificationsLoading => _notificationsState.isLoading;

  String? get notificationErrorMessage => _notificationsState.error;

  @override
  void onRetry() {
    loadNotifications();
  }
}

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
