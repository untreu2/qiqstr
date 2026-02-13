import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme_manager.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../widgets/common/title_widget.dart';
import '../../../l10n/app_localizations.dart';
import '../../../data/services/auth_service.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  String _message = '';
  bool _isLoading = false;
  final AuthService _authService = AuthService.instance;

  Future<void> _createNewAccount() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isLoading = true;
      _message = '';
    });

    try {
      final result = await _authService.createAccountWithMnemonic();
      if (result.isSuccess) {
        final mnemonicResult = await _authService.getCurrentUserMnemonic();
        if (mnemonicResult.isSuccess && mnemonicResult.data != null) {
          _navigateToKeysInfo(result.data!, mnemonicResult.data!);
        } else {
          _navigateToProfileSetup(result.data!);
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

  void _navigateToKeysInfo(String npub, String mnemonic) {
    if (mounted) {
      context.go(
        '/keys-info?npub=${Uri.encodeComponent(npub)}',
        extra: {'mnemonic': mnemonic},
      );
    }
  }

  void _navigateToProfileSetup(String npub) {
    if (mounted) {
      context.go('/profile-setup?npub=${Uri.encodeComponent(npub)}');
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
                                title: l10n.createNewAccount,
                                fontSize: 32,
                                subtitle: l10n.signupSubtitle,
                                useTopPadding: false,
                                padding:
                                    const EdgeInsets.fromLTRB(16, 72, 16, 8),
                              ),
                              const SizedBox(height: 32),
                              _buildFeatures(l10n),
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
              onPressed: () => context.go('/welcome'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatures(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildFeatureItem(
            Icons.vpn_key,
            l10n.signupFeatureKeys,
          ),
          const SizedBox(height: 24),
          _buildFeatureItem(
            Icons.shield,
            l10n.signupFeatureBackup,
          ),
          const SizedBox(height: 24),
          _buildFeatureItem(
            Icons.person,
            l10n.signupFeatureProfile,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String description) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: context.colors.overlayLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: context.colors.textPrimary,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            description,
            style: TextStyle(
              fontSize: 16,
              color: context.colors.textPrimary,
              height: 1.4,
            ),
          ),
        ),
      ],
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
          label: l10n.createNewAccount,
          onPressed: _createNewAccount,
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
          l10n.signupCreating,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 16),
        ),
      ],
    );
  }
}
