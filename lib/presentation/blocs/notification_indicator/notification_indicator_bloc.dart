import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:bloc/bloc.dart';
import '../../../data/repositories/notification_repository.dart';
import 'notification_indicator_event.dart';
import 'notification_indicator_state.dart';

class NotificationIndicatorBloc extends Bloc<NotificationIndicatorEvent, NotificationIndicatorState> {
  final NotificationRepository _notificationRepository;
  StreamSubscription<bool>? _subscription;

  NotificationIndicatorBloc({
    required NotificationRepository notificationRepository,
  })  : _notificationRepository = notificationRepository,
        super(const NotificationIndicatorInitial()) {
    on<NotificationIndicatorInitialized>(_onNotificationIndicatorInitialized);
  }

  Future<void> _onNotificationIndicatorInitialized(
    NotificationIndicatorInitialized event,
    Emitter<NotificationIndicatorState> emit,
  ) async {
    final hasNew = await _notificationRepository.hasNewNotifications();
    debugPrint('[NotificationIndicatorBloc] Initialized: hasNew=$hasNew');
    emit(NotificationIndicatorLoaded(hasNewNotifications: hasNew));

    _subscription?.cancel();
    _subscription = _notificationRepository.hasNewNotificationsStream.listen((hasNew) {
      debugPrint('[NotificationIndicatorBloc] Stream update: hasNew=$hasNew');
      emit(NotificationIndicatorLoaded(hasNewNotifications: hasNew));
    });
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
