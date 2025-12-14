import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';
import 'package:provider/provider.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/viewmodels/edit_profile_viewmodel.dart';
import '../../../data/repositories/user_repository.dart';
import 'package:file_picker/file_picker.dart';
import '../../../data/services/media_service.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/custom_input_field.dart';

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
        const blossomUrl = 'https://blossom.primal.net'; // Default Blossom server
        final filePath = result.files.single.path!;

        try {
          final mediaUrl = await MediaService().sendMedia(filePath, blossomUrl);
          setState(() {
            controller.text = mediaUrl;
          });

          if (isPicture) {
            viewModel.updatePicture(mediaUrl);
          }

          if (mounted) {
            AppSnackbar.success(context, '$label uploaded successfully.');
          }
          if (kDebugMode) {
            print('[EditProfile] Media uploaded successfully: $mediaUrl');
          }
        } catch (uploadError) {
          if (mounted) {
            AppSnackbar.error(context, 'Upload failed: $uploadError');
          }
          setState(() {
            controller.text = ''; // Clear on upload failure
          });
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Upload failed: $e');
      }
    } finally {
      setState(() {
        if (isPicture) {
        } else {
          _isUploadingBanner = false;
        }
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final viewModel = context.read<EditProfileViewModel>();

    viewModel.updateName(_nameController.text.trim());
    viewModel.updateAbout(_aboutController.text.trim());
    viewModel.updatePicture(_pictureController.text.trim());
    viewModel.updateLud16(_lud16Controller.text.trim());
    viewModel.updateWebsite(_websiteController.text.trim());

    try {
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
            Navigator.pop(context);
          },
          (error) {
            AppSnackbar.error(context, 'Failed to update profile: $error');
          },
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('[EditProfile] Error saving profile: $e');
      }
      if (mounted) {
        AppSnackbar.error(context, 'Failed to update profile: ${e.toString()}');
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
      fillColor: context.colors.inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(25),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      isDense: true,
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

  Widget _buildHeader(BuildContext context) {
    return TitleWidget(
      title: 'Edit Profile',
      fontSize: 32,
      useTopPadding: true,
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
                            CustomInputField(
                              controller: _nameController,
                              labelText: 'Username',
                              fillColor: context.colors.inputFill,
                              onChanged: (value) => viewModel.updateName(value),
                              validator: (value) {
                                if (value != null && value.trim().length > 50) {
                                  return 'Username must be 50 characters or less';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            CustomInputField(
                              controller: _aboutController,
                              labelText: 'Bio',
                              fillColor: context.colors.inputFill,
                              maxLines: 3,
                              height: null,
                              onChanged: (value) => viewModel.updateAbout(value),
                              validator: (value) {
                                if (value != null && value.trim().length > 300) {
                                  return 'Bio must be 300 characters or less';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            CustomInputField(
                              controller: _pictureController,
                              enabled: !viewModel.isUploadingPicture,
                              labelText: 'Profile image URL',
                              fillColor: context.colors.inputFill,
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
                              suffixIcon: _inputDecoration(
                                context,
                                'Profile image URL',
                                onUpload: viewModel.isUploadingPicture
                                    ? null
                                    : () => _pickAndUploadMedia(
                                          controller: _pictureController,
                                          label: 'Profile image',
                                          isPicture: true,
                                        ),
                              ).suffixIcon,
                            ),
                            const SizedBox(height: 20),
                            CustomInputField(
                              controller: _bannerController,
                              enabled: !_isUploadingBanner,
                              labelText: 'Banner URL',
                              fillColor: context.colors.inputFill,
                              validator: (value) {
                                if (value != null && value.trim().isNotEmpty) {
                                  final uri = Uri.tryParse(value.trim());
                                  if (uri == null || !uri.hasScheme) {
                                    return 'Please enter a valid URL';
                                  }
                                }
                                return null;
                              },
                              suffixIcon: _inputDecoration(
                                context,
                                'Banner URL',
                                onUpload: _isUploadingBanner
                                    ? null
                                    : () => _pickAndUploadMedia(
                                          controller: _bannerController,
                                          label: 'Banner',
                                          isPicture: false,
                                        ),
                              ).suffixIcon,
                            ),
                            const SizedBox(height: 20),
                            CustomInputField(
                              controller: _lud16Controller,
                              labelText: 'Lightning address (optional)',
                              fillColor: context.colors.inputFill,
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
                            const SizedBox(height: 20),
                            CustomInputField(
                              controller: _websiteController,
                              labelText: 'Website (optional)',
                              fillColor: context.colors.inputFill,
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
                  onTap: viewModel.isSaving ? null : _saveProfile,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: context.colors.textPrimary,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: viewModel.isSaving
                        ? Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(context.colors.background),
                              ),
                            ),
                          )
                        : Icon(
                            Icons.check,
                            color: context.colors.background,
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
