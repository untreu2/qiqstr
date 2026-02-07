import '../../../core/bloc/base/base_state.dart';

abstract class NotificationState extends BaseState {
  const NotificationState();
}

class NotificationInitial extends NotificationState {
  const NotificationInitial();
}

class NotificationLoading extends NotificationState {
  const NotificationLoading();
}

class NotificationsLoaded extends NotificationState {
  final List<Map<String, dynamic>> notifications;
  final int unreadCount;
  final String currentUserHex;

  const NotificationsLoaded({
    required this.notifications,
    required this.unreadCount,
    required this.currentUserHex,
  });

  @override
  List<Object?> get props => [notifications, unreadCount, currentUserHex];

  NotificationsLoaded copyWith({
    List<Map<String, dynamic>>? notifications,
    int? unreadCount,
    String? currentUserHex,
  }) {
    return NotificationsLoaded(
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
      currentUserHex: currentUserHex ?? this.currentUserHex,
    );
  }
}

class NotificationError extends NotificationState {
  final String message;

  const NotificationError(this.message);

  @override
  List<Object?> get props => [message];
}
