import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../theme/theme_manager.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/custom_input_field.dart';
import '../../widgets/common/title_widget.dart';
import '../../../l10n/app_localizations.dart';
import '../../../presentation/blocs/onboarding_spark/onboarding_spark_bloc.dart';
import '../../../presentation/blocs/onboarding_spark/onboarding_spark_event.dart';
import '../../../presentation/blocs/onboarding_spark/onboarding_spark_state.dart';

class RestoreWalletPage extends StatefulWidget {
  const RestoreWalletPage({super.key});

  @override
  State<RestoreWalletPage> createState() => _RestoreWalletPageState();
}

class _RestoreWalletPageState extends State<RestoreWalletPage> {
  final TextEditingController _controller = TextEditingController();
  bool _obscureText = true;
  String _errorMessage = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(BuildContext context) {
    final phrase = _controller.text.trim();
    if (phrase.isEmpty) return;
    setState(() => _errorMessage = '');
    context
        .read<OnboardingSparkBloc>()
        .add(OnboardingSparkRestoreRequested(phrase));
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData?.text != null) {
      _controller.text = clipboardData!.text!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return BlocListener<OnboardingSparkBloc, OnboardingSparkState>(
      listener: (context, state) {
        if (state is OnboardingSparkError) {
          setState(() => _errorMessage = state.message);
        }
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: SafeArea(
          child: BlocBuilder<OnboardingSparkBloc, OnboardingSparkState>(
            builder: (context, state) {
              final isLoading = state is OnboardingSparkLoading;

              return Stack(
                children: [
                  isLoading
                      ? Center(child: _buildLoadingScreen(colors, l10n))
                      : Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TitleWidget(
                                      title: l10n.restoreWallet,
                                      fontSize: 32,
                                      subtitle: l10n.restoreWalletSubtitle,
                                      useTopPadding: false,
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 72, 16, 8),
                                    ),
                                    const SizedBox(height: 32),
                                    _buildInputSection(context, colors, l10n),
                                    if (_errorMessage.isNotEmpty) ...[
                                      const SizedBox(height: 16),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 24),
                                        child: Text(
                                          _errorMessage,
                                          style: TextStyle(
                                            color: colors.error,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            _buildBottomSection(context, l10n),
                          ],
                        ),
                  BackButtonWidget.floating(
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInputSection(
      BuildContext context, AppThemeColors colors, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: CustomInputField(
        controller: _controller,
        labelText: l10n.restoreWalletHint,
        fillColor: colors.inputFill,
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
                  color: colors.textSecondary,
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
                    color: colors.textPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.content_paste,
                    color: colors.background,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSection(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 24, right: 24),
      child: SizedBox(
        width: double.infinity,
        child: PrimaryButton(
          label: l10n.restoreWalletButton,
          onPressed: () => _submit(context),
          size: ButtonSize.large,
        ),
      ),
    );
  }

  Widget _buildLoadingScreen(AppThemeColors colors, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: colors.loading),
        const SizedBox(height: 20),
        Text(
          l10n.restoreWallet,
          style: TextStyle(color: colors.textSecondary, fontSize: 16),
        ),
      ],
    );
  }
}
