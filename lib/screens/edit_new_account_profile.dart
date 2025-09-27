import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import 'package:provider/provider.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/providers/user_provider.dart';
import 'package:qiqstr/screens/suggested_follows_page.dart';

import '../services/in_memory_data_manager.dart';
import 'package:file_picker/file_picker.dart';

class EditNewAccountProfilePage extends StatefulWidget {
  final String npub;
  final DataService dataService;

  const EditNewAccountProfilePage({
    super.key,
    required this.npub,
    required this.dataService,
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
        final filePath = result.files.single.path!;
        final url = await widget.dataService.sendMedia(filePath, 'https://blossom.primal.net');
        setState(() {
          _pictureController.text = url;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile image uploaded successfully.')),
          );
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
      if (_nameController.text.trim().isNotEmpty ||
          _aboutController.text.trim().isNotEmpty ||
          _pictureController.text.trim().isNotEmpty ||
          _lud16Controller.text.trim().isNotEmpty ||
          _websiteController.text.trim().isNotEmpty) {
        await widget.dataService.sendProfileEdit(
          name: _nameController.text.trim(),
          about: _aboutController.text.trim(),
          picture: _pictureController.text.trim(),
          nip05: '',
          banner: '',
          lud16: _lud16Controller.text.trim(),
          website: _websiteController.text.trim(),
        );

        await Future.delayed(const Duration(milliseconds: 500));

        final usersBox = InMemoryDataManager.instance.usersBox;
        final newUser = UserModel(
          npub: widget.npub,
          name: _nameController.text.trim(),
          about: _aboutController.text.trim(),
          profileImage: _pictureController.text.trim(),
          nip05: '',
          banner: '',
          lud16: _lud16Controller.text.trim(),
          website: _websiteController.text.trim(),
          updatedAt: DateTime.now(),
        );

        await usersBox?.put(widget.npub, newUser);

        widget.dataService.profilesNotifier.value = {
          ...widget.dataService.profilesNotifier.value,
          newUser.npub: newUser,
        };
        UserProvider.instance.updateUser(widget.npub, newUser);
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SuggestedFollowsPage(
              npub: widget.npub,
              dataService: widget.dataService,
            ),
          ),
        );
      }
    } catch (e) {
      print('[EditNewAccountProfile] Error saving profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: ${e.toString()}'),
            backgroundColor: Colors.red,
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
          dataService: widget.dataService,
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
