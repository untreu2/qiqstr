import 'package:carbon_icons/carbon_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:qiqstr/data/services/auth_service.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/theme_manager.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../widgets/common/custom_input_field.dart';
import '../../widgets/dialogs/language_dialog.dart';
import '../../../l10n/app_localizations.dart';
import '../../../presentation/blocs/locale/locale_bloc.dart';
import '../../../presentation/blocs/locale/locale_state.dart';

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
  bool _acceptedTerms = false;
  final AuthService _authService = AuthService.instance;

  static const _termsUrl =
      'https://github.com/untreu2/qiqstr/blob/master/TERMS.md';

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _loginWithInput() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_acceptedTerms) {
      setState(() => _message = l10n.acceptanceOfTermsIsRequired);
      return;
    }
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
    if (!_acceptedTerms) {
      setState(() => _message = l10n.acceptanceOfTermsIsRequired);
      return;
    }
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
      context.go('/onboarding-coinos?npub=${Uri.encodeComponent(npub)}');
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
          const SizedBox(height: 32),
          _buildAcceptTerms(),
          const SizedBox(height: 12),
          if (_message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _message,
                style: TextStyle(
                    color: context.colors.error, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAcceptTerms() {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () => setState(() => _acceptedTerms = !_acceptedTerms),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: _acceptedTerms,
              onChanged: (value) =>
                  setState(() => _acceptedTerms = value ?? false),
              activeColor: context.colors.textPrimary,
              checkColor: context.colors.background,
              side: BorderSide(color: context.colors.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 14,
                ),
                children: [
                  TextSpan(text: l10n.iAcceptThe),
                  TextSpan(
                    text: l10n.termsOfUse,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => launchUrl(
                            Uri.parse(_termsUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                  ),
                ],
              ),
            ),
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
    return BlocBuilder<LocaleBloc, LocaleState>(
      builder: (context, localeState) {
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
                _buildLanguageButton(localeState),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLanguageButton(LocaleState localeState) {
    return Positioned(
      top: 14,
      right: 16,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: context.colors.textPrimary,
          borderRadius: BorderRadius.circular(22.0),
        ),
        child: GestureDetector(
          onTap: () => showLanguageDialog(
            context: context,
            currentLocale: localeState.locale,
          ),
          behavior: HitTestBehavior.opaque,
          child: Icon(
            CarbonIcons.language,
            color: context.colors.background,
            size: 20,
          ),
        ),
      ),
    );
  }
}
