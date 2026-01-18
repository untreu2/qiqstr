import '../../../core/bloc/base/base_state.dart';

abstract class EditProfileState extends BaseState {
  const EditProfileState();
}

class EditProfileInitial extends EditProfileState {
  const EditProfileInitial();
}

class EditProfileLoading extends EditProfileState {
  const EditProfileLoading();
}

class EditProfileLoaded extends EditProfileState {
  final Map<String, dynamic> user;
  final String name;
  final String about;
  final String picture;
  final String nip05;
  final String banner;
  final String lud16;
  final String website;
  final bool isSaving;
  final bool isUploadingPicture;

  const EditProfileLoaded({
    required this.user,
    required this.name,
    required this.about,
    required this.picture,
    required this.nip05,
    required this.banner,
    required this.lud16,
    required this.website,
    this.isSaving = false,
    this.isUploadingPicture = false,
  });

  EditProfileLoaded copyWith({
    Map<String, dynamic>? user,
    String? name,
    String? about,
    String? picture,
    String? nip05,
    String? banner,
    String? lud16,
    String? website,
    bool? isSaving,
    bool? isUploadingPicture,
  }) {
    return EditProfileLoaded(
      user: user ?? this.user,
      name: name ?? this.name,
      about: about ?? this.about,
      picture: picture ?? this.picture,
      nip05: nip05 ?? this.nip05,
      banner: banner ?? this.banner,
      lud16: lud16 ?? this.lud16,
      website: website ?? this.website,
      isSaving: isSaving ?? this.isSaving,
      isUploadingPicture: isUploadingPicture ?? this.isUploadingPicture,
    );
  }

  @override
  List<Object?> get props => [
        user,
        name,
        about,
        picture,
        nip05,
        banner,
        lud16,
        website,
        isSaving,
        isUploadingPicture,
      ];
}

class EditProfileError extends EditProfileState {
  final String message;

  const EditProfileError(this.message);

  @override
  List<Object?> get props => [message];
}

class EditProfileSaveSuccess extends EditProfileState {
  final Map<String, dynamic> user;

  const EditProfileSaveSuccess({required this.user});

  @override
  List<Object?> get props => [user];
}
