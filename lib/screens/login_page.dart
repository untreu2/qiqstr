import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nostr/nostr.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/screens/home_navigator.dart';
import 'package:qiqstr/screens/edit_new_account_profile.dart';

import 'package:qiqstr/theme/theme_manager.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _nsecController = TextEditingController();
  String _message = '';
  bool _isLoading = false;
  DataService? _tempService;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  @override
  void dispose() {
    _nsecController.dispose();
    _tempService?.closeConnections();
    super.dispose();
  }

  Future<void> _loginWithNsecInput() async {
    if (_nsecController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final nsecHex = Nip19.decodePrivkey(_nsecController.text.trim());
      if (nsecHex.isEmpty) throw Exception('Invalid nsec format.');
      await _login(nsecHex);
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = 'Error: Invalid nsec input.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createNewAccount() async {
    setState(() => _isLoading = true);
    try {
      final keychain = Keychain.generate();
      await _loginNewAccount(keychain.private);
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = 'Error: Could not create a new account.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loginNewAccount(String nsecHex) async {
    try {
      final keychain = Keychain(nsecHex);
      final npubHex = keychain.public;

      await _secureStorage.write(key: 'privateKey', value: nsecHex);
      await _secureStorage.write(key: 'npub', value: npubHex);

      final dataService = DataService(npub: npubHex, dataType: DataType.feed);
      await dataService.initialize();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EditNewAccountProfilePage(
              npub: npubHex,
              dataService: dataService,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = 'Error: Account creation failed.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _login(String nsecHex) async {
    try {
      final keychain = Keychain(nsecHex);
      final npubHex = keychain.public;

      await _secureStorage.write(key: 'privateKey', value: nsecHex);
      await _secureStorage.write(key: 'npub', value: npubHex);

      final dataService = DataService(npub: npubHex, dataType: DataType.feed);
      await dataService.initialize();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeNavigator(
              npub: npubHex,
              dataService: dataService,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = 'Error: Login failed.';
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildLoginForm() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/main_icon_white.svg',
            height: 100,
            width: 100,
            color: context.colors.textPrimary,
          ),
          const SizedBox(height: 40),
          TextField(
            controller: _nsecController,
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Enter your nsec...',
              labelStyle: TextStyle(color: context.colors.textSecondary),
              filled: true,
              fillColor: context.colors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _loginWithNsecInput,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.buttonPrimary,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: context.colors.borderAccent),
              ),
              child: Text(
                'Login',
                style: TextStyle(
                  color: context.colors.background,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _createNewAccount,
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
                'Create a New Account',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_message.isNotEmpty)
            Text(
              _message,
              style: TextStyle(color: context.colors.error, fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: context.colors.loading),
        const SizedBox(height: 20),
        Text(
          'Logging in...',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 16),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Center(
          child: _isLoading ? _buildLoadingScreen() : SingleChildScrollView(child: _buildLoginForm()),
        ),
      ),
    );
  }
}
