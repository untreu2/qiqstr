import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../data/services/rust_nostr_bridge.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qiqstr/ui/theme/theme_manager.dart';
import '../../widgets/common/back_button_widget.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../widgets/common/title_widget.dart';
import '../../widgets/dialogs/copy_key_warning_dialog.dart';
import '../../../presentation/blocs/theme/theme_bloc.dart';
import '../../../presentation/blocs/theme/theme_state.dart';

class KeysPage extends StatefulWidget {
  const KeysPage({super.key});

  @override
  State<KeysPage> createState() => _KeysPageState();
}

class _KeysPageState extends State<KeysPage> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String _nsecBech32 = 'Loading...';
  String _npubBech32 = 'Loading...';
  String _mnemonic = 'Loading...';
  String? _copiedKeyType;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    try {
      final hexPrivateKey = await _secureStorage.read(key: 'privateKey');
      final npubBech32 = await _secureStorage.read(key: 'npub');
      final mnemonic = await _secureStorage.read(key: 'mnemonic');

      if (hexPrivateKey != null && npubBech32 != null) {
        String nsecBech32;
        try {
          nsecBech32 = Nip19.encodePrivateKey(hexPrivateKey);
        } catch (e) {
          nsecBech32 = 'Error encoding nsec';
        }

        setState(() {
          _nsecBech32 = nsecBech32;
          _npubBech32 = npubBech32;
          _mnemonic = mnemonic ?? 'Not available';
        });
      } else {
        setState(() {
          _nsecBech32 = 'Not found';
          _npubBech32 = 'Not found';
          _mnemonic = 'Not found';
        });
      }
    } catch (e) {
      setState(() {
        _nsecBech32 = 'Error loading keys';
        _npubBech32 = 'Error loading keys';
        _mnemonic = 'Error loading keys';
      });
      if (kDebugMode) {
        print('Error loading keys: \$e');
      }
    }
  }

  Future<void> _copyToClipboard(String text, String keyType) async {
    if (keyType == 'nsec' || keyType == 'mnemonic') {
      final shouldCopy = await showCopyKeyWarningDialog(
        context: context,
        keyType: keyType == 'nsec' ? 'Private Key (nsec)' : 'Seed Phrase',
      );

      if (!shouldCopy || !mounted) return;
    }

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;

    AppSnackbar.success(
        context, '${keyType.toUpperCase()} copied to clipboard!');

    setState(() => _copiedKeyType = keyType);

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copiedKeyType = null);
      }
    });
  }

  Widget _buildKeyTitle(BuildContext context, String title,
      {String? description}) {
    return Padding(
      padding: const EdgeInsets.only(left: 33, right: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                color: context.colors.textSecondary.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKeyDisplayCard(BuildContext context, String title, String value,
      String keyType, bool isCopied) {
    final isMasked = keyType == 'mnemonic' || keyType == 'nsec';
    final displayValue = isMasked ? '•' * 48 : value;

    String? description;
    if (keyType == 'npub') {
      description = 'Share this with others to receive messages and zaps.';
    } else if (keyType == 'nsec') {
      description = 'Keep this secret! Never share it with anyone.';
    } else if (keyType == 'mnemonic') {
      description = 'Use this to recover your account. Store it safely.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildKeyTitle(context, title, description: description),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: context.colors.overlayLight,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayValue,
                    maxLines: isMasked ? 3 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      letterSpacing: isMasked ? 2 : 0,
                      height: isMasked ? 1.4 : 1.0,
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
                      color: isCopied
                          ? context.colors.success
                          : context.colors.iconSecondary,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedLink(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: GestureDetector(
          onTap: () {
            setState(() {
              _showAdvanced = !_showAdvanced;
            });
          },
          child: Text(
            'Advanced',
            style: TextStyle(
              fontSize: 15,
              color: context.colors.textSecondary,
              decoration: TextDecoration.underline,
              decorationColor: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 60),
      child: const TitleWidget(
        title: 'Keys',
        fontSize: 32,
        subtitle: "Manage your Nostr identity keys.",
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeBloc, ThemeState>(
      builder: (context, themeState) {
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
              const SizedBox(height: 16),
              _buildKeyDisplayCard(
                context,
                'Public Key (npub)',
                _npubBech32,
                'npub',
                _copiedKeyType == 'npub',
              ),
              const SizedBox(height: 24),
              if (_showAdvanced) ...[
                _buildKeyDisplayCard(
                  context,
                  'Private Key (nsec)',
                  _nsecBech32,
                  'nsec',
                  _copiedKeyType == 'nsec',
                ),
                const SizedBox(height: 24),
              ],
              _buildKeyDisplayCard(
                context,
                'Seed Phrase',
                _mnemonic,
                'mnemonic',
                _copiedKeyType == 'mnemonic',
              ),
              const SizedBox(height: 32),
              _buildAdvancedLink(context),
              const SizedBox(height: 32),
            ],
          ),
        ),
        const BackButtonWidget.floating(),
      ],
    );
  }
}
