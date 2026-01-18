import '../../../core/bloc/base/base_event.dart';

abstract class NotificationEvent extends BaseEvent {
  const NotificationEvent();
}

class NotificationsLoadRequested extends NotificationEvent {
  const NotificationsLoadRequested();
}

class NotificationsLoaded extends NotificationEvent {
  const NotificationsLoaded();
}

class NotificationsRefreshRequested extends NotificationEvent {
  const NotificationsRefreshRequested();
}

class NotificationsRefreshed extends NotificationEvent {
  const NotificationsRefreshed();
}

class NotificationsMarkAllAsReadRequested extends NotificationEvent {
  const NotificationsMarkAllAsReadRequested();
}

class NotificationRead extends NotificationEvent {
  final String notificationId;

  const NotificationRead(this.notificationId);

  @override
  List<Object?> get props => [notificationId];
}

class AllNotificationsRead extends NotificationEvent {
  const AllNotificationsRead();
}
