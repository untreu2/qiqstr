import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qiqstr/data/services/auth_service.dart';

import '../../theme/theme_manager.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../widgets/common/custom_input_field.dart';
import '../../../l10n/app_localizations.dart';

class LoginPage extends StatefulWidget {
  final bool isAddAccount;
  const LoginPage({super.key, this.isAddAccount = false});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _inputController = TextEditingController();
  String _message = '';
  bool _isLoading = false;
  final AuthService _authService = AuthService.instance;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _loginWithInput() async {
    final l10n = AppLocalizations.of(context)!;
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
              _message = l10n.errorPrefix(result.error ?? l10n.unknownError);
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
              _message = l10n.errorPrefix(result.error ?? l10n.unknownError);
              _isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = l10n.errorInvalidInput;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createNewAccount() async {
    final l10n = AppLocalizations.of(context)!;
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
            _message = l10n.errorPrefix(result.error ?? l10n.unknownError);
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = l10n.errorCouldNotCreateAccount;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _navigateToKeysInfo(String npub, String mnemonic) async {
    if (mounted) {
      context.go(
        '/keys-info?npub=${Uri.encodeComponent(npub)}',
        extra: {'mnemonic': mnemonic},
      );
    }
  }

  Future<void> _navigateToProfileSetup(String npub) async {
    if (mounted) {
      context.go('/profile-setup?npub=${Uri.encodeComponent(npub)}');
    }
  }

  Future<void> _navigateToHome(String npub) async {
    if (mounted) {
      context.go('/home/feed?npub=${Uri.encodeComponent(npub)}');
    }
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData != null && clipboardData.text != null) {
      _inputController.text = clipboardData.text!;
    }
  }

  Widget _buildLoginForm() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CustomInputField(
            controller: _inputController,
            labelText: l10n.enterSeedPhraseOrNsec,
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
            child: PrimaryButton(
              label: l10n.login,
              onPressed: _isLoading ? null : _loginWithInput,
              size: ButtonSize.large,
              isLoading: _isLoading,
              backgroundColor: context.colors.inputFill,
              foregroundColor: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: l10n.createNewAccount,
              onPressed: _isLoading ? null : _createNewAccount,
              size: ButtonSize.large,
            ),
          ),
          const SizedBox(height: 20),
          if (_message.isNotEmpty)
            Text(
              _message,
              style: TextStyle(
                  color: context.colors.error, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: context.colors.loading),
        const SizedBox(height: 20),
        Text(
          l10n.loggingIn,
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
        child: Stack(
          children: [
            Center(
              child: _isLoading
                  ? _buildLoadingScreen()
                  : SingleChildScrollView(child: _buildLoginForm()),
            ),
            if (widget.isAddAccount)
              BackButtonWidget.floating(
                onPressed: () => context.pop(),
              ),
          ],
        ),
      ),
    );
  }
}
