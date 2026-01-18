import '../../../core/bloc/base/base_event.dart';

abstract class SidebarEvent extends BaseEvent {
  const SidebarEvent();
}

class SidebarInitialized extends SidebarEvent {
  const SidebarInitialized();
}

class SidebarRefreshed extends SidebarEvent {
  const SidebarRefreshed();
}
