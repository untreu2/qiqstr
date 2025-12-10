import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qiqstr/ui/theme/theme_manager.dart';
import '../../widgets/common/title_widget.dart';
import '../auth/edit_new_account_profile.dart';

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
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: _buildBody(context),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: 16),
                _buildMnemonicTitle(context),
                const SizedBox(height: 8),
                _buildMnemonicCard(context),
                const SizedBox(height: 24),
                _buildWarningCard(context),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
        _buildActionButtons(context),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;

    return TitleWidget(
      title: 'Backup Your Account',
      fontSize: 32,
      subtitle: "Secure your account with your seed phrase.",
      useTopPadding: false,
      padding: EdgeInsets.fromLTRB(16, topPadding + 20, 16, 8),
    );
  }

  Widget _buildWarningCard(BuildContext context) {
    final warnings = [
      'Write down your seed phrase in the correct order',
      'Store it in a safe place',
      'Never share it with anyone',
      'If you lose it, you will lose access to your account forever',
      'You can access this later from Settings > Keys',
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
                  'Important',
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

  Widget _buildMnemonicTitle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 33, right: 16),
      child: Text(
        'Seed Phrase',
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(40),
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

  Widget _buildActionButtons(BuildContext context) {
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
              borderRadius: BorderRadius.circular(40),
            ),
            child: Text(
              'I have written down my seed phrase',
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
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => EditNewAccountProfilePage(
          npub: widget.npub,
        ),
      ),
    );
  }
}
