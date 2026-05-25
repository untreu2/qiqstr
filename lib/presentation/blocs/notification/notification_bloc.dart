import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../domain/entities/notification_item.dart';
import 'notification_event.dart' as notification_event;
import 'notification_state.dart';

class NotificationBloc
    extends Bloc<notification_event.NotificationEvent, NotificationState> {
  final NotificationRepository _notificationRepository;
  final SyncService _syncService;
  final AuthService _authService;

  final Set<String> _readNotificationIds = {};
  final List<NotificationItem> _olderNotifications = [];
  final Set<String> _olderIds = {};
  String? _currentUserHex;
  StreamSubscription<List<NotificationItem>>? _notificationSubscription;

  static const int _liveWatchLimit = 200;
  static const int _loadMorePageSize = 100;

  NotificationBloc({
    required NotificationRepository notificationRepository,
    required SyncService syncService,
    required AuthService authService,
  })  : _notificationRepository = notificationRepository,
        _syncService = syncService,
        _authService = authService,
        super(const NotificationInitial()) {
    on<notification_event.NotificationsLoadRequested>(
        _onNotificationsLoadRequested);
    on<notification_event.NotificationsRefreshRequested>(
        _onNotificationsRefreshRequested);
    on<notification_event.NotificationsLoadMoreRequested>(
        _onNotificationsLoadMoreRequested);
    on<notification_event.NotificationRead>(_onNotificationRead);
    on<notification_event.AllNotificationsRead>(_onAllNotificationsRead);
    on<notification_event.NotificationsMarkAllAsReadRequested>(
        _onNotificationsMarkAllAsReadRequested);
    on<_NotificationsUpdated>(_onNotificationsUpdated);

    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final currentUserHex = _authService.currentUserPubkeyHex;
    if (currentUserHex != null && currentUserHex.isNotEmpty) {
      add(const notification_event.NotificationsLoadRequested());
    }
  }

  Future<void> _onNotificationsLoadRequested(
    notification_event.NotificationsLoadRequested event,
    Emitter<NotificationState> emit,
  ) async {
    final currentUserHex = _authService.currentUserPubkeyHex;
    if (currentUserHex == null) {
      emit(const NotificationError('Not authenticated'));
      return;
    }

    _currentUserHex = currentUserHex;
    _olderNotifications.clear();
    _olderIds.clear();

    emit(NotificationsLoaded(
      notifications: const [],
      unreadCount: 0,
      currentUserHex: currentUserHex,
    ));

    _watchNotifications(currentUserHex);
    _syncInBackground(currentUserHex);
  }

  void _watchNotifications(String userHex) {
    _notificationSubscription?.cancel();
    _notificationSubscription = _notificationRepository
        .watchNotifications(userHex, limit: _liveWatchLimit)
        .listen((notifications) {
      if (isClosed) return;
      add(_NotificationsUpdated(notifications));
    });
  }

  void _onNotificationsUpdated(
    _NotificationsUpdated event,
    Emitter<NotificationState> emit,
  ) {
    if (state is! NotificationsLoaded) return;
    final currentState = state as NotificationsLoaded;

    final merged = _mergeWithOlder(event.notifications);
    final processedNotifications = _processNotifications(merged);
    final unreadCount = processedNotifications.where((n) {
      final isRead = n['isRead'] as bool? ?? false;
      return !isRead;
    }).length;

    emit(currentState.copyWith(
      notifications: processedNotifications,
      unreadCount: unreadCount,
    ));
  }

  List<NotificationItem> _mergeWithOlder(List<NotificationItem> live) {
    if (_olderNotifications.isEmpty) return live;

    final liveIds = live.map((n) => n.id).toSet();
    final combined = <NotificationItem>[...live];
    for (final older in _olderNotifications) {
      if (!liveIds.contains(older.id)) {
        combined.add(older);
      }
    }
    combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return combined;
  }

  void _syncInBackground(String userHex) {
    Future.microtask(() async {
      if (isClosed) return;
      try {
        await _syncService.syncNotifications(userHex);
      } catch (_) {}
    });
  }

  Future<void> _onNotificationsRefreshRequested(
    notification_event.NotificationsRefreshRequested event,
    Emitter<NotificationState> emit,
  ) async {
    if (_currentUserHex == null) return;
    try {
      await _syncService.syncNotifications(_currentUserHex!, force: true);
    } catch (_) {}
  }

  Future<void> _onNotificationsLoadMoreRequested(
    notification_event.NotificationsLoadMoreRequested event,
    Emitter<NotificationState> emit,
  ) async {
    if (state is! NotificationsLoaded) return;
    final currentState = state as NotificationsLoaded;
    if (currentState.isLoadingMore || currentState.hasReachedEnd) return;
    final userHex = _currentUserHex;
    if (userHex == null) return;

    final notifications = currentState.notifications;
    if (notifications.isEmpty) return;

    final oldestVisible = notifications.last['createdAt'] as int? ?? 0;
    if (oldestVisible == 0) return;

    emit(currentState.copyWith(isLoadingMore: true));

    final remoteCount = await _syncService.syncOlderNotifications(
      userHex,
      beforeTimestamp: oldestVisible,
      limit: _loadMorePageSize,
    );

    if (isClosed) return;

    final localOlder = await _notificationRepository.getNotificationsBefore(
      userHex,
      beforeTimestamp: oldestVisible,
      limit: _loadMorePageSize,
    );

    if (isClosed) return;

    var addedNew = false;
    for (final item in localOlder) {
      if (item.id.isEmpty) continue;
      if (_olderIds.add(item.id)) {
        _olderNotifications.add(item);
        addedNew = true;
      }
    }

    if (state is! NotificationsLoaded) return;
    final latestState = state as NotificationsLoaded;

    if (!addedNew && remoteCount == 0) {
      emit(latestState.copyWith(
        isLoadingMore: false,
        hasReachedEnd: true,
      ));
      return;
    }

    final liveIds = notifications.map((n) => n['id'] as String? ?? '').toSet();
    final liveAsItems = notifications.map((n) {
      return NotificationItem(
        id: n['id'] as String? ?? '',
        type: _parseType(n['type'] as String? ?? ''),
        fromPubkey: n['fromPubkey'] as String? ?? '',
        targetNoteId: n['targetEventId'] as String?,
        content: n['content'] as String?,
        createdAt: n['createdAt'] as int? ?? 0,
        fromName: n['fromName'] as String?,
        fromImage: n['fromImage'] as String?,
        zapAmount: n['zapAmount'] as int?,
      );
    }).where((i) => liveIds.contains(i.id)).toList();

    final merged = _mergeWithOlder(liveAsItems);
    final processed = _processNotifications(merged);
    final unreadCount = processed.where((n) {
      final isRead = n['isRead'] as bool? ?? false;
      return !isRead;
    }).length;

    emit(latestState.copyWith(
      notifications: processed,
      unreadCount: unreadCount,
      isLoadingMore: false,
      hasReachedEnd: localOlder.isEmpty,
    ));
  }

  NotificationType _parseType(String type) {
    return switch (type) {
      'reply' => NotificationType.reply,
      'quote' => NotificationType.quote,
      'reaction' => NotificationType.reaction,
      'repost' => NotificationType.repost,
      'zap' => NotificationType.zap,
      _ => NotificationType.mention,
    };
  }

  List<Map<String, dynamic>> _processNotifications(
      List<NotificationItem> items) {
    return items.map((n) {
      final id = n.id;
      return {
        'id': id,
        'type': n.type.name,
        'content': n.content,
        'author': n.fromPubkey,
        'fromPubkey': n.fromPubkey,
        'fromName': n.fromName,
        'fromImage': n.fromImage,
        'picture': n.fromImage ?? '',
        'name': n.fromName ?? '',
        'targetEventId': n.targetNoteId,
        'createdAt': n.createdAt,
        'zapAmount': n.zapAmount ?? 0,
        'isRead': _readNotificationIds.contains(id),
      };
    }).toList();
  }

  Future<void> _onNotificationsMarkAllAsReadRequested(
    notification_event.NotificationsMarkAllAsReadRequested event,
    Emitter<NotificationState> emit,
  ) async {
    await _onAllNotificationsRead(
        const notification_event.AllNotificationsRead(), emit);
  }

  Future<void> _onNotificationRead(
    notification_event.NotificationRead event,
    Emitter<NotificationState> emit,
  ) async {
    final currentState = state;
    if (currentState is NotificationsLoaded) {
      _readNotificationIds.add(event.notificationId);

      final updatedNotifications = currentState.notifications.map((n) {
        final notificationId = n['id'] as String? ?? '';
        if (notificationId.isNotEmpty &&
            notificationId == event.notificationId) {
          return {...n, 'isRead': true};
        }
        return n;
      }).toList();

      final unreadCount = updatedNotifications.where((n) {
        final isRead = n['isRead'] as bool? ?? false;
        return !isRead;
      }).length;

      emit(currentState.copyWith(
        notifications: updatedNotifications,
        unreadCount: unreadCount,
      ));
    }
  }

  Future<void> _onAllNotificationsRead(
    notification_event.AllNotificationsRead event,
    Emitter<NotificationState> emit,
  ) async {
    final currentState = state;
    if (currentState is NotificationsLoaded) {
      for (final n in currentState.notifications) {
        final id = n['id'] as String? ?? '';
        if (id.isNotEmpty) {
          _readNotificationIds.add(id);
        }
      }

      final updatedNotifications = currentState.notifications.map((n) {
        return {...n, 'isRead': true};
      }).toList();

      emit(currentState.copyWith(
        notifications: updatedNotifications,
        unreadCount: 0,
      ));
    }
  }

  @override
  Future<void> close() {
    _notificationSubscription?.cancel();
    return super.close();
  }
}

class _NotificationsUpdated extends notification_event.NotificationEvent {
  final List<NotificationItem> notifications;
  const _NotificationsUpdated(this.notifications);

  @override
  List<Object?> get props => [notifications];
}
