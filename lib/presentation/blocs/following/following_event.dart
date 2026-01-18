import '../../../core/bloc/base/base_event.dart';

abstract class FollowingEvent extends BaseEvent {
  const FollowingEvent();
}

class FollowingLoadRequested extends FollowingEvent {
  final String userNpub;

  const FollowingLoadRequested({required this.userNpub});

  @override
  List<Object?> get props => [userNpub];
}
