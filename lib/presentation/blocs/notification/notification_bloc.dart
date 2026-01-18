import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/data_service.dart';
import 'notification_event.dart' as notification_event;
import 'notification_state.dart';

class NotificationBloc extends Bloc<notification_event.NotificationEvent, NotificationState> {
  final NotificationRepository _notificationRepository;
  final AuthRepository _authRepository;
  final DataService _nostrDataService;

  final List<StreamSubscription> _subscriptions = [];

  NotificationBloc({
    required NotificationRepository notificationRepository,
    required UserRepository userRepository,
    required AuthRepository authRepository,
    required DataService nostrDataService,
  })  : _notificationRepository = notificationRepository,
        _authRepository = authRepository,
        _nostrDataService = nostrDataService,
        super(const NotificationInitial()) {
    on<notification_event.NotificationsLoadRequested>(_onNotificationsLoadRequested);
    on<notification_event.NotificationsLoaded>(_onNotificationsLoaded);
    on<notification_event.NotificationsRefreshRequested>(_onNotificationsRefreshRequested);
    on<notification_event.NotificationsRefreshed>(_onNotificationsRefreshed);
    on<notification_event.NotificationRead>(_onNotificationRead);
    on<notification_event.AllNotificationsRead>(_onAllNotificationsRead);
    on<notification_event.NotificationsMarkAllAsReadRequested>(_onNotificationsMarkAllAsReadRequested);

    _loadCurrentUser();
    _subscribeToNotificationUpdates();
  }

  Future<void> _loadCurrentUser() async {
    final result = await _authRepository.getCurrentUserNpub();
    final npub = result.fold((n) => n, (_) => null) ?? '';
    if (npub.isNotEmpty) {
      add(notification_event.NotificationsRefreshed());
    }
  }

  void _subscribeToNotificationUpdates() {
    _subscriptions.add(
      _nostrDataService.notificationsStream.listen((newNotifications) {
        final currentState = state;
        if (currentState is NotificationsLoaded) {
          add(const notification_event.NotificationsRefreshed());
        }
      }),
    );
  }

  Future<void> _onNotificationsLoadRequested(
    notification_event.NotificationsLoadRequested event,
    Emitter<NotificationState> emit,
  ) async {
    await _onNotificationsLoaded(const notification_event.NotificationsLoaded(), emit);
  }

  Future<void> _onNotificationsLoaded(
    notification_event.NotificationsLoaded event,
    Emitter<NotificationState> emit,
  ) async {
    emit(const NotificationLoading());

    final result = await _notificationRepository.getNotifications();

    await result.fold(
      (notifications) async {
        final groupedNotifications = _notificationRepository.groupNotifications(notifications);
        final unreadCount = notifications.where((n) {
          final isRead = n['isRead'] as bool? ?? false;
          return !isRead;
        }).length;

        final currentUserResult = await _authRepository.getCurrentUserNpub();
        final currentUserNpub = currentUserResult.fold((n) => n, (_) => null) ?? '';

        emit(NotificationsLoaded(
          notifications: groupedNotifications,
          unreadCount: unreadCount,
          userProfiles: {},
          currentUserNpub: currentUserNpub,
        ));
      },
      (error) async {
        emit(NotificationError(error));
      },
    );
  }

  Future<void> _onNotificationsRefreshRequested(
    notification_event.NotificationsRefreshRequested event,
    Emitter<NotificationState> emit,
  ) async {
    await _onNotificationsRefreshed(const notification_event.NotificationsRefreshed(), emit);
  }

  Future<void> _onNotificationsRefreshed(
    notification_event.NotificationsRefreshed event,
    Emitter<NotificationState> emit,
  ) async {
    await _onNotificationsLoaded(const notification_event.NotificationsLoaded(), emit);
  }

  Future<void> _onNotificationsMarkAllAsReadRequested(
    notification_event.NotificationsMarkAllAsReadRequested event,
    Emitter<NotificationState> emit,
  ) async {
    await _onAllNotificationsRead(const notification_event.AllNotificationsRead(), emit);
  }

  Future<void> _onNotificationRead(
    notification_event.NotificationRead event,
    Emitter<NotificationState> emit,
  ) async {
    final currentState = state;
    if (currentState is NotificationsLoaded) {
      final updatedNotifications = currentState.notifications.map((n) {
        final notificationId = n['id'] as String? ?? '';
        if (notificationId.isNotEmpty && notificationId == event.notificationId) {
          final updatedNotification = Map<String, dynamic>.from(n);
          updatedNotification['isRead'] = true;
          return updatedNotification;
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
    final result = await _notificationRepository.markAllAsRead();

    result.fold(
      (_) {
        final currentState = state;
        if (currentState is NotificationsLoaded) {
          final updatedNotifications = currentState.notifications.map((n) {
            final updatedNotification = Map<String, dynamic>.from(n);
            updatedNotification['isRead'] = true;
            return updatedNotification;
          }).toList();

          emit(currentState.copyWith(
            notifications: updatedNotifications,
            unreadCount: 0,
          ));
        }
      },
      (error) => emit(NotificationError(error)),
    );
  }

  @override
  Future<void> close() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    return super.close();
  }
}
