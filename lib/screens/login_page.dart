import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nostr/nostr.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/screens/feed_page.dart';
import '../colors.dart';

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

  Future<void> _saveNsecAndNpub(String nsecBech32) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final nsecHex = Nip19.decodePrivkey(nsecBech32);
      if (nsecHex.isEmpty) {
        throw Exception('Invalid nsec format.');
      }

      final keychain = Keychain(nsecHex);
      final npubHex = keychain.public;

      await _secureStorage.write(key: 'privateKey', value: nsecHex);
      await _secureStorage.write(key: 'npub', value: npubHex);

      _tempService = DataService(npub: npubHex, dataType: DataType.feed);
      await _tempService!.initialize();
      await _tempService?.closeConnections();
      _tempService = null;

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FeedPage(npub: npubHex),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = 'Error: Invalid nsec input.';
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildLoginForm() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Welcome to Qiqstr!',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -1,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Login securely with your private key.',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          TextField(
            controller: _nsecController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Enter your nsec...',
              labelStyle: const TextStyle(color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.inputFill,
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: AppColors.inputBorder),
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: AppColors.inputFocused),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppColors.buttonPrimary,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                if (_nsecController.text.trim().isNotEmpty) {
                  _saveNsecAndNpub(_nsecController.text.trim());
                }
              },
              child: const Text('LOGIN', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 20),
          if (_message.isNotEmpty)
            Text(
              _message,
              style: const TextStyle(color: AppColors.error),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        CircularProgressIndicator(color: AppColors.loading),
        SizedBox(height: 20),
        Text(
          'Logging in...',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: _isLoading
              ? _buildLoadingScreen()
              : SingleChildScrollView(child: _buildLoginForm()),
        ),
      ),
    );
  }
}
