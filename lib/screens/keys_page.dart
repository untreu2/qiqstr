import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nostr/nostr.dart';
import 'package:qiqstr/theme/theme_manager.dart';
import '../widgets/back_button_widget.dart';
import '../widgets/toast_widget.dart';
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
      final hexPrivateKey = await _secureStorage.read(key: 'privateKey');
      final npubBech32 = await _secureStorage.read(key: 'npub');

      if (hexPrivateKey != null && npubBech32 != null) {
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

    AppToast.success(context, '${keyType.toUpperCase()} copied to clipboard!');

    setState(() => _copiedKeyType = keyType);

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copiedKeyType = null);
      }
    });
  }

  Widget _buildKeyDisplayCard(BuildContext context, String title, String value, String keyType, bool isCopied) {
    final displayValue = keyType == 'nsec' ? '•' * 48 : value;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: context.colors.border.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  displayValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    letterSpacing: keyType == 'nsec' ? 2 : 0,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _copyToClipboard(value, keyType),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    isCopied ? Icons.check : Icons.content_copy,
                    color: isCopied ? context.colors.success : context.colors.iconSecondary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Manage your Nostr identity keys securely.",
            style: TextStyle(
              fontSize: 15,
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
              const SizedBox(height: 8),
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
              const SizedBox(height: 32),
            ],
          ),
        ),
        const BackButtonWidget.floating(),
      ],
    );
  }
}

