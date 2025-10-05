import 'package:flutter/material.dart';
import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../models/user_model.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../services/media_service.dart';

class EditProfileViewModel extends BaseViewModel with CommandMixin {
  final UserRepository _userRepository;

  EditProfileViewModel({
    required UserRepository userRepository,
    required AuthRepository authRepository,
  }) : _userRepository = userRepository;

  UIState<UserModel> _profileState = const UIState.initial();
  UIState<UserModel> get profileState => _profileState;

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  bool _isUploadingPicture = false;
  bool get isUploadingPicture => _isUploadingPicture;

  String _name = '';
  String _about = '';
  String _picture = '';
  String _nip05 = '';
  String _banner = '';
  String _lud16 = '';
  String _website = '';

  String get name => _name;
  String get about => _about;
  String get picture => _picture;
  String get nip05 => _nip05;
  String get banner => _banner;
  String get lud16 => _lud16;
  String get website => _website;

  @override
  void initialize() {
    super.initialize();

    registerCommand('saveProfile', SimpleCommand(_saveProfile));
    registerCommand('uploadPicture', SimpleCommand(_uploadPicture));
  }

  void saveProfileCommand() => executeCommand('saveProfile');
  void uploadPicture() => executeCommand('uploadPicture');

  void updateName(String value) {
    _name = value;
    safeNotifyListeners();
  }

  void updateAbout(String value) {
    _about = value;
    safeNotifyListeners();
  }

  void updatePicture(String value) {
    _picture = value;
    safeNotifyListeners();
  }

  void updateLud16(String value) {
    _lud16 = value;
    safeNotifyListeners();
  }

  void updateNip05(String value) {
    _nip05 = value;
    safeNotifyListeners();
  }

  void updateBanner(String value) {
    _banner = value;
    safeNotifyListeners();
  }

  void updateWebsite(String value) {
    _website = value;
    safeNotifyListeners();
  }

  Future<void> loadCurrentUserProfile() async {
    _profileState = const UIState.loading();
    safeNotifyListeners();

    final result = await _userRepository.getCurrentUser();
    result.fold(
      (user) {
        _name = user.name;
        _about = user.about;
        _picture = user.profileImage;
        _nip05 = user.nip05;
        _banner = user.banner;
        _lud16 = user.lud16;
        _website = user.website;
        _profileState = UIState.loaded(user);
      },
      (error) {
        _profileState = UIState.error(error);
      },
    );
    safeNotifyListeners();
  }

  Future<void> loadProfile(String npub) async {
    _profileState = const UIState.loading();
    safeNotifyListeners();

    final result = await _userRepository.getUserProfile(npub);
    result.fold(
      (user) {
        _name = user.name;
        _about = user.about;
        _picture = user.profileImage;
        _nip05 = user.nip05;
        _banner = user.banner;
        _lud16 = user.lud16;
        _website = user.website;
        _profileState = UIState.loaded(user);
      },
      (error) {
        _profileState = UIState.error(error);
      },
    );
    safeNotifyListeners();
  }

  Future<void> _saveProfile() async {
    if (_isSaving) return;

    _isSaving = true;
    safeNotifyListeners();

    try {
      final result = await _userRepository.updateProfile(
        name: _name.trim(),
        about: _about.trim(),
        profileImage: _picture.trim(),
        nip05: _nip05.trim(),
        banner: _banner.trim(),
        lud16: _lud16.trim(),
        website: _website.trim(),
      );

      result.fold(
        (updatedUser) {
          _profileState = UIState.loaded(updatedUser);
          debugPrint('Profile updated successfully via ViewModel');
        },
        (error) {
          throw Exception(error);
        },
      );
    } catch (e) {
      debugPrint('Error saving profile: $e');
      rethrow;
    } finally {
      _isSaving = false;
      safeNotifyListeners();
    }
  }

  Future<void> _uploadPicture() async {
    if (_isUploadingPicture) return;

    _isUploadingPicture = true;
    _picture = 'Uploading...';
    safeNotifyListeners();

    try {

      debugPrint('Picture upload method ready - UI layer should call with file path');

      _picture = '';
    } catch (e) {
      _picture = ''; // Clear on error
      throw Exception('Upload failed: ${e.toString()}');
    } finally {
      _isUploadingPicture = false;
      safeNotifyListeners();
    }
  }

  Future<void> uploadPictureWithPath(String filePath) async {
    if (_isUploadingPicture) return;

    _isUploadingPicture = true;
    _picture = 'Uploading...';
    safeNotifyListeners();

    try {
      const blossomUrl = 'https://blossom.primal.net'; // Default Blossom server
      final mediaUrl = await MediaService().sendMedia(filePath, blossomUrl);

      _picture = mediaUrl;
      debugPrint('Picture uploaded successfully: $mediaUrl');
    } catch (e) {
      _picture = ''; // Clear on error
      throw Exception('Upload failed: ${e.toString()}');
    } finally {
      _isUploadingPicture = false;
      safeNotifyListeners();
    }
  }

  bool get hasFormData =>
      _name.trim().isNotEmpty ||
      _about.trim().isNotEmpty ||
      _picture.trim().isNotEmpty ||
      _lud16.trim().isNotEmpty ||
      _website.trim().isNotEmpty;
}
