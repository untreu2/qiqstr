import '../../../core/bloc/base/base_event.dart';

abstract class MutedEvent extends BaseEvent {
  const MutedEvent();
}

class MutedLoadRequested extends MutedEvent {
  const MutedLoadRequested();
}

class MutedUserUnmuted extends MutedEvent {
  final String userNpub;

  const MutedUserUnmuted(this.userNpub);

  @override
  List<Object?> get props => [userNpub];
}

class MutedRefreshed extends MutedEvent {
  const MutedRefreshed();
}
