import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:hive/hive.dart';
import 'package:file_picker/file_picker.dart';

class EditOwnProfilePage extends StatefulWidget {
  const EditOwnProfilePage({super.key});

  @override
  State<EditOwnProfilePage> createState() => _EditOwnProfilePageState();
}

class _EditOwnProfilePageState extends State<EditOwnProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _secureStorage = const FlutterSecureStorage();

  final _nameController = TextEditingController();
  final _aboutController = TextEditingController();
  final _pictureController = TextEditingController();
  final _nip05Controller = TextEditingController();
  final _bannerController = TextEditingController();
  final _lud16Controller = TextEditingController();
  final _websiteController = TextEditingController();

  DataService? _dataService;

  bool _isSaving = false;
  bool _isLoading = true;
  bool _isUploadingPicture = false;
  bool _isUploadingBanner = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _dataService?.closeConnections();
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
    final npub = await _secureStorage.read(key: 'npub');
    if (npub == null) return;

    final usersBox = await Hive.openBox<UserModel>('users');
    final user = usersBox.get(npub);

    final dataService = DataService(npub: npub, dataType: DataType.Profile);
    await dataService.initialize();

    setState(() {
      _dataService = dataService;
      _nameController.text = user?.name ?? '';
      _aboutController.text = user?.about ?? '';
      _pictureController.text = user?.profileImage ?? '';
      _nip05Controller.text = user?.nip05 ?? '';
      _bannerController.text = user?.banner ?? '';
      _lud16Controller.text = user?.lud16 ?? '';
      _websiteController.text = user?.website ?? '';
      _isLoading = false;
    });
  }

  Future<void> _pickAndUploadMedia({
    required TextEditingController controller,
    required String label,
    required bool isPicture,
  }) async {
    setState(() {
      if (isPicture) {
        _isUploadingPicture = true;
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
        final url = await _dataService!
            .sendMedia(filePath, 'https://blossom.primal.net');
        setState(() {
          controller.text = url;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$label uploaded successfully.')),
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
        if (isPicture) {
          _isUploadingPicture = false;
        } else {
          _isUploadingBanner = false;
        }
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;

    setState(() => _isSaving = true);

    try {
      await _dataService!.sendProfileEdit(
        name: _nameController.text.trim(),
        about: _aboutController.text.trim(),
        picture: _pictureController.text.trim(),
        nip05: _nip05Controller.text.trim(),
        banner: _bannerController.text.trim(),
        lud16: _lud16Controller.text.trim(),
        website: _websiteController.text.trim(),
      );

      final usersBox = await Hive.openBox<UserModel>('users');
      final updatedUser = usersBox.get(_dataService!.npub);

      if (updatedUser != null) {
        _dataService!.profilesNotifier.value = {
          ..._dataService!.profilesNotifier.value,
          updatedUser.npub: updatedUser,
        };
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  InputDecoration _inputDecoration(String label, {VoidCallback? onUpload}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        color: Colors.grey,
      ),
      filled: true,
      fillColor: Colors.black,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFECB200), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      suffixIcon: onUpload != null
          ? IconButton(
              icon: const Icon(Icons.upload, color: Color(0xFFECB200)),
              onPressed: onUpload,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveProfile,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Color(0xFFECB200),
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.check, color: Color(0xFFECB200)),
            label: Text(
              _isSaving ? 'Updating...' : 'Save',
              style: const TextStyle(
                color: Color(0xFFECB200),
                fontWeight: FontWeight.bold,
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
                decoration: _inputDecoration('Username'),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _aboutController,
                decoration: _inputDecoration('Bio'),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pictureController,
                enabled: !_isUploadingPicture,
                decoration: _inputDecoration(
                  'Profile image',
                  onUpload: _isUploadingPicture
                      ? null
                      : () => _pickAndUploadMedia(
                            controller: _pictureController,
                            label: 'Profile image',
                            isPicture: true,
                          ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bannerController,
                enabled: !_isUploadingBanner,
                decoration: _inputDecoration(
                  'Banner',
                  onUpload: _isUploadingBanner
                      ? null
                      : () => _pickAndUploadMedia(
                            controller: _bannerController,
                            label: 'Banner',
                            isPicture: false,
                          ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _lud16Controller,
                decoration: _inputDecoration('Lightning address'),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _websiteController,
                decoration: _inputDecoration('Website'),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
