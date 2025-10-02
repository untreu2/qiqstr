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
        // Use legacy Blossom upload pattern exactly
        const blossomUrl = 'https://blossom.primal.net'; // Default Blossom server
        final filePath = result.files.single.path!;

        try {
          final mediaUrl = await MediaService().sendMedia(filePath, blossomUrl);
          setState(() {
            _pictureController.text = mediaUrl;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile image uploaded successfully.')),
            );
          }
          if (kDebugMode) {
            print('[EditNewAccountProfile] Media uploaded successfully: $mediaUrl');
          }
        } catch (uploadError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Upload failed: $uploadError')),
            );
          }
          setState(() {
            _pictureController.text = ''; // Clear on upload failure
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
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
      // Always create and send profile update to establish user presence on relays
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

      // Send profile update to relays
      final result = await _userRepository.updateUserProfile(updatedUser);

      result.fold(
        (success) {
          debugPrint('[EditNewAccountProfile] Profile updated successfully');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile updated successfully!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        (error) {
          debugPrint('[EditNewAccountProfile] Profile update failed: $error');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Profile update failed: $error'),
                backgroundColor: Colors.red,
              ),
            );
          }
          // Don't return - still continue to next page even if profile update fails
        },
      );

      // Small delay to let the profile update propagate
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        // Still continue to next page even on error
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

  Future<void> _skipToSuggestions() async {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SuggestedFollowsPage(
          npub: widget.npub,
        ),
      ),
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
          ? IconButton(
              icon: Icon(Icons.upload, color: context.colors.accent),
              onPressed: onUpload,
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
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Text(
                            'Set up your profile',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: context.colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add some basic information to help others discover you.',
                            style: TextStyle(
                              fontSize: 16,
                              color: context.colors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 40),
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
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                  decoration: BoxDecoration(
                    color: context.colors.background,
                    border: Border(
                      top: BorderSide(color: context.colors.border),
                    ),
                  ),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _isSaving ? null : _skipToSuggestions,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: context.colors.overlayLight,
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(color: context.colors.borderAccent),
                          ),
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: _isSaving ? null : _saveAndContinue,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: context.colors.buttonPrimary,
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(color: context.colors.borderAccent),
                          ),
                          child: _isSaving
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(context.colors.background),
                                  ),
                                )
                              : Text(
                                  'Continue',
                                  style: TextStyle(
                                    color: context.colors.background,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
