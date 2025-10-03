import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nostr/nostr.dart';
import 'package:qiqstr/theme/theme_manager.dart';
import '../widgets/back_button_widget.dart';
import 'package:provider/provider.dart';

class KeysPage extends StatefulWidget {
  const KeysPage({super.key});

  @override
  State<KeysPage> createState() => _KeysPageState();
}

class _KeysPageState extends State<KeysPage> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String _nsecBech32 = 'Loading...';
  String _npubBech32 = 'Loading...';
  String? _copiedKeyType;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    try {
      // Read hex private key and npub from storage
      final hexPrivateKey = await _secureStorage.read(key: 'privateKey');
      final npubBech32 = await _secureStorage.read(key: 'npub');

      if (hexPrivateKey != null && npubBech32 != null) {
        // Generate nsec from hex private key dynamically
        String nsecBech32;
        try {
          nsecBech32 = Nip19.encodePrivkey(hexPrivateKey);
        } catch (e) {
          nsecBech32 = 'Error encoding nsec';
        }

        setState(() {
          _nsecBech32 = nsecBech32;
          _npubBech32 = npubBech32;
        });
      } else {
        setState(() {
          _nsecBech32 = 'Not found';
          _npubBech32 = 'Not found';
        });
      }
    } catch (e) {
      setState(() {
        _nsecBech32 = 'Error loading keys';
        _npubBech32 = 'Error loading keys';
      });
      if (kDebugMode) {
        print('Error loading keys: \$e');
      }
    }
  }

  Future<void> _copyToClipboard(String text, String keyType) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${keyType.toUpperCase()} copied to clipboard!'),
        backgroundColor: context.colors.success.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );

    setState(() => _copiedKeyType = keyType);

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copiedKeyType = null);
      }
    });
  }

  Widget _buildKeyDisplayCard(BuildContext context, String title, String value, String keyType, bool isCopied) {
    final displayValue = keyType == 'nsec' ? '****************************************************************' : value;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  displayValue,
                  maxLines: 1,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 15,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: isCopied
                    ? Icon(Icons.check, color: context.colors.success)
                    : Icon(Icons.copy_outlined, color: context.colors.iconPrimary),
                onPressed: () => _copyToClipboard(value, keyType),
                tooltip: 'Copy to clipboard',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimerCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: context.colors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What are these keys?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16.0),
          _buildDisclaimerRow(
            context,
            title: 'Private Key (nsec)',
            description:
                'This is your password. Keep it secret and never share it. It allows you to sign messages and control your identity.',
          ),
          const SizedBox(height: 16.0),
          _buildDisclaimerRow(
            context,
            title: 'Public Key (npub)',
            description: 'This is your username. Share it with others so they can find you and interact with your profile.',
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimerRow(BuildContext context, {required String title, required String description}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: context.colors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(color: context.colors.textSecondary, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding + 70, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keys',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            "Manage your Nostr identity keys securely.",
            style: TextStyle(
              fontSize: 14,
              color: context.colors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

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
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              _buildKeyDisplayCard(
                context,
                'Private Key (nsec)',
                _nsecBech32,
                'nsec',
                _copiedKeyType == 'nsec',
              ),
              _buildKeyDisplayCard(
                context,
                'Public Key (npub)',
                _npubBech32,
                'npub',
                _copiedKeyType == 'npub',
              ),
              const SizedBox(height: 16),
              _buildDisclaimerCard(context),
              const SizedBox(height: 24),
            ],
          ),
        ),
        const BackButtonWidget.floating(),
      ],
    );
  }
}
