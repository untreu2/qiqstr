import '../../../core/bloc/base/base_state.dart';

abstract class EditNewAccountProfileState extends BaseState {
  const EditNewAccountProfileState();
}

class EditNewAccountProfileInitial extends EditNewAccountProfileState {
  const EditNewAccountProfileInitial();
}

class EditNewAccountProfileLoaded extends EditNewAccountProfileState {
  final String? uploadedPictureUrl;
  final bool isUploadingPicture;
  final bool isSaving;

  const EditNewAccountProfileLoaded({
    this.uploadedPictureUrl,
    this.isUploadingPicture = false,
    this.isSaving = false,
  });

  EditNewAccountProfileLoaded copyWith({
    String? uploadedPictureUrl,
    bool? isUploadingPicture,
    bool? isSaving,
  }) {
    return EditNewAccountProfileLoaded(
      uploadedPictureUrl: uploadedPictureUrl ?? this.uploadedPictureUrl,
      isUploadingPicture: isUploadingPicture ?? this.isUploadingPicture,
      isSaving: isSaving ?? this.isSaving,
    );
  }

  @override
  List<Object?> get props => [uploadedPictureUrl, isUploadingPicture, isSaving];
}

class EditNewAccountProfileError extends EditNewAccountProfileState {
  final String message;

  const EditNewAccountProfileError(this.message);

  @override
  List<Object?> get props => [message];
}

class EditNewAccountProfileSaveSuccess extends EditNewAccountProfileState {
  const EditNewAccountProfileSaveSuccess();
}
