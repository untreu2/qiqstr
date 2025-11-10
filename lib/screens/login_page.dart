import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qiqstr/data/services/auth_service.dart';
import 'package:qiqstr/screens/home_navigator.dart';
import 'package:qiqstr/screens/edit_new_account_profile.dart';
import 'package:qiqstr/screens/keys_info_page.dart';

import 'package:qiqstr/theme/theme_manager.dart';
import 'package:qiqstr/widgets/common_buttons.dart';

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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: SvgPicture.asset(
                        'assets/main_icon_white.svg',
                        width: 50,
                        height: 50,
                        colorFilter: ColorFilter.mode(context.colors.textPrimary, BlendMode.srcIn),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 40,
                          decoration: BoxDecoration(
                            color: context.colors.accent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'qiqstr',
                          style: GoogleFonts.poppins(
                            fontSize: 48,
                            fontWeight: FontWeight.w700,
                            color: context.colors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 40),
          TextField(
            controller: _inputController,
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Enter your seed phrase or nsec...',
              labelStyle: TextStyle(color: context.colors.textSecondary),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: _pasteFromClipboard,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.colors.buttonPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.content_paste,
                      color: context.colors.buttonText,
                      size: 20,
                    ),
                  ),
                ),
              ),
              filled: true,
              fillColor: context.colors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(40),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Login',
              onPressed: _isLoading ? null : _loginWithInput,
              size: ButtonSize.large,
              isLoading: _isLoading,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SecondaryButton(
              label: 'Create a New Account',
              onPressed: _isLoading ? null : _createNewAccount,
              size: ButtonSize.large,
              backgroundColor: context.colors.overlayLight,
              foregroundColor: context.colors.textPrimary,
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
