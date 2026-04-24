import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme_manager.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../widgets/common/custom_input_field.dart';
import '../../widgets/common/title_widget.dart';
import '../../../l10n/app_localizations.dart';
import '../../../data/services/auth_service.dart';

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
  bool _obscureText = true;
  final AuthService _authService = AuthService.instance;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _loginWithInput() async {
    final l10n = AppLocalizations.of(context)!;
    if (_inputController.text.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _message = '';
    });

    final input = _inputController.text.trim();

    try {
      if (input.startsWith('nsec1')) {
        final result = await _authService.loginWithNsec(input);
        if (result.isSuccess) {
          _navigateAfterLogin(result.data!);
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
          _navigateAfterLogin(result.data!);
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

  void _navigateAfterLogin(String npub) {
    if (mounted) {
      context.go('/onboarding-spark?npub=${Uri.encodeComponent(npub)}');
    }
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData != null && clipboardData.text != null) {
      _inputController.text = clipboardData.text!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Stack(
          children: [
            _isLoading
                ? Center(child: _buildLoadingScreen(l10n))
                : Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TitleWidget(
                                title: l10n.login,
                                fontSize: 32,
                                subtitle: l10n.loginSubtitle,
                                useTopPadding: false,
                                padding:
                                    const EdgeInsets.fromLTRB(16, 72, 16, 8),
                              ),
                              const SizedBox(height: 32),
                              _buildInputSection(l10n),
                              if (_message.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24),
                                  child: Text(
                                    _message,
                                    style: TextStyle(
                                      color: context.colors.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      _buildBottomSection(l10n),
                    ],
                  ),
            BackButtonWidget.floating(
              onPressed: () {
                if (widget.isAddAccount) {
                  context.pop();
                } else {
                  context.go('/welcome');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputSection(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomInputField(
            controller: _inputController,
            labelText: l10n.enterSeedPhraseOrNsec,
            fillColor: context.colors.inputFill,
            obscureText: _obscureText,
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _obscureText = !_obscureText),
                    child: Icon(
                      _obscureText ? Icons.visibility_off : Icons.visibility,
                      color: context.colors.textSecondary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            l10n.loginExampleSeed,
            style: TextStyle(
              fontSize: 12,
              color: context.colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.loginExampleNsec,
            style: TextStyle(
              fontSize: 12,
              color: context.colors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSection(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 16,
        left: 24,
        right: 24,
      ),
      child: SizedBox(
        width: double.infinity,
        child: PrimaryButton(
          label: l10n.login,
          onPressed: _loginWithInput,
          size: ButtonSize.large,
        ),
      ),
    );
  }

  Widget _buildLoadingScreen(AppLocalizations l10n) {
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
}
