import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qiqstr/data/services/auth_service.dart';
import 'package:qiqstr/screens/home_navigator.dart';
import 'package:qiqstr/screens/edit_new_account_profile.dart';

import 'package:qiqstr/theme/theme_manager.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _nsecController = TextEditingController();
  String _message = '';
  bool _isLoading = false;
  final AuthService _authService = AuthService.instance;

  @override
  void dispose() {
    _nsecController.dispose();
    super.dispose();
  }

  Future<void> _loginWithNsecInput() async {
    if (_nsecController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final result = await _authService.loginWithNsec(_nsecController.text.trim());
      if (result.isSuccess) {
        await _navigateToHome(result.data!);
      } else {
        if (mounted) {
          setState(() {
            _message = 'Error: ${result.error}';
            _isLoading = false;
          });
        }
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

  Future<void> _createNewAccount() async {
    setState(() => _isLoading = true);
    try {
      final result = await _authService.createNewAccount();
      if (result.isSuccess) {
        await _navigateToProfileSetup(result.data!);
      } else {
        if (mounted) {
          setState(() {
            _message = 'Error: ${result.error}';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = 'Error: Could not create a new account.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _navigateToProfileSetup(String npub) async {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => EditNewAccountProfilePage(
            npub: npub,
          ),
        ),
      );
    }
  }

  Future<void> _navigateToHome(String npub) async {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeNavigator(
            npub: npub,
          ),
        ),
      );
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
            colorFilter: ColorFilter.mode(context.colors.textPrimary, BlendMode.srcIn),
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
