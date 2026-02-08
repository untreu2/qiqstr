import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qiqstr/ui/theme/theme_manager.dart';
import '../../widgets/common/title_widget.dart';
import '../../../presentation/blocs/theme/theme_bloc.dart';
import '../../../presentation/blocs/theme/theme_state.dart';
import '../../../l10n/app_localizations.dart';

class KeysInfoPage extends StatefulWidget {
  final String mnemonic;
  final String npub;

  const KeysInfoPage({
    super.key,
    required this.mnemonic,
    required this.npub,
  });

  @override
  State<KeysInfoPage> createState() => _KeysInfoPageState();
}

class _KeysInfoPageState extends State<KeysInfoPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<ThemeBloc, ThemeState>(
      builder: (context, themeState) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: _buildBody(context, l10n),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, l10n),
                const SizedBox(height: 16),
                _buildMnemonicTitle(context, l10n),
                const SizedBox(height: 8),
                _buildMnemonicCard(context),
                const SizedBox(height: 24),
                _buildWarningCard(context, l10n),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
        _buildActionButtons(context, l10n),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    final double topPadding = MediaQuery.of(context).padding.top;

    return TitleWidget(
      title: l10n.backupYourAccount,
      fontSize: 32,
      subtitle: l10n.secureYourAccount,
      useTopPadding: false,
      padding: EdgeInsets.fromLTRB(16, topPadding + 20, 16, 8),
    );
  }

  Widget _buildWarningCard(BuildContext context, AppLocalizations l10n) {
    final warnings = [
      l10n.writeSeedPhraseInOrder,
      l10n.storeItSafely,
      l10n.neverShareIt,
      l10n.ifYouLoseIt,
      l10n.accessFromSettings,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 17),
            child: Row(
              children: [
                Icon(
                  Icons.warning_rounded,
                  color: context.colors.error,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.important,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: context.colors.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...warnings.map((warning) => Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 17),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: TextStyle(
                        fontSize: 15,
                        color: context.colors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        warning,
                        style: TextStyle(
                          fontSize: 15,
                          color: context.colors.textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildMnemonicTitle(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(left: 33, right: 16),
      child: Text(
        l10n.seedPhrase,
        style: TextStyle(
          color: context.colors.textSecondary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildMnemonicCard(BuildContext context) {
    final words = widget.mnemonic.split(' ');
    final mnemonicWithCommas = words.join(', ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          mnemonicWithCommas,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      decoration: BoxDecoration(
        color: context.colors.background,
      ),
      child: SizedBox(
        width: double.infinity,
        child: GestureDetector(
          onTap: _continueToProfile,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: context.colors.textPrimary,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              l10n.iHaveWrittenDownSeedPhrase,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.background,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _continueToProfile() {
    context.go('/profile-setup?npub=${Uri.encodeComponent(widget.npub)}');
  }
}
