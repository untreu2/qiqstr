import 'package:bloc/bloc.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/data_service.dart';
import 'edit_new_account_profile_event.dart';
import 'edit_new_account_profile_state.dart';

class EditNewAccountProfileBloc
    extends Bloc<EditNewAccountProfileEvent, EditNewAccountProfileState> {
  final UserRepository _userRepository;
  final DataService _dataService;
  final String npub;

  EditNewAccountProfileBloc({
    required UserRepository userRepository,
    required DataService dataService,
    required this.npub,
  })  : _userRepository = userRepository,
        _dataService = dataService,
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

    try {
      const blossomUrl = 'https://blossom.primal.net';
      final mediaResult =
          await _dataService.sendMedia(event.filePath, blossomUrl);

      if (mediaResult.isSuccess && mediaResult.data != null) {
        emit(currentState.copyWith(
          uploadedPictureUrl: mediaResult.data!,
          isUploadingPicture: false,
        ));
      } else {
        emit(currentState.copyWith(isUploadingPicture: false));
        emit(EditNewAccountProfileError('Failed to upload picture'));
      }
    } catch (e) {
      emit(currentState.copyWith(isUploadingPicture: false));
      emit(EditNewAccountProfileError(
          'Failed to upload picture: ${e.toString()}'));
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

    try {
      const blossomUrl = 'https://blossom.primal.net';
      final mediaResult =
          await _dataService.sendMedia(event.filePath, blossomUrl);

      if (mediaResult.isSuccess && mediaResult.data != null) {
        emit(currentState.copyWith(
          uploadedBannerUrl: mediaResult.data!,
          isUploadingBanner: false,
        ));
      } else {
        emit(currentState.copyWith(isUploadingBanner: false));
        emit(EditNewAccountProfileError('Failed to upload banner'));
      }
    } catch (e) {
      emit(currentState.copyWith(isUploadingBanner: false));
      emit(EditNewAccountProfileError(
          'Failed to upload banner: ${e.toString()}'));
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
      final updatedUser = <String, dynamic>{
        'pubkeyHex': npub,
        'name': event.name.trim().isNotEmpty ? event.name.trim() : 'New User',
        'about': event.about.trim(),
        'profileImage': event.profileImage.trim(),
        'nip05': '',
        'banner': event.banner.trim(),
        'lud16': event.lud16.trim(),
        'website': event.website.trim(),
        'updatedAt': DateTime.now(),
        'nip05Verified': false,
        'followerCount': 0,
      };

      final result = await _userRepository.updateUserProfile(updatedUser);

      result.fold(
        (_) {
          emit(const EditNewAccountProfileSaveSuccess());
        },
        (error) {
          emit(EditNewAccountProfileError(error));
        },
      );
    } catch (e) {
      emit(EditNewAccountProfileError(
          'Failed to save profile: ${e.toString()}'));
    }
  }
}
