import '../../../core/bloc/base/base_state.dart';

abstract class EditNewAccountProfileState extends BaseState {
  const EditNewAccountProfileState();
}

class EditNewAccountProfileInitial extends EditNewAccountProfileState {
  const EditNewAccountProfileInitial();
}

class EditNewAccountProfileLoaded extends EditNewAccountProfileState {
  final String? uploadedPictureUrl;
  final String? uploadedBannerUrl;
  final bool isUploadingPicture;
  final bool isUploadingBanner;
  final bool isSaving;

  const EditNewAccountProfileLoaded({
    this.uploadedPictureUrl,
    this.uploadedBannerUrl,
    this.isUploadingPicture = false,
    this.isUploadingBanner = false,
    this.isSaving = false,
  });

  EditNewAccountProfileLoaded copyWith({
    String? uploadedPictureUrl,
    String? uploadedBannerUrl,
    bool? isUploadingPicture,
    bool? isUploadingBanner,
    bool? isSaving,
  }) {
    return EditNewAccountProfileLoaded(
      uploadedPictureUrl: uploadedPictureUrl ?? this.uploadedPictureUrl,
      uploadedBannerUrl: uploadedBannerUrl ?? this.uploadedBannerUrl,
      isUploadingPicture: isUploadingPicture ?? this.isUploadingPicture,
      isUploadingBanner: isUploadingBanner ?? this.isUploadingBanner,
      isSaving: isSaving ?? this.isSaving,
    );
  }

  @override
  List<Object?> get props => [
        uploadedPictureUrl,
        uploadedBannerUrl,
        isUploadingPicture,
        isUploadingBanner,
        isSaving
      ];
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
