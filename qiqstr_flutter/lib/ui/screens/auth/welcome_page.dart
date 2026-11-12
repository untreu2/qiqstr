import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/theme_manager.dart';
import '../../widgets/common/common_buttons.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../widgets/dialogs/language_dialog.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/blocs/welcome/welcome_bloc.dart';
import '../../../presentation/blocs/welcome/welcome_event.dart';
import '../../../presentation/blocs/welcome/welcome_state.dart';
import '../../../presentation/blocs/locale/locale_bloc.dart';
import '../../../presentation/blocs/locale/locale_state.dart';

class WelcomePage extends StatelessWidget {
  final bool isAddAccount;
  const WelcomePage({super.key, this.isAddAccount = false});

  static const _termsUrl =
      'https://github.com/untreu2/qiqstr/blob/master/TERMS.md';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return BlocProvider(
      create: (_) => AppDI.get<WelcomeBloc>(),
      child: BlocBuilder<WelcomeBloc, WelcomeState>(
        builder: (context, state) {
          final localeState = context.watch<LocaleBloc>().state;
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
                      if (state.showTermsError)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Center(
                            child: Text(
                              l10n.acceptanceOfTermsIsRequired,
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
                  if (isAddAccount)
                    BackButtonWidget.floating(
                      onPressed: () => context.pop(),
                    ),
                ],
              ),
            ),
          );
        },
      ),
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
              fontSize: 52,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
              letterSpacing: -1.5,
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
            PhosphorIcons.globe(),
            l10n.welcomeFeatureDecentralized,
          ),
          const SizedBox(height: 24),
          _buildFeatureItem(
            context,
            PhosphorIcons.key(),
            l10n.welcomeFeatureKeys,
          ),
          const SizedBox(height: 24),
          _buildFeatureItem(
            context,
            PhosphorIcons.lock(),
            l10n.welcomeFeatureBitcoin,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(
      BuildContext context, PhosphorIconData icon, String description) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: context.colors.overlayLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: PhosphorIcon(
              icon,
              color: context.colors.textPrimary,
              size: 20,
            ),
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
    final bloc = context.read<WelcomeBloc>();
    final acceptedTerms = bloc.state.acceptedTerms;
    return Center(
      child: GestureDetector(
        onTap: () => bloc.add(WelcomeTermsChanged(!acceptedTerms)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: acceptedTerms,
                onChanged: (value) =>
                    bloc.add(WelcomeTermsChanged(value ?? false)),
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
                    WidgetSpan(
                      child: GestureDetector(
                        onTap: () => launchUrl(
                          Uri.parse(_termsUrl),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Text(
                          l10n.termsOfUse,
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            decoration: TextDecoration.underline,
                            fontSize: 14,
                          ),
                        ),
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
    final bloc = context.read<WelcomeBloc>();
    final acceptedTerms = bloc.state.acceptedTerms;
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
              onPressed: acceptedTerms
                  ? () => context
                      .go(isAddAccount ? '/signup?addAccount=true' : '/signup')
                  : () => bloc.add(const WelcomeTermsRequired()),
              size: ButtonSize.large,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: acceptedTerms
                ? () => context
                    .go(isAddAccount ? '/login?addAccount=true' : '/login')
                : () => bloc.add(const WelcomeTermsRequired()),
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
          child: PhosphorIcon(
            PhosphorIcons.translate(),
            color: context.colors.background,
            size: 20,
          ),
        ),
      ),
    );
  }
}
