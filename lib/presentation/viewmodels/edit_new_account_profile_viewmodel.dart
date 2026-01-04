import '../../core/base/base_view_model.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/media_service.dart';
import '../../models/user_model.dart';

class EditNewAccountProfileViewModel extends BaseViewModel {
  final UserRepository _userRepository;
  final String npub;

  EditNewAccountProfileViewModel({
    required UserRepository userRepository,
    required this.npub,
  }) : _userRepository = userRepository;

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  bool _isUploadingPicture = false;
  bool get isUploadingPicture => _isUploadingPicture;

  String? _uploadedPictureUrl;
  String? get uploadedPictureUrl => _uploadedPictureUrl;

  Future<void> uploadPicture(String filePath) async {
    if (_isUploadingPicture) return;

    _isUploadingPicture = true;
    _uploadedPictureUrl = null;
    safeNotifyListeners();

    try {
      const blossomUrl = 'https://blossom.primal.net';
      final mediaUrl = await MediaService().sendMedia(filePath, blossomUrl);
      
      if (!isDisposed) {
        _uploadedPictureUrl = mediaUrl;
        _isUploadingPicture = false;
        safeNotifyListeners();
      }
    } catch (e) {
      if (!isDisposed) {
        _uploadedPictureUrl = null;
        _isUploadingPicture = false;
        safeNotifyListeners();
      }
      rethrow;
    }
  }

  Future<void> saveProfile({
    required String name,
    required String about,
    required String profileImage,
    required String lud16,
    required String website,
  }) async {
    if (_isSaving) return;

    _isSaving = true;
    safeNotifyListeners();

    try {
      final updatedUser = UserModel.create(
        pubkeyHex: npub,
        name: name.trim().isNotEmpty ? name.trim() : 'New User',
        about: about.trim(),
        profileImage: profileImage.trim(),
        nip05: '',
        banner: '',
        lud16: lud16.trim(),
        website: website.trim(),
        updatedAt: DateTime.now(),
      );

      final result = await _userRepository.updateUserProfile(updatedUser);

      if (!isDisposed) {
        result.fold(
          (success) {
            // Profile updated successfully
          },
          (error) {
            throw Exception(error);
          },
        );
      }
    } catch (e) {
      if (!isDisposed) {
        safeNotifyListeners();
      }
      rethrow;
    } finally {
      if (!isDisposed) {
        _isSaving = false;
        safeNotifyListeners();
      }
    }
  }
}
