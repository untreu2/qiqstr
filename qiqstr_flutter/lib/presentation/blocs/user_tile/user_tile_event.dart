import '../../../core/bloc/base/base_event.dart';

abstract class UserTileEvent extends BaseEvent {
  const UserTileEvent();
}

class UserTileInitialized extends UserTileEvent {
  final String userNpub;

  const UserTileInitialized({required this.userNpub});

  @override
  List<Object?> get props => [userNpub];
}

class UserTileFollowToggled extends UserTileEvent {
  const UserTileFollowToggled();
}
