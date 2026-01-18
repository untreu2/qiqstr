import '../../../core/bloc/base/base_event.dart';

abstract class ProfileInfoEvent extends BaseEvent {
  const ProfileInfoEvent();
}

class ProfileInfoInitialized extends ProfileInfoEvent {
  final String userPubkeyHex;

  const ProfileInfoInitialized({required this.userPubkeyHex});

  @override
  List<Object?> get props => [userPubkeyHex];
}

class ProfileInfoUserUpdated extends ProfileInfoEvent {
  final Map<String, dynamic> user;

  const ProfileInfoUserUpdated({required this.user});

  @override
  List<Object?> get props => [user];
}

class ProfileInfoFollowToggled extends ProfileInfoEvent {
  const ProfileInfoFollowToggled();
}

class ProfileInfoMuteToggled extends ProfileInfoEvent {
  const ProfileInfoMuteToggled();
}
