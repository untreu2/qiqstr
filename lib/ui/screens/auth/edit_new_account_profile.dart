import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../data/sync/sync_service.dart';
import '../../../presentation/blocs/edit_new_account_profile/edit_new_account_profile_bloc.dart';
import '../../../presentation/blocs/edit_new_account_profile/edit_new_account_profile_event.dart';
import '../../../presentation/blocs/edit_new_account_profile/edit_new_account_profile_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/custom_input_field.dart';

class EditNewAccountProfilePage extends StatefulWidget {
  final String npub;

  const EditNewAccountProfilePage({
    super.key,
    required this.npub,
  });

  @override
  State<EditNewAccountProfilePage> createState() =>
      _EditNewAccountProfilePageState();
}

class _EditNewAccountProfilePageState extends State<EditNewAccountProfilePage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _aboutController = TextEditingController();
  final _pictureController = TextEditingController();
  final _bannerController = TextEditingController();
  final _lud16Controller = TextEditingController();
  final _websiteController = TextEditingController();

  bool _isUploadingBanner = false;

  @override
  void initState() {
    super.initState();
    _pictureController.addListener(_onControllerChanged);
    _bannerController.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _pictureController.removeListener(_onControllerChanged);
    _bannerController.removeListener(_onControllerChanged);
    _nameController.dispose();
    _aboutController.dispose();
    _pictureController.dispose();
    _bannerController.dispose();
    _lud16Controller.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadMedia({
    required BuildContext context,
    required bool isPicture,
  }) async {
    final bloc = context.read<EditNewAccountProfileBloc>();

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
          bloc.add(EditNewAccountProfilePictureUploaded(filePath));
        } else {
          bloc.add(EditNewAccountProfileBannerUploaded(filePath));
        }
      }
    } catch (e) {
      if (context.mounted) {
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

  Future<void> _saveAndContinue(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    context.read<EditNewAccountProfileBloc>().add(EditNewAccountProfileSaved(
          name: _nameController.text.trim(),
          about: _aboutController.text.trim(),
          profileImage: _pictureController.text.trim(),
          banner: _bannerController.text.trim(),
          lud16: _lud16Controller.text.trim(),
          website: _websiteController.text.trim(),
        ));
  }

  Widget _buildHeader(BuildContext context) {
    return TitleWidget(
      title: 'Set Up Profile',
      fontSize: 32,
      subtitle: 'Add some basic information to help others discover you.',
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
                context: context,
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
                color: Colors.black.withValues(alpha: 0.3),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.colors.background.withValues(alpha: 0.9),
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

  Widget _buildProfilePicturePreview(
      BuildContext context, EditNewAccountProfileLoaded state) {
    final pictureUrl = _pictureController.text.trim();
    final avatarRadius = 40.0;
    final isUploading = state.isUploadingPicture;

    return Row(
      children: [
        GestureDetector(
          onTap: isUploading
              ? null
              : () => _pickAndUploadMedia(
                    context: context,
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
                        color: Colors.black.withValues(alpha: 0.3),
                      ),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: context.colors.background.withValues(alpha: 0.9),
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
    return BlocProvider<EditNewAccountProfileBloc>(
      create: (context) => EditNewAccountProfileBloc(
        syncService: AppDI.get<SyncService>(),
        npub: widget.npub,
      ),
      child:
          BlocListener<EditNewAccountProfileBloc, EditNewAccountProfileState>(
        listener: (context, state) {
          if (state is EditNewAccountProfileLoaded) {
            if (state.uploadedPictureUrl != null) {
              _pictureController.text = state.uploadedPictureUrl!;
              AppSnackbar.success(
                  context, 'Profile image uploaded successfully.');
            }
            if (state.uploadedBannerUrl != null) {
              _bannerController.text = state.uploadedBannerUrl!;
              AppSnackbar.success(context, 'Banner uploaded successfully.');
            }
          }
          if (state is EditNewAccountProfileError) {
            AppSnackbar.error(context, state.message);
          }
          if (state is EditNewAccountProfileSaveSuccess) {
            final router = GoRouter.of(context);
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                router.go(
                    '/suggested-follows?npub=${Uri.encodeComponent(widget.npub)}');
              }
            });
          }
        },
        child:
            BlocBuilder<EditNewAccountProfileBloc, EditNewAccountProfileState>(
          builder: (context, state) {
            final loadedState = state is EditNewAccountProfileLoaded
                ? state
                : const EditNewAccountProfileLoaded();

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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: _buildProfilePicturePreview(
                                  context, loadedState),
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
                                  validator: (value) {
                                    if (value != null &&
                                        value.trim().length > 50) {
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
                                  validator: (value) {
                                    if (value != null &&
                                        value.trim().length > 300) {
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
                                  validator: (value) {
                                    if (value != null &&
                                        value.trim().isNotEmpty) {
                                      final lud16 = value.trim();
                                      if (!lud16.contains('@') ||
                                          lud16.split('@').length != 2) {
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
                                  validator: (value) {
                                    if (value != null &&
                                        value.trim().isNotEmpty) {
                                      final website = value.trim();
                                      if (!website.contains('.') ||
                                          website.contains(' ')) {
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
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 16,
                    right: 16,
                    child: GestureDetector(
                      onTap: loadedState.isSaving
                          ? null
                          : () => _saveAndContinue(context),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: context.colors.textPrimary,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: loadedState.isSaving
                            ? Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        context.colors.background),
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
        ),
      ),
    );
  }
}
