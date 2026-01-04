import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../theme/theme_manager.dart';
import 'package:provider/provider.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/viewmodels/edit_profile_viewmodel.dart';
import 'package:file_picker/file_picker.dart';
import '../../../data/services/media_service.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../widgets/common/back_button_widget.dart';
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

  bool _isUploadingBanner = false;
  bool _hasLoadedUser = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasLoadedUser) {
      _hasLoadedUser = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final viewModel = Provider.of<EditProfileViewModel>(context, listen: false);
          _loadUser(viewModel);
          _setupControllerListeners();
        }
      });
    }
  }

  void _setupControllerListeners() {
    _pictureController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    _bannerController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _pictureController.removeListener(() {});
    _bannerController.removeListener(() {});
    _nameController.dispose();
    _aboutController.dispose();
    _pictureController.dispose();
    _nip05Controller.dispose();
    _bannerController.dispose();
    _lud16Controller.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _loadUser(EditProfileViewModel viewModel) async {
    await viewModel.loadCurrentUserProfile();
    if (!mounted) return;
    
    final profileState = viewModel.profileState;
    
    if (profileState.isLoaded && profileState.data != null) {
      final user = profileState.data!;
      if (mounted) {
        setState(() {
          _nameController.text = user.name;
          _aboutController.text = user.about;
          _pictureController.text = user.profileImage;
          _nip05Controller.text = user.nip05;
          _bannerController.text = user.banner;
          _lud16Controller.text = user.lud16;
          _websiteController.text = user.website;
        });
      }
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
    viewModel.updateNip05(_nip05Controller.text.trim());
    viewModel.updateBanner(_bannerController.text.trim());
    viewModel.updateLud16(_lud16Controller.text.trim());
    viewModel.updateWebsite(_websiteController.text.trim());

    try {
      await viewModel.saveProfileCommand();
      if (mounted) {
        context.pop();
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


  Widget _buildHeader(BuildContext context) {
    return TitleWidget(
      title: 'Edit Profile',
      fontSize: 32,
      useTopPadding: true,
    );
  }

  Widget _buildBannerPreview(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bannerHeight = screenWidth * (3.5 / 10);
    final bannerUrl = _bannerController.text.trim();

    return GestureDetector(
      onTap: _isUploadingBanner
          ? null
          : () => _pickAndUploadMedia(
                controller: _bannerController,
                label: 'Banner',
                isPicture: false,
              ),
      child: Stack(
        children: [
          Container(
            width: screenWidth,
            height: bannerHeight,
            color: context.colors.background,
            child: _isUploadingBanner
                ? Container(
                    height: bannerHeight,
                    width: screenWidth,
                    color: context.colors.grey700,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: context.colors.textPrimary,
                      ),
                    ),
                  )
                : bannerUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: bannerUrl,
                        width: screenWidth,
                        height: bannerHeight,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          height: bannerHeight,
                          width: screenWidth,
                          color: context.colors.grey700,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          height: bannerHeight,
                          width: screenWidth,
                          color: context.colors.background,
                          child: Icon(
                            Icons.image,
                            color: context.colors.textSecondary,
                            size: 40,
                          ),
                        ),
                      )
                    : Container(
                        height: bannerHeight,
                        width: screenWidth,
                        color: context.colors.background,
                        child: Icon(
                          Icons.add_photo_alternate,
                          color: context.colors.textSecondary,
                          size: 40,
                        ),
                      ),
          ),
          if (!_isUploadingBanner)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.colors.background.withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CarbonIcons.camera,
                      color: context.colors.textPrimary,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProfilePicturePreview(BuildContext context) {
    return Consumer<EditProfileViewModel>(
      builder: (context, viewModel, child) {
        final pictureUrl = _pictureController.text.trim();
        final avatarRadius = 40.0;
        final isUploading = viewModel.isUploadingPicture;

        return Row(
          children: [
            GestureDetector(
              onTap: isUploading
                  ? null
                  : () => _pickAndUploadMedia(
                        controller: _pictureController,
                        label: 'Profile image',
                        isPicture: true,
                      ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.colors.background,
                    width: 3,
                  ),
                ),
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: avatarRadius,
                      backgroundColor: context.colors.surfaceTransparent,
                      backgroundImage: pictureUrl.isNotEmpty && !isUploading
                          ? CachedNetworkImageProvider(pictureUrl)
                          : null,
                      child: isUploading
                          ? CircularProgressIndicator(
                              color: context.colors.textPrimary,
                              strokeWidth: 2,
                            )
                          : pictureUrl.isEmpty
                              ? Icon(
                                  Icons.person,
                                  size: avatarRadius,
                                  color: context.colors.textSecondary,
                                )
                              : null,
                    ),
                    if (!isUploading)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.3),
                          ),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: context.colors.background.withOpacity(0.9),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                CarbonIcons.camera,
                                color: context.colors.textPrimary,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EditProfileViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.profileState.isLoading) {
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBannerPreview(context),
                        Container(
                          transform: Matrix4.translationValues(0, -16, 0),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildProfilePicturePreview(context),
                        ),
                      ],
                    ),
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
