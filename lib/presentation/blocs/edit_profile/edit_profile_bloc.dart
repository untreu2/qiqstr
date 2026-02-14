import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import 'edit_profile_event.dart';
import 'edit_profile_state.dart';

class EditProfileBloc extends Bloc<EditProfileEvent, EditProfileState> {
  final ProfileRepository _profileRepository;
  final SyncService _syncService;
  final AuthService _authService;

  EditProfileBloc({
    required ProfileRepository profileRepository,
    required SyncService syncService,
    required AuthService authService,
  })  : _profileRepository = profileRepository,
        _syncService = syncService,
        _authService = authService,
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
    on<EditProfileLocationChanged>(_onEditProfileLocationChanged);
    on<EditProfileSaved>(_onEditProfileSaved);
    on<EditProfilePictureUploaded>(_onEditProfilePictureUploaded);
    on<EditProfileBannerUploaded>(_onEditProfileBannerUploaded);
  }

  Future<void> _onEditProfileInitialized(
    EditProfileInitialized event,
    Emitter<EditProfileState> emit,
  ) async {
    emit(const EditProfileLoading());

    try {
      final currentUserHex = _authService.currentUserPubkeyHex;
      if (currentUserHex == null) {
        emit(const EditProfileError('User not found'));
        return;
      }

      final profile = await _profileRepository.getProfile(currentUserHex);
      if (profile == null) {
        emit(const EditProfileError('User not found'));
        return;
      }

      _emitLoadedState(emit, profile.toMap());
    } catch (e) {
      emit(EditProfileError(e.toString()));
    }
  }

  Future<void> _onEditProfileLoadRequested(
    EditProfileLoadRequested event,
    Emitter<EditProfileState> emit,
  ) async {
    emit(const EditProfileLoading());

    try {
      String? targetHex;
      if (event.npub != null) {
        targetHex = _authService.npubToHex(event.npub!);
      } else {
        targetHex = _authService.currentUserPubkeyHex;
      }

      if (targetHex == null) {
        emit(const EditProfileError('User not found'));
        return;
      }

      await _syncService.syncProfile(targetHex);
      final profile = await _profileRepository.getProfile(targetHex);

      if (profile == null) {
        emit(const EditProfileError('User not found'));
        return;
      }

      _emitLoadedState(emit, profile.toMap());
    } catch (e) {
      emit(EditProfileError(e.toString()));
    }
  }

  void _emitLoadedState(
      Emitter<EditProfileState> emit, Map<String, dynamic> user) {
    final nameValue = user['name'];
    final name =
        nameValue is String ? nameValue : (nameValue?.toString() ?? '');

    final aboutValue = user['about'];
    final about =
        aboutValue is String ? aboutValue : (aboutValue?.toString() ?? '');

    final pictureValue = user['profileImage'] ?? user['picture'];
    final picture = pictureValue is String
        ? pictureValue
        : (pictureValue?.toString() ?? '');

    final nip05Value = user['nip05'];
    final nip05 =
        nip05Value is String ? nip05Value : (nip05Value?.toString() ?? '');

    final bannerValue = user['banner'];
    final banner =
        bannerValue is String ? bannerValue : (bannerValue?.toString() ?? '');

    final lud16Value = user['lud16'];
    final lud16 =
        lud16Value is String ? lud16Value : (lud16Value?.toString() ?? '');

    final websiteValue = user['website'];
    final website = websiteValue is String
        ? websiteValue
        : (websiteValue?.toString() ?? '');

    final locationValue = user['location'];
    final location = locationValue is String
        ? locationValue
        : (locationValue?.toString() ?? '');

    emit(EditProfileLoaded(
      user: user,
      name: name,
      about: about,
      picture: picture,
      nip05: nip05,
      banner: banner,
      lud16: lud16,
      website: website,
      location: location,
    ));
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

  void _onEditProfileLocationChanged(
    EditProfileLocationChanged event,
    Emitter<EditProfileState> emit,
  ) {
    final currentState = state;
    if (currentState is EditProfileLoaded) {
      emit(currentState.copyWith(location: event.location));
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
      final profile = {
        'name': currentState.name.trim(),
        'about': currentState.about.trim(),
        'picture': currentState.picture.trim(),
        'nip05': currentState.nip05.trim(),
        'banner': currentState.banner.trim(),
        'lud16': currentState.lud16.trim(),
        'website': currentState.website.trim(),
        'location': currentState.location.trim(),
      };

      await _syncService.publishProfileUpdate(profileContent: profile);

      final currentUserHex = _authService.currentUserPubkeyHex;
      if (currentUserHex != null) {
        final profileData = Map<String, String>.from(
          profile.map((k, v) => MapEntry(k, v.toString())),
        );
        await _profileRepository.saveProfile(currentUserHex, profileData);
      }

      emit(EditProfileSaveSuccess(user: profile));
    } catch (e) {
      emit(EditProfileError('Failed to save profile: ${e.toString()}'));
    }
  }

  Future<void> _onEditProfilePictureUploaded(
    EditProfilePictureUploaded event,
    Emitter<EditProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! EditProfileLoaded || currentState.isUploadingPicture) {
      return;
    }

    emit(currentState.copyWith(
        isUploadingPicture: true, picture: 'Uploading...'));

    final url = await _syncService.uploadMedia(event.filePath);

    if (url != null) {
      emit(currentState.copyWith(
        picture: url,
        isUploadingPicture: false,
      ));
    } else {
      emit(currentState.copyWith(
        picture: '',
        isUploadingPicture: false,
      ));
      emit(const EditProfileError('Failed to upload picture'));
    }
  }

  Future<void> _onEditProfileBannerUploaded(
    EditProfileBannerUploaded event,
    Emitter<EditProfileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! EditProfileLoaded) return;

    final url = await _syncService.uploadMedia(event.filePath);

    if (url != null) {
      emit(currentState.copyWith(banner: url));
    } else {
      emit(const EditProfileError('Failed to upload banner'));
    }
  }
}
