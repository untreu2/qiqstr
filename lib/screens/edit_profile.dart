import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import 'package:provider/provider.dart';
import '../core/di/app_di.dart';
import '../presentation/viewmodels/edit_profile_viewmodel.dart';
import '../data/repositories/user_repository.dart';
import 'package:file_picker/file_picker.dart';
import '../services/media_service.dart';

class EditOwnProfilePage extends StatelessWidget {
  const EditOwnProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EditProfileViewModel>(
      create: (_) {
        final viewModel = AppDI.get<EditProfileViewModel>();
        viewModel.initialize();
        return viewModel;
      },
      child: const _EditProfileContent(),
    );
  }
}

class _EditProfileContent extends StatefulWidget {
  const _EditProfileContent();

  @override
  State<_EditProfileContent> createState() => _EditProfileContentState();
}

class _EditProfileContentState extends State<_EditProfileContent> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _aboutController = TextEditingController();
  final _pictureController = TextEditingController();
  final _nip05Controller = TextEditingController();
  final _bannerController = TextEditingController();
  final _lud16Controller = TextEditingController();
  final _websiteController = TextEditingController();

  bool _isLoading = true;
  bool _isUploadingBanner = false;

  late final UserRepository _userRepository;

  @override
  void initState() {
    super.initState();
    _userRepository = AppDI.get<UserRepository>();
    _loadUser();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _aboutController.dispose();
    _pictureController.dispose();
    _nip05Controller.dispose();
    _bannerController.dispose();
    _lud16Controller.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    try {
      final currentUserResult = await _userRepository.getCurrentUser();

      if (currentUserResult.isSuccess && currentUserResult.data != null) {
        final user = currentUserResult.data!;

        setState(() {
          _nameController.text = user.name;
          _aboutController.text = user.about;
          _pictureController.text = user.profileImage;
          _nip05Controller.text = user.nip05;
          _bannerController.text = user.banner;
          _lud16Controller.text = user.lud16;
          _websiteController.text = user.website;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (kDebugMode) {
        print('[EditProfile] Error loading user: $e');
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadMedia({
    required TextEditingController controller,
    required String label,
    required bool isPicture,
  }) async {
    final viewModel = context.read<EditProfileViewModel>();

    setState(() {
      if (isPicture) {
        _pictureController.text = 'Uploading...';
      } else {
        _isUploadingBanner = true;
        _bannerController.text = 'Uploading...';
      }
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
            controller.text = mediaUrl;
          });

          // Update the ViewModel with the new URL
          if (isPicture) {
            viewModel.updatePicture(mediaUrl);
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$label uploaded successfully.')),
            );
          }
          if (kDebugMode) {
            print('[EditProfile] Media uploaded successfully: $mediaUrl');
          }
        } catch (uploadError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Upload failed: $uploadError')),
            );
          }
          setState(() {
            controller.text = ''; // Clear on upload failure
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
        if (isPicture) {
          // Picture upload state is handled by viewModel
        } else {
          _isUploadingBanner = false;
        }
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final viewModel = context.read<EditProfileViewModel>();

    // Update viewModel with current form values
    viewModel.updateName(_nameController.text.trim());
    viewModel.updateAbout(_aboutController.text.trim());
    viewModel.updatePicture(_pictureController.text.trim());
    viewModel.updateLud16(_lud16Controller.text.trim());
    viewModel.updateWebsite(_websiteController.text.trim());

    try {
      // Use the enhanced update method that includes all fields
      final result = await _userRepository.updateProfile(
        name: _nameController.text.trim(),
        about: _aboutController.text.trim(),
        profileImage: _pictureController.text.trim(),
        banner: _bannerController.text.trim(),
        website: _websiteController.text.trim(),
        nip05: _nip05Controller.text.trim(),
        lud16: _lud16Controller.text.trim(),
      );

      if (mounted) {
        result.fold(
          (updatedUser) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile updated successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context);
          },
          (error) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to update profile: $error'),
                backgroundColor: Colors.red,
              ),
            );
          },
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('[EditProfile] Error saving profile: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  InputDecoration _inputDecoration(BuildContext context, String label, {VoidCallback? onUpload}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: context.colors.textSecondary,
      ),
      filled: true,
      fillColor: context.colors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.colors.accent, width: 2),
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
    return Consumer<EditProfileViewModel>(
      builder: (context, viewModel, child) {
        if (_isLoading) {
          return Scaffold(
            backgroundColor: context.colors.background,
            body: Center(child: CircularProgressIndicator(color: context.colors.textPrimary)),
          );
        }

        return Scaffold(
          backgroundColor: context.colors.background,
          appBar: AppBar(
            backgroundColor: context.colors.background,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.colors.textPrimary, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            actions: [
              GestureDetector(
                onTap: viewModel.isSaving ? null : _saveProfile,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  height: 34,
                  alignment: Alignment.center,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: context.colors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: viewModel.isSaving
                        ? [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(context.colors.textPrimary),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Updating...',
                              style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ]
                        : [
                            Text(
                              'Save',
                              style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.check, size: 16, color: context.colors.textPrimary),
                          ],
                  ),
                ),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: _inputDecoration(context, 'Username'),
                    style: TextStyle(color: context.colors.textPrimary),
                    maxLength: 50,
                    onChanged: (value) => viewModel.updateName(value),
                    validator: (value) {
                      if (value != null && value.trim().length > 50) {
                        return 'Username must be 50 characters or less';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _aboutController,
                    decoration: _inputDecoration(context, 'Bio'),
                    style: TextStyle(color: context.colors.textPrimary),
                    maxLines: 3,
                    maxLength: 300,
                    onChanged: (value) => viewModel.updateAbout(value),
                    validator: (value) {
                      if (value != null && value.trim().length > 300) {
                        return 'Bio must be 300 characters or less';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _pictureController,
                    enabled: !viewModel.isUploadingPicture,
                    decoration: _inputDecoration(
                      context,
                      'Profile image URL',
                      onUpload: viewModel.isUploadingPicture
                          ? null
                          : () => _pickAndUploadMedia(
                                controller: _pictureController,
                                label: 'Profile image',
                                isPicture: true,
                              ),
                    ),
                    style: TextStyle(color: context.colors.textPrimary),
                    onChanged: (value) => viewModel.updatePicture(value),
                    validator: (value) {
                      if (value != null && value.trim().isNotEmpty) {
                        final uri = Uri.tryParse(value.trim());
                        if (uri == null || !uri.hasScheme) {
                          return 'Please enter a valid URL';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _bannerController,
                    enabled: !_isUploadingBanner,
                    decoration: _inputDecoration(
                      context,
                      'Banner URL',
                      onUpload: _isUploadingBanner
                          ? null
                          : () => _pickAndUploadMedia(
                                controller: _bannerController,
                                label: 'Banner',
                                isPicture: false,
                              ),
                    ),
                    style: TextStyle(color: context.colors.textPrimary),
                    validator: (value) {
                      if (value != null && value.trim().isNotEmpty) {
                        final uri = Uri.tryParse(value.trim());
                        if (uri == null || !uri.hasScheme) {
                          return 'Please enter a valid URL';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _lud16Controller,
                    decoration: _inputDecoration(context, 'Lightning address'),
                    style: TextStyle(color: context.colors.textPrimary),
                    onChanged: (value) => viewModel.updateLud16(value),
                    validator: (value) {
                      if (value != null && value.trim().isNotEmpty) {
                        final lud16 = value.trim();
                        if (!lud16.contains('@') || lud16.split('@').length != 2) {
                          return 'Please enter a valid lightning address (e.g., user@domain.com)';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _websiteController,
                    decoration: _inputDecoration(context, 'Website'),
                    style: TextStyle(color: context.colors.textPrimary),
                    onChanged: (value) => viewModel.updateWebsite(value),
                    validator: (value) {
                      if (value != null && value.trim().isNotEmpty) {
                        final website = value.trim();
                        if (!website.contains('.') || website.contains(' ')) {
                          return 'Please enter a valid website URL';
                        }
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
