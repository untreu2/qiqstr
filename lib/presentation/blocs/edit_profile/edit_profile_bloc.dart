import 'package:bloc/bloc.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/data_service.dart';
import 'edit_profile_event.dart';
import 'edit_profile_state.dart';

class EditProfileBloc extends Bloc<EditProfileEvent, EditProfileState> {
  final UserRepository _userRepository;
  final DataService _dataService;

  EditProfileBloc({
    required UserRepository userRepository,
    required AuthRepository authRepository,
    required DataService dataService,
  })  : _userRepository = userRepository,
        _dataService = dataService,
        super(const EditProfileInitial()) {
    on<EditProfileInitialized>(_onEditProfileInitialized);
    on<EditProfileLoadRequested>(_onEditProfileLoadRequested);
    on<EditProfileNameChanged>(_onEditProfileNameChanged);
    on<EditProfileAboutChanged>(_onEditProfileAboutChanged);
    on<EditProfilePictureChanged>(_onEditProfilePictureChanged);
    on<EditProfileNip05Changed>(_onEditProfileNip05Changed);
    on<EditProfileBannerChanged>(_onEditProfileBannerChanged);
    on<EditProfileLud16Changed>(_onEditProfileLud16Changed);
    on<EditProfileWebsiteChanged>(_onEditProfileWebsiteChanged);
    on<EditProfileSaved>(_onEditProfileSaved);
    on<EditProfilePictureUploaded>(_onEditProfilePictureUploaded);
    on<EditProfileBannerUploaded>(_onEditProfileBannerUploaded);
  }

  Future<void> _onEditProfileInitialized(
    EditProfileInitialized event,
    Emitter<EditProfileState> emit,
  ) async {
    emit(const EditProfileLoading());

    final result = await _userRepository.getCurrentUser();
    result.fold(
      (user) {
        final nameValue = user['name'];
        final name = nameValue is String ? nameValue : (nameValue?.toString() ?? '');

        final aboutValue = user['about'];
        final about = aboutValue is String ? aboutValue : (aboutValue?.toString() ?? '');

        final pictureValue = user['profileImage'];
        final picture = pictureValue is String ? pictureValue : (pictureValue?.toString() ?? '');

        final nip05Value = user['nip05'];
        final nip05 = nip05Value is String ? nip05Value : (nip05Value?.toString() ?? '');

        final bannerValue = user['banner'];
        final banner = bannerValue is String ? bannerValue : (bannerValue?.toString() ?? '');

        final lud16Value = user['lud16'];
        final lud16 = lud16Value is String ? lud16Value : (lud16Value?.toString() ?? '');

        final websiteValue = user['website'];
        final website = websiteValue is String ? websiteValue : (websiteValue?.toString() ?? '');

        emit(EditProfileLoaded(
          user: user,
          name: name,
          about: about,
          picture: picture,
          nip05: nip05,
          banner: banner,
          lud16: lud16,
          website: website,
        ));
      },
      (error) => emit(EditProfileError(error.toString())),
    );
  }

  Future<void> _onEditProfileLoadRequested(
    EditProfileLoadRequested event,
    Emitter<EditProfileState> emit,
  ) async {
    emit(const EditProfileLoading());

    final result = event.npub != null ? await _userRepository.getUserProfile(event.npub!) : await _userRepository.getCurrentUser();

    result.fold(
      (user) {
        final nameValue = user['name'];
        final name = nameValue is String ? nameValue : (nameValue?.toString() ?? '');

        final aboutValue = user['about'];
        final about = aboutValue is String ? aboutValue : (aboutValue?.toString() ?? '');

        final pictureValue = user['profileImage'];
        final picture = pictureValue is String ? pictureValue : (pictureValue?.toString() ?? '');

        final nip05Value = user['nip05'];
        final nip05 = nip05Value is String ? nip05Value : (nip05Value?.toString() ?? '');

        final bannerValue = user['banner'];
        final banner = bannerValue is String ? bannerValue : (bannerValue?.toString() ?? '');

        final lud16Value = user['lud16'];
        final lud16 = lud16Value is String ? lud16Value : (lud16Value?.toString() ?? '');

        final websiteValue = user['website'];
        final website = websiteValue is String ? websiteValue : (websiteValue?.toString() ?? '');

        emit(EditProfileLoaded(
          user: user,
          name: name,
          about: about,
          picture: picture,
          nip05: nip05,
          banner: banner,
          lud16: lud16,
          website: website,
        ));
      },
      (error) => emit(EditProfileError(error.toString())),
    );
  }

  void _onEditProfileNameChanged(
    EditProfileNameChanged event,
    Emitter<EditProfileState> emit,
  ) {
    final currentState = state;
    if (currentState is EditProfileLoaded) {
      emit(currentState.copyWith(name: event.name));
    }
  }

  void _onEditProfileAboutChanged(
    EditProfileAboutChanged event,
    Emitter<EditProfileState> emit,
  ) {
    final currentState = state;
    if (currentState is EditProfileLoaded) {
      emit(currentState.copyWith(about: event.about));
    }
  }

  void _onEditProfilePictureChanged(
    EditProfilePictureChanged event,
    Emitter<EditProfileState> emit,
  ) {
    final currentState = state;
    if (currentState is EditProfileLoaded) {
      emit(currentState.copyWith(picture: event.picture));
    }
  }

  void _onEditProfileNip05Changed(
    EditProfileNip05Changed event,
    Emitter<EditProfileState> emit,
  ) {
    final currentState = state;
    if (currentState is EditProfileLoaded) {
      emit(currentState.copyWith(nip05: event.nip05));
    }
  }

  void _onEditProfileBannerChanged(
    EditProfileBannerChanged event,
    Emitter<EditProfileState> emit,
  ) {
    final currentState = state;
    if (currentState is EditProfileLoaded) {
      emit(currentState.copyWith(banner: event.banner));
    }
  }

  void _onEditProfileLud16Changed(
    EditProfileLud16Changed event,
    Emitter<EditProfileState> emit,
  ) {
    final currentState = state;
    if (currentState is EditProfileLoaded) {
      emit(currentState.copyWith(lud16: event.lud16));
    }
  }

  void _onEditProfileWebsiteChanged(
    EditProfileWebsiteChanged event,
    Emitter<EditProfileState> emit,
  ) {
    final currentState = state;
    if (currentState is EditProfileLoaded) {
      emit(currentState.copyWith(website: event.website));
    }
  }

  Future<void> _onEditProfileSaved(
    EditProfileSaved event,
    Emitter<EditProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! EditProfileLoaded || currentState.isSaving) return;

    emit(currentState.copyWith(isSaving: true));

    try {
      final result = await _userRepository.updateProfile(
        name: currentState.name.trim(),
        about: currentState.about.trim(),
        profileImage: currentState.picture.trim(),
        nip05: currentState.nip05.trim(),
        banner: currentState.banner.trim(),
        lud16: currentState.lud16.trim(),
        website: currentState.website.trim(),
      );

      result.fold(
        (updatedUser) {
          emit(EditProfileSaveSuccess(user: updatedUser));
        },
        (error) => emit(EditProfileError(error)),
      );
    } catch (e) {
      emit(EditProfileError('Failed to save profile: ${e.toString()}'));
    }
  }

  Future<void> _onEditProfilePictureUploaded(
    EditProfilePictureUploaded event,
    Emitter<EditProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! EditProfileLoaded || currentState.isUploadingPicture) return;

    emit(currentState.copyWith(isUploadingPicture: true, picture: 'Uploading...'));

    try {
      const blossomUrl = 'https://blossom.primal.net';
      final mediaResult = await _dataService.sendMedia(event.filePath, blossomUrl);

      if (mediaResult.isSuccess && mediaResult.data != null) {
        emit(currentState.copyWith(
          picture: mediaResult.data!,
          isUploadingPicture: false,
        ));
      } else {
        emit(currentState.copyWith(
          picture: '',
          isUploadingPicture: false,
        ));
        emit(EditProfileError('Failed to upload picture'));
      }
    } catch (e) {
      emit(currentState.copyWith(
        picture: '',
        isUploadingPicture: false,
      ));
      emit(EditProfileError('Failed to upload picture: ${e.toString()}'));
    }
  }

  Future<void> _onEditProfileBannerUploaded(
    EditProfileBannerUploaded event,
    Emitter<EditProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! EditProfileLoaded) return;

    try {
      const blossomUrl = 'https://blossom.primal.net';
      final mediaResult = await _dataService.sendMedia(event.filePath, blossomUrl);

      if (mediaResult.isSuccess && mediaResult.data != null) {
        emit(currentState.copyWith(banner: mediaResult.data!));
      } else {
        emit(EditProfileError('Failed to upload banner'));
      }
    } catch (e) {
      emit(EditProfileError('Failed to upload banner: ${e.toString()}'));
    }
  }
}
