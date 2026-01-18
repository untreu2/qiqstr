import '../../../core/bloc/base/base_event.dart';

abstract class EditNewAccountProfileEvent extends BaseEvent {
  const EditNewAccountProfileEvent();
}

class EditNewAccountProfilePictureUploaded extends EditNewAccountProfileEvent {
  final String filePath;

  const EditNewAccountProfilePictureUploaded(this.filePath);

  @override
  List<Object?> get props => [filePath];
}

class EditNewAccountProfileSaved extends EditNewAccountProfileEvent {
  final String name;
  final String about;
  final String profileImage;
  final String lud16;
  final String website;

  const EditNewAccountProfileSaved({
    required this.name,
    required this.about,
    required this.profileImage,
    required this.lud16,
    required this.website,
  });

  @override
  List<Object?> get props => [name, about, profileImage, lud16, website];
}
