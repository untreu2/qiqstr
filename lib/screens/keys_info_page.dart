import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qiqstr/theme/theme_manager.dart';
import '../widgets/back_button_widget.dart';
import 'edit_new_account_profile.dart';

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
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 8),
                    _buildMnemonicCard(context),
                    const SizedBox(height: 60),
                    _buildWarningCard(context),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
            _buildActionButtons(context),
            const SizedBox(height: 32),
          ],
        ),
        const BackButtonWidget.floating(),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding + 70, 16, 8),
      child: Text(
        'Backup Your Account',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: context.colors.textPrimary,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _buildWarningCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.colors.error.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_rounded,
                color: context.colors.error,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Important',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: context.colors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '• Write down your seed phrase in the correct order\n'
            '• Store it in a safe place\n'
            '• Never share it with anyone\n'
            '• If you lose it, you will lose access to your account forever\n'
            '• You can access this later from Settings > Keys',
            style: TextStyle(
              fontSize: 14,
              color: context.colors.textPrimary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMnemonicCard(BuildContext context) {
    final words = widget.mnemonic.split(' ');
    final mnemonicWithCommas = words.join(', ');
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: context.colors.border.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seed Phrase',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            mnemonicWithCommas,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: GestureDetector(
        onTap: _continueToProfile,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: context.colors.buttonPrimary,
            borderRadius: BorderRadius.circular(40),
          ),
          child: Text(
            'I have written down my seed phrase',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.buttonText,
              fontSize: 17,
              fontWeight: FontWeight.w600,
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
