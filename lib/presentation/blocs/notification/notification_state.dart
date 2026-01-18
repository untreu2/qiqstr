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
  final List<dynamic> notifications;
  final int unreadCount;
  final Map<String, Map<String, dynamic>> userProfiles;
  final String currentUserNpub;

  const NotificationsLoaded({
    required this.notifications,
    required this.unreadCount,
    required this.userProfiles,
    required this.currentUserNpub,
  });

  @override
  List<Object?> get props => [notifications, unreadCount, userProfiles, currentUserNpub];

  NotificationsLoaded copyWith({
    List<dynamic>? notifications,
    int? unreadCount,
    Map<String, Map<String, dynamic>>? userProfiles,
    String? currentUserNpub,
  }) {
    return NotificationsLoaded(
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
      userProfiles: userProfiles ?? this.userProfiles,
      currentUserNpub: currentUserNpub ?? this.currentUserNpub,
    );
  }
}

class NotificationError extends NotificationState {
  final String message;

  const NotificationError(this.message);

  @override
  List<Object?> get props => [message];
}
