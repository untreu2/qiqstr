import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../theme/theme_manager.dart';
import 'package:provider/provider.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/blocs/edit_profile/edit_profile_bloc.dart';
import '../../../presentation/blocs/edit_profile/edit_profile_event.dart';
import '../../../presentation/blocs/edit_profile/edit_profile_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/custom_input_field.dart';

class EditOwnProfilePage extends StatelessWidget {
  const EditOwnProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<EditProfileBloc>(
      create: (context) {
        final bloc = AppDI.get<EditProfileBloc>();
        bloc.add(const EditProfileInitialized());
        return bloc;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _setupControllerListeners();
      }
    });
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


  Future<void> _pickAndUploadMedia({
    required TextEditingController controller,
    required String label,
    required bool isPicture,
  }) async {
    final bloc = context.read<EditProfileBloc>();

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
        final filePath = result.files.single.path!;

        if (isPicture) {
          bloc.add(EditProfilePictureUploaded(filePath));
        } else {
          bloc.add(EditProfileBannerUploaded(filePath));
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Upload failed: $e');
      }
    } finally {
      setState(() {
        if (!isPicture) {
          _isUploadingBanner = false;
        }
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final bloc = context.read<EditProfileBloc>();

    bloc.add(EditProfileNameChanged(_nameController.text.trim()));
    bloc.add(EditProfileAboutChanged(_aboutController.text.trim()));
    bloc.add(EditProfilePictureChanged(_pictureController.text.trim()));
    bloc.add(EditProfileNip05Changed(_nip05Controller.text.trim()));
    bloc.add(EditProfileBannerChanged(_bannerController.text.trim()));
    bloc.add(EditProfileLud16Changed(_lud16Controller.text.trim()));
    bloc.add(EditProfileWebsiteChanged(_websiteController.text.trim()));

    bloc.add(const EditProfileSaved());
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

  Widget _buildProfilePicturePreview(BuildContext context, EditProfileLoaded state) {
    final pictureUrl = _pictureController.text.trim();
    final avatarRadius = 40.0;
    final isUploading = state.isUploadingPicture;

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
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EditProfileBloc, EditProfileState>(
      builder: (context, state) {
        if (state is EditProfileLoading) {
          return Scaffold(
            backgroundColor: context.colors.background,
            body: Center(child: CircularProgressIndicator(color: context.colors.textPrimary)),
          );
        }

        if (state is EditProfileSaveSuccess) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.pop();
            }
          });
        }

        if (state is EditProfileError) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              AppSnackbar.error(context, state.message);
            }
          });
        }

        final loadedState = state is EditProfileLoaded ? state : null;
        if (loadedState == null && state is! EditProfileInitial) {
          return Scaffold(
            backgroundColor: context.colors.background,
            body: Center(child: CircularProgressIndicator(color: context.colors.textPrimary)),
          );
        }

        if (loadedState != null && !_hasLoadedUser) {
          _nameController.text = loadedState.name;
          _aboutController.text = loadedState.about;
          _pictureController.text = loadedState.picture;
          _nip05Controller.text = loadedState.nip05;
          _bannerController.text = loadedState.banner;
          _lud16Controller.text = loadedState.lud16;
          _websiteController.text = loadedState.website;
          _hasLoadedUser = true;
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
                          child: loadedState != null
                              ? _buildProfilePicturePreview(context, loadedState)
                              : const SizedBox(),
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
                              onChanged: (value) {
                                context.read<EditProfileBloc>().add(EditProfileNameChanged(value));
                              },
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
                              onChanged: (value) {
                                context.read<EditProfileBloc>().add(EditProfileAboutChanged(value));
                              },
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
                              onChanged: (value) {
                                context.read<EditProfileBloc>().add(EditProfileLud16Changed(value));
                              },
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
                              onChanged: (value) {
                                context.read<EditProfileBloc>().add(EditProfileWebsiteChanged(value));
                              },
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
                  onTap: loadedState?.isSaving == true ? null : _saveProfile,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: context.colors.textPrimary,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: loadedState?.isSaving == true
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
