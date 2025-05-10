import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qiqstr/screens/profile_page.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:hive/hive.dart';

class EditOwnProfilePage extends StatefulWidget {
  const EditOwnProfilePage({super.key});

  @override
  State<EditOwnProfilePage> createState() => _EditOwnProfilePageState();
}

class _EditOwnProfilePageState extends State<EditOwnProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _secureStorage = const FlutterSecureStorage();

  late TextEditingController _nameController;
  late TextEditingController _aboutController;
  late TextEditingController _pictureController;
  late TextEditingController _nip05Controller;
  late TextEditingController _bannerController;
  late TextEditingController _lud16Controller;
  late TextEditingController _websiteController;

  DataService? _dataService;

  bool _isSaving = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
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
      _nameController = TextEditingController(text: user?.name ?? '');
      _aboutController = TextEditingController(text: user?.about ?? '');
      _pictureController =
          TextEditingController(text: user?.profileImage ?? '');
      _nip05Controller = TextEditingController(text: user?.nip05 ?? '');
      _bannerController = TextEditingController(text: user?.banner ?? '');
      _lud16Controller = TextEditingController(text: user?.lud16 ?? '');
      _websiteController = TextEditingController(text: user?.website ?? '');
      _isLoading = false;
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

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

      if (mounted && updatedUser != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ProfilePage(user: updatedUser),
          ),
        );
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextFormField(
                controller: _aboutController,
                decoration: const InputDecoration(labelText: 'About'),
              ),
              TextFormField(
                controller: _pictureController,
                decoration:
                    const InputDecoration(labelText: 'Profile Image URL'),
              ),
              TextFormField(
                controller: _nip05Controller,
                decoration: const InputDecoration(labelText: 'nip05'),
              ),
              TextFormField(
                controller: _bannerController,
                decoration: const InputDecoration(labelText: 'Banner URL'),
              ),
              TextFormField(
                controller: _lud16Controller,
                decoration: const InputDecoration(labelText: 'lud16'),
              ),
              TextFormField(
                controller: _websiteController,
                decoration: const InputDecoration(labelText: 'Website'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFECB200), width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _isSaving ? null : _saveProfile,
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
