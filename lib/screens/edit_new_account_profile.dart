import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../theme/theme_manager.dart';
import '../models/user_model.dart';
import '../screens/suggested_follows_page.dart';
import '../core/di/app_di.dart';
import '../data/repositories/user_repository.dart';
import '../services/media_service.dart';
import '../widgets/snackbar_widget.dart';
import '../widgets/back_button_widget.dart';
import '../widgets/common_buttons.dart';
import '../widgets/title_widget.dart';

class EditNewAccountProfilePage extends StatefulWidget {
  final String npub;

  const EditNewAccountProfilePage({
    super.key,
    required this.npub,
  });

  @override
  State<EditNewAccountProfilePage> createState() => _EditNewAccountProfilePageState();
}

class _EditNewAccountProfilePageState extends State<EditNewAccountProfilePage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _aboutController = TextEditingController();
  final _pictureController = TextEditingController();
  final _lud16Controller = TextEditingController();
  final _websiteController = TextEditingController();

  bool _isSaving = false;
  bool _isUploadingPicture = false;

  late final UserRepository _userRepository;
  @override
  void initState() {
    super.initState();
    _userRepository = AppDI.get<UserRepository>();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _aboutController.dispose();
    _pictureController.dispose();
    _lud16Controller.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadMedia() async {
    setState(() {
      _isUploadingPicture = true;
      _pictureController.text = 'Uploading...';
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (result != null && result.files.single.path != null) {
        const blossomUrl = 'https://blossom.primal.net'; // Default Blossom server
        final filePath = result.files.single.path!;

        try {
          final mediaUrl = await MediaService().sendMedia(filePath, blossomUrl);
          setState(() {
            _pictureController.text = mediaUrl;
          });

          if (mounted) {
            AppSnackbar.success(context, 'Profile image uploaded successfully.');
          }
          if (kDebugMode) {
            print('[EditNewAccountProfile] Media uploaded successfully: $mediaUrl');
          }
        } catch (uploadError) {
          if (mounted) {
            AppSnackbar.error(context, 'Upload failed: $uploadError');
          }
          setState(() {
            _pictureController.text = ''; // Clear on upload failure
          });
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Upload failed: $e');
      }
    } finally {
      setState(() {
        _isUploadingPicture = false;
      });
    }
  }

  Future<void> _saveAndContinue() async {
    setState(() => _isSaving = true);

    try {
      final updatedUser = UserModel(
        pubkeyHex: widget.npub,
        name: _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : 'New User',
        about: _aboutController.text.trim(),
        profileImage: _pictureController.text.trim(),
        nip05: '',
        banner: '',
        lud16: _lud16Controller.text.trim(),
        website: _websiteController.text.trim(),
        updatedAt: DateTime.now(),
      );

      debugPrint('[EditNewAccountProfile] Updating profile: ${updatedUser.name}');
      debugPrint(
          '[EditNewAccountProfile] Profile data: name=${updatedUser.name}, about=${updatedUser.about}, image=${updatedUser.profileImage}');

      final result = await _userRepository.updateUserProfile(updatedUser);

      result.fold(
        (success) {
          debugPrint('[EditNewAccountProfile] Profile updated successfully');
        },
        (error) {
          debugPrint('[EditNewAccountProfile] Profile update failed: $error');
          if (mounted) {
            AppSnackbar.error(context, 'Profile update failed: $error');
          }
        },
      );

      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SuggestedFollowsPage(
              npub: widget.npub,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[EditNewAccountProfile] Error saving profile: $e');
      if (mounted) {
        AppSnackbar.error(context, 'Failed to update profile: ${e.toString()}');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SuggestedFollowsPage(
              npub: widget.npub,
            ),
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Widget _buildHeader(BuildContext context) {
    return TitleWidget(
      title: 'Set Up Profile',
      fontSize: 32,
      subtitle: 'Add some basic information to help others discover you.',
      useTopPadding: true,
    );
  }

  InputDecoration _inputDecoration(BuildContext context, String label, {VoidCallback? onUpload}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: context.colors.textSecondary,
      ),
      filled: true,
      fillColor: context.colors.inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(25),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      suffixIcon: onUpload != null
          ? IconActionButton(
              icon: Icons.upload,
              iconColor: context.colors.accent,
              onPressed: onUpload,
              size: ButtonSize.small,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _nameController,
                              decoration: _inputDecoration(context, 'Username'),
                              style: TextStyle(color: context.colors.textPrimary),
                              maxLength: 50,
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _aboutController,
                              decoration: _inputDecoration(context, 'Bio'),
                              style: TextStyle(color: context.colors.textPrimary),
                              maxLines: 3,
                              maxLength: 300,
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _pictureController,
                              enabled: !_isUploadingPicture,
                              decoration: _inputDecoration(
                                context,
                                'Profile image URL',
                                onUpload: _isUploadingPicture ? null : _pickAndUploadMedia,
                              ),
                              style: TextStyle(color: context.colors.textPrimary),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _lud16Controller,
                              decoration: _inputDecoration(context, 'Lightning address (optional)'),
                              style: TextStyle(color: context.colors.textPrimary),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _websiteController,
                              decoration: _inputDecoration(context, 'Website (optional)'),
                              style: TextStyle(color: context.colors.textPrimary),
                            ),
                            const SizedBox(height: 60),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const BackButtonWidget.floating(),
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 16,
                child: GestureDetector(
                  onTap: _isSaving ? null : _saveAndContinue,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: context.colors.buttonPrimary,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: _isSaving
                        ? Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(context.colors.buttonText),
                              ),
                            ),
                          )
                        : Icon(
                            Icons.check,
                            color: context.colors.buttonText,
                            size: 24,
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
