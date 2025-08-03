import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nostr/nostr.dart';
import 'package:qiqstr/theme/theme_manager.dart';
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
  String _copyMessage = '';

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    try {
      final nsecHex = await _secureStorage.read(key: 'privateKey');
      final npubHex = await _secureStorage.read(key: 'npub');

      if (nsecHex != null && npubHex != null) {
        setState(() {
          _nsecBech32 = Nip19.encodePrivkey(nsecHex);
          _npubBech32 = Nip19.encodePubkey(npubHex);
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
      print('Error loading keys: \$e');
    }
  }

  Future<void> _copyToClipboard(String text, String keyType) async {
    await Clipboard.setData(ClipboardData(text: text));
    setState(() {
      _copyMessage = '\$keyType copied to clipboard!';
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _copyMessage = '';
        });
      }
    });
  }

  Widget _buildKeyTile(BuildContext context, String title, String value, String keyType) {
    final displayValue = keyType == 'nsec' ? '****************************************************************' : value;
    return ListTile(
      title: Text(title, style: TextStyle(color: context.colors.textPrimary)),
      subtitle: SelectableText(
        displayValue,
        maxLines: 1,
        style: TextStyle(color: context.colors.textSecondary),
      ),
      trailing: IconButton(
        icon: Icon(Icons.copy, color: context.colors.iconPrimary),
        onPressed: () => _copyToClipboard(value, keyType),
        tooltip: 'Copy to clipboard',
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: context.colors.iconPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8.0),
          Text(
            'Your Keys',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: context.colors.textPrimary,
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
          body: Stack(
            children: [
              SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    _buildDisclaimer(context),
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: 2, // For nsec and npub
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _buildKeyTile(
                              context,
                              'Private Key (nsec):',
                              _nsecBech32,
                              'nsec',
                            );
                          } else {
                            return _buildKeyTile(
                              context,
                              'Public Key (npub):',
                              _npubBech32,
                              'npub',
                            );
                          }
                        },
                        separatorBuilder: (_, __) => Divider(
                          color: context.colors.border,
                          height: 1,
                        ),
                      ),
                    ),
                    if (_copyMessage.isNotEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            _copyMessage,
                            style: TextStyle(
                              color: context.colors.success,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDisclaimer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0, top: 0.0),
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
          const SizedBox(height: 8.0),
          Text(
            'Your private key (nsec) is like a password. Keep it secret and never share it with anyone. It allows you to sign messages and prove your identity on the Nostr network.',
            style: TextStyle(color: context.colors.textSecondary),
          ),
          const SizedBox(height: 8.0),
          Text(
            'Your public key (npub) is like your username. You can share it with others so they can find you and interact with your profile.',
            style: TextStyle(color: context.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
