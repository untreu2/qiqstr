import '../../../core/bloc/base/base_event.dart';

abstract class NotificationIndicatorEvent extends BaseEvent {
  const NotificationIndicatorEvent();
}

class NotificationIndicatorInitialized extends NotificationIndicatorEvent {
  const NotificationIndicatorInitialized();
}

class NotificationIndicatorNewReceived extends NotificationIndicatorEvent {
  const NotificationIndicatorNewReceived();
}

class NotificationIndicatorChecked extends NotificationIndicatorEvent {
  const NotificationIndicatorChecked();
}
