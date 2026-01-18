import '../../../core/bloc/base/base_state.dart';

abstract class NotificationIndicatorState extends BaseState {
  const NotificationIndicatorState();
}

class NotificationIndicatorInitial extends NotificationIndicatorState {
  const NotificationIndicatorInitial();
}

class NotificationIndicatorLoaded extends NotificationIndicatorState {
  final bool hasNewNotifications;

  const NotificationIndicatorLoaded({required this.hasNewNotifications});

  @override
  List<Object?> get props => [hasNewNotifications];
}
