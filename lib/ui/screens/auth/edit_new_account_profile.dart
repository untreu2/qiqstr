import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/blocs/edit_new_account_profile/edit_new_account_profile_bloc.dart';
import '../../../presentation/blocs/edit_new_account_profile/edit_new_account_profile_event.dart';
import '../../../presentation/blocs/edit_new_account_profile/edit_new_account_profile_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/common/custom_input_field.dart';

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

  @override
  void dispose() {
    _nameController.dispose();
    _aboutController.dispose();
    _pictureController.dispose();
    _lud16Controller.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadMedia(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        context.read<EditNewAccountProfileBloc>().add(EditNewAccountProfilePictureUploaded(filePath));
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Upload failed: $e');
      }
    }
  }

  Future<void> _saveAndContinue(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    context.read<EditNewAccountProfileBloc>().add(EditNewAccountProfileSaved(
          name: _nameController.text.trim(),
          about: _aboutController.text.trim(),
          profileImage: _pictureController.text.trim(),
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
    return BlocProvider<EditNewAccountProfileBloc>(
      create: (context) => EditNewAccountProfileBloc(
        userRepository: AppDI.get(),
        dataService: AppDI.get(),
        npub: widget.npub,
      ),
      child: BlocListener<EditNewAccountProfileBloc, EditNewAccountProfileState>(
        listener: (context, state) {
          if (state is EditNewAccountProfileLoaded && state.uploadedPictureUrl != null) {
            _pictureController.text = state.uploadedPictureUrl!;
            AppSnackbar.success(context, 'Profile image uploaded successfully.');
          }
          if (state is EditNewAccountProfileError) {
            AppSnackbar.error(context, state.message);
          }
          if (state is EditNewAccountProfileSaveSuccess) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                context.go('/suggested-follows?npub=${Uri.encodeComponent(widget.npub)}');
              }
            });
          }
        },
        child: BlocBuilder<EditNewAccountProfileBloc, EditNewAccountProfileState>(
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
                                  enabled: !loadedState.isUploadingPicture,
                                  labelText: 'Profile image URL',
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
                                    'Profile image URL',
                                    onUpload: loadedState.isUploadingPicture ? null : () => _pickAndUploadMedia(context),
                                  ).suffixIcon,
                                ),
                                const SizedBox(height: 20),
                                CustomInputField(
                                  controller: _lud16Controller,
                                  labelText: 'Lightning address (optional)',
                                  fillColor: context.colors.inputFill,
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
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 16,
                    right: 16,
                    child: GestureDetector(
                      onTap: loadedState.isSaving ? null : () => _saveAndContinue(context),
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
        ),
      ),
    );
  }
}
