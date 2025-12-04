import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qiqstr/data/services/auth_service.dart';
import '../home_navigator.dart';
import 'edit_new_account_profile.dart';
import '../settings/keys_info_page.dart';

import '../../theme/theme_manager.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/brand_widget.dart';
import '../../widgets/common/custom_input_field.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  String _message = '';
  bool _isLoading = false;
  final AuthService _authService = AuthService.instance;

  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _bounceAnimation = Tween<double>(
      begin: 1.0,
      end: 1.03,
    ).animate(CurvedAnimation(
      parent: _bounceController,
      curve: Curves.easeInOut,
    ));

    _inputController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (_inputController.text.isNotEmpty) {
      _bounceController.forward().then((_) {
        _bounceController.reverse();
      });
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _loginWithInput() async {
    if (_inputController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);

    final input = _inputController.text.trim();

    try {
      if (input.startsWith('nsec1')) {
        final result = await _authService.loginWithNsec(input);
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
      } else {
        final result = await _authService.loginWithMnemonic(input);
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
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = 'Error: Invalid input. Please check your NSEC or mnemonic phrase.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createNewAccount() async {
    setState(() => _isLoading = true);
    try {
      final result = await _authService.createAccountWithMnemonic();
      if (result.isSuccess) {
        final mnemonicResult = await _authService.getCurrentUserMnemonic();
        if (mnemonicResult.isSuccess && mnemonicResult.data != null) {
          await _navigateToKeysInfo(result.data!, mnemonicResult.data!);
        } else {
          await _navigateToProfileSetup(result.data!);
        }
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

  Future<void> _navigateToKeysInfo(String npub, String mnemonic) async {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => KeysInfoPage(
            npub: npub,
            mnemonic: mnemonic,
          ),
        ),
      );
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

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData != null && clipboardData.text != null) {
      _inputController.text = clipboardData.text!;
    }
  }

  Widget _buildLoginForm() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _bounceAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _bounceAnimation.value,
                child: const BrandWidget(),
              );
            },
          ),
          const SizedBox(height: 40),
          CustomInputField(
            controller: _inputController,
            labelText: 'Enter your seed phrase or nsec...',
            fillColor: context.colors.inputFill,
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: _pasteFromClipboard,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: context.colors.textPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.content_paste,
                    color: context.colors.background,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: SecondaryButton(
              label: 'Login',
              onPressed: _isLoading ? null : _loginWithInput,
              size: ButtonSize.large,
              isLoading: _isLoading,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Create a New Account',
              onPressed: _isLoading ? null : _createNewAccount,
              size: ButtonSize.large,
            ),
          ),
          const SizedBox(height: 20),
          if (_message.isNotEmpty)
            Text(
              _message,
              style: TextStyle(color: context.colors.error, fontWeight: FontWeight.w600),
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
