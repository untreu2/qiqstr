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

class ProfileUserNotePublished extends ProfileEvent {
  final Map<String, dynamic> note;

  const ProfileUserNotePublished(this.note);

  @override
  List<Object?> get props => [note];
}

class ProfileProfilesLoaded extends ProfileEvent {
  final Map<String, Map<String, dynamic>> profiles;

  const ProfileProfilesLoaded(this.profiles);

  @override
  List<Object?> get props => [profiles];
}

class ProfileSyncCompleted extends ProfileEvent {
  const ProfileSyncCompleted();
}

class ProfileRepliesLoaded extends ProfileEvent {
  final String pubkeyHex;

  const ProfileRepliesLoaded(this.pubkeyHex);

  @override
  List<Object?> get props => [pubkeyHex];
}

class ProfileLoadMoreRepliesRequested extends ProfileEvent {
  const ProfileLoadMoreRepliesRequested();
}

class ProfileArticlesRequested extends ProfileEvent {
  final String pubkeyHex;

  const ProfileArticlesRequested(this.pubkeyHex);

  @override
  List<Object?> get props => [pubkeyHex];
}

class ProfileLikesRequested extends ProfileEvent {
  final String pubkeyHex;

  const ProfileLikesRequested(this.pubkeyHex);

  @override
  List<Object?> get props => [pubkeyHex];
}

class ProfileLoadMoreLikesRequested extends ProfileEvent {
  const ProfileLoadMoreLikesRequested();
}

class ProfileLoadMoreArticlesRequested extends ProfileEvent {
  const ProfileLoadMoreArticlesRequested();
}
