import 'package:carbon_icons/carbon_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/theme_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../widgets/dialogs/language_dialog.dart';
import '../../../l10n/app_localizations.dart';
import '../../../presentation/blocs/locale/locale_bloc.dart';
import '../../../presentation/blocs/locale/locale_state.dart';

class WelcomePage extends StatefulWidget {
  final bool isAddAccount;
  const WelcomePage({super.key, this.isAddAccount = false});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool _acceptedTerms = false;
  String _message = '';

  static const _termsUrl =
      'https://github.com/untreu2/qiqstr/blob/master/TERMS.md';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return BlocBuilder<LocaleBloc, LocaleState>(
      builder: (context, localeState) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTitle(context, l10n),
                            const SizedBox(height: 32),
                            _buildFeatures(context, l10n),
                          ],
                        ),
                      ),
                    ),
                    _buildAcceptTerms(context, l10n),
                    const SizedBox(height: 20),
                    if (_message.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Center(
                          child: Text(
                            _message,
                            style: TextStyle(
                              color: context.colors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    _buildBottomButtons(context, l10n),
                  ],
                ),
                _buildLanguageButton(context, localeState),
                if (widget.isAddAccount)
                  BackButtonWidget.floating(
                    onPressed: () => context.pop(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTitle(BuildContext context, AppLocalizations l10n) {
    final subtitle = l10n.welcomeSubtitle;
    final normalStyle = TextStyle(
      fontSize: 15,
      color: context.colors.textSecondary,
      height: 1.4,
    );
    final boldStyle = normalStyle.copyWith(fontWeight: FontWeight.w700);

    const boldWords = [
      'decentralized',
      'Nostr',
      'open source',
      'açık kaynaklı',
      'merkeziyetsiz',
      'dezentrales'
    ];
    final spans = <TextSpan>[];
    var remaining = subtitle;
    while (remaining.isNotEmpty) {
      int earliestIndex = remaining.length;
      String? matchedWord;
      for (final word in boldWords) {
        final idx = remaining.indexOf(word);
        if (idx != -1 && idx < earliestIndex) {
          earliestIndex = idx;
          matchedWord = word;
        }
      }
      if (matchedWord != null) {
        if (earliestIndex > 0) {
          spans.add(TextSpan(
              text: remaining.substring(0, earliestIndex), style: normalStyle));
        }
        spans.add(TextSpan(text: matchedWord, style: boldStyle));
        remaining = remaining.substring(earliestIndex + matchedWord.length);
      } else {
        spans.add(TextSpan(text: remaining, style: normalStyle));
        remaining = '';
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 72, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.welcomeTitle,
            style: GoogleFonts.poppins(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          RichText(text: TextSpan(children: spans)),
        ],
      ),
    );
  }

  Widget _buildFeatures(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildFeatureItem(
            context,
            Icons.public,
            l10n.welcomeFeatureDecentralized,
          ),
          const SizedBox(height: 24),
          _buildFeatureItem(
            context,
            Icons.vpn_key,
            l10n.welcomeFeatureKeys,
          ),
          const SizedBox(height: 24),
          _buildFeatureItem(
            context,
            Icons.lock,
            l10n.welcomeFeatureBitcoin,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(
      BuildContext context, IconData icon, String description) {
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

  Widget _buildAcceptTerms(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: GestureDetector(
        onTap: () => setState(() => _acceptedTerms = !_acceptedTerms),
        child: Row(
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
      ),
    );
  }

  Widget _buildBottomButtons(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 16,
        left: 24,
        right: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: l10n.createNewAccount,
              onPressed: _acceptedTerms
                  ? () => context.go('/signup')
                  : () => _showTermsRequired(l10n),
              size: ButtonSize.large,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _acceptedTerms
                ? () => context.go('/login')
                : () => _showTermsRequired(l10n),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n.welcomeAlreadyHaveAccount,
                style: TextStyle(
                  fontSize: 16,
                  color: context.colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTermsRequired(AppLocalizations l10n) {
    setState(() => _message = l10n.acceptanceOfTermsIsRequired);
  }

  Widget _buildLanguageButton(BuildContext context, LocaleState localeState) {
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
