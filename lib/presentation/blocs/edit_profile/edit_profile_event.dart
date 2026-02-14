import '../../../core/bloc/base/base_event.dart';

abstract class EditProfileEvent extends BaseEvent {
  const EditProfileEvent();
}

class EditProfileInitialized extends EditProfileEvent {
  const EditProfileInitialized();
}

class EditProfileLoadRequested extends EditProfileEvent {
  final String? npub;

  const EditProfileLoadRequested({this.npub});

  @override
  List<Object?> get props => [npub];
}

class EditProfileNameChanged extends EditProfileEvent {
  final String name;

  const EditProfileNameChanged(this.name);

  @override
  List<Object?> get props => [name];
}

class EditProfileAboutChanged extends EditProfileEvent {
  final String about;

  const EditProfileAboutChanged(this.about);

  @override
  List<Object?> get props => [about];
}

class EditProfilePictureChanged extends EditProfileEvent {
  final String picture;

  const EditProfilePictureChanged(this.picture);

  @override
  List<Object?> get props => [picture];
}

class EditProfileNip05Changed extends EditProfileEvent {
  final String nip05;

  const EditProfileNip05Changed(this.nip05);

  @override
  List<Object?> get props => [nip05];
}

class EditProfileBannerChanged extends EditProfileEvent {
  final String banner;

  const EditProfileBannerChanged(this.banner);

  @override
  List<Object?> get props => [banner];
}

class EditProfileLud16Changed extends EditProfileEvent {
  final String lud16;

  const EditProfileLud16Changed(this.lud16);

  @override
  List<Object?> get props => [lud16];
}

class EditProfileWebsiteChanged extends EditProfileEvent {
  final String website;

  const EditProfileWebsiteChanged(this.website);

  @override
  List<Object?> get props => [website];
}

class EditProfileLocationChanged extends EditProfileEvent {
  final String location;

  const EditProfileLocationChanged(this.location);

  @override
  List<Object?> get props => [location];
}

class EditProfileSaved extends EditProfileEvent {
  const EditProfileSaved();
}

class EditProfilePictureUploaded extends EditProfileEvent {
  final String filePath;

  const EditProfilePictureUploaded(this.filePath);

  @override
  List<Object?> get props => [filePath];
}

class EditProfileBannerUploaded extends EditProfileEvent {
  final String filePath;

  const EditProfileBannerUploaded(this.filePath);

  @override
  List<Object?> get props => [filePath];
}
