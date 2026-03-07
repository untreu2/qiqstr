import '../../../core/bloc/base/base_event.dart';

abstract class DmIndicatorEvent extends BaseEvent {
  const DmIndicatorEvent();
}

class DmIndicatorInitialized extends DmIndicatorEvent {
  const DmIndicatorInitialized();
}

class DmIndicatorChecked extends DmIndicatorEvent {
  const DmIndicatorChecked();
}
