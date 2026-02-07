import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/sync/sync_service.dart';
import 'edit_new_account_profile_event.dart';
import 'edit_new_account_profile_state.dart';

class EditNewAccountProfileBloc
    extends Bloc<EditNewAccountProfileEvent, EditNewAccountProfileState> {
  final SyncService _syncService;
  final String npub;

  EditNewAccountProfileBloc({
    required SyncService syncService,
    required this.npub,
  })  : _syncService = syncService,
        super(const EditNewAccountProfileInitial()) {
    on<EditNewAccountProfilePictureUploaded>(
        _onEditNewAccountProfilePictureUploaded);
    on<EditNewAccountProfileBannerUploaded>(
        _onEditNewAccountProfileBannerUploaded);
    on<EditNewAccountProfileSaved>(_onEditNewAccountProfileSaved);
  }

  Future<void> _onEditNewAccountProfilePictureUploaded(
    EditNewAccountProfilePictureUploaded event,
    Emitter<EditNewAccountProfileState> emit,
  ) async {
    final currentState = state is EditNewAccountProfileLoaded
        ? (state as EditNewAccountProfileLoaded)
        : const EditNewAccountProfileLoaded();

    if (currentState.isUploadingPicture) return;

    emit(currentState.copyWith(
        isUploadingPicture: true, uploadedPictureUrl: null));

    final url = await _syncService.uploadMedia(event.filePath);

    if (url != null) {
      emit(currentState.copyWith(
        uploadedPictureUrl: url,
        isUploadingPicture: false,
      ));
    } else {
      emit(currentState.copyWith(isUploadingPicture: false));
      emit(const EditNewAccountProfileError('Failed to upload picture'));
    }
  }

  Future<void> _onEditNewAccountProfileBannerUploaded(
    EditNewAccountProfileBannerUploaded event,
    Emitter<EditNewAccountProfileState> emit,
  ) async {
    final currentState = state is EditNewAccountProfileLoaded
        ? (state as EditNewAccountProfileLoaded)
        : const EditNewAccountProfileLoaded();

    if (currentState.isUploadingBanner) return;

    emit(currentState.copyWith(
        isUploadingBanner: true, uploadedBannerUrl: null));

    final url = await _syncService.uploadMedia(event.filePath);

    if (url != null) {
      emit(currentState.copyWith(
        uploadedBannerUrl: url,
        isUploadingBanner: false,
      ));
    } else {
      emit(currentState.copyWith(isUploadingBanner: false));
      emit(const EditNewAccountProfileError('Failed to upload banner'));
    }
  }

  Future<void> _onEditNewAccountProfileSaved(
    EditNewAccountProfileSaved event,
    Emitter<EditNewAccountProfileState> emit,
  ) async {
    final currentState = state is EditNewAccountProfileLoaded
        ? (state as EditNewAccountProfileLoaded)
        : const EditNewAccountProfileLoaded();

    if (currentState.isSaving) return;

    emit(currentState.copyWith(isSaving: true));

    try {
      final profile = {
        'name': event.name.trim().isNotEmpty ? event.name.trim() : 'New User',
        'about': event.about.trim(),
        'picture': event.profileImage.trim(),
        'banner': event.banner.trim(),
        'lud16': event.lud16.trim(),
        'website': event.website.trim(),
      };

      await _syncService.publishProfileUpdate(profileContent: profile);
      emit(const EditNewAccountProfileSaveSuccess());
    } catch (e) {
      emit(EditNewAccountProfileError(
          'Failed to save profile: ${e.toString()}'));
    }
  }
}
