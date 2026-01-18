import '../../../core/bloc/base/base_event.dart';

abstract class ProfileEvent extends BaseEvent {
  const ProfileEvent();
}

class ProfileLoadRequested extends ProfileEvent {
  final String pubkeyHex;

  const ProfileLoadRequested(this.pubkeyHex);

  @override
  List<Object?> get props => [pubkeyHex];
}

class ProfileRefreshed extends ProfileEvent {
  const ProfileRefreshed();
}

class ProfileFollowToggled extends ProfileEvent {
  const ProfileFollowToggled();
}

class ProfileEditRequested extends ProfileEvent {
  const ProfileEditRequested();
}

class ProfileFollowingListRequested extends ProfileEvent {
  const ProfileFollowingListRequested();
}

class ProfileFollowersListRequested extends ProfileEvent {
  const ProfileFollowersListRequested();
}

class ProfileNotesLoaded extends ProfileEvent {
  final String pubkeyHex;

  const ProfileNotesLoaded(this.pubkeyHex);

  @override
  List<Object?> get props => [pubkeyHex];
}

class ProfileLoadMoreNotesRequested extends ProfileEvent {
  const ProfileLoadMoreNotesRequested();
}

class ProfileUserUpdated extends ProfileEvent {
  final Map<String, dynamic> user;

  const ProfileUserUpdated(this.user);

  @override
  List<Object?> get props => [user];
}
