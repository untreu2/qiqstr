import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import '../widgets/back_button_widget.dart';
import '../core/di/app_di.dart';
import '../data/repositories/wallet_repository.dart';

class NwcSettingsPage extends StatefulWidget {
  const NwcSettingsPage({super.key});

  @override
  State<NwcSettingsPage> createState() => _NwcSettingsPageState();
}

class _NwcSettingsPageState extends State<NwcSettingsPage> {
  final TextEditingController _nwcController = TextEditingController();
  final _walletRepository = AppDI.get<WalletRepository>();
  bool _isConnecting = false;
  bool _isDisconnecting = false;
  String? _currentConnection;

  @override
  void initState() {
    super.initState();
    _loadCurrentConnection();
  }

  @override
  void dispose() {
    _nwcController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentConnection() async {
    final result = await _walletRepository.autoConnect();
    result.fold(
      (connection) {
        if (connection != null && mounted) {
          setState(() {
            _currentConnection = connection.walletPubKey;
          });
        }
      },
      (error) {},
    );
  }

  Future<void> _updateConnection() async {
    if (_nwcController.text.trim().isEmpty) {
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    final result = await _walletRepository.connectWallet(_nwcController.text.trim());

    result.fold(
      (connection) {
        if (mounted) {
          setState(() {
            _isConnecting = false;
            _currentConnection = connection.walletPubKey;
            _nwcController.clear();
          });
          Navigator.pop(context, true);
        }
      },
      (error) {
        if (mounted) {
          setState(() {
            _isConnecting = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update connection: $error')),
          );
        }
      },
    );
  }

  Future<void> _disconnectWallet() async {
    setState(() {
      _isDisconnecting = true;
    });

    await _walletRepository.disconnect();

    if (mounted) {
      setState(() {
        _isDisconnecting = false;
        _currentConnection = null;
      });
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: 16),
                _buildContent(context),
              ],
            ),
          ),
          const BackButtonWidget.floating(),
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
            'Wallet Settings',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Manage your Nostr Wallet Connect settings.',
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

  Widget _buildContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_currentConnection != null) ...[
            Text(
              'Current Connection',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.colors.overlayLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _currentConnection!.substring(0, 16) + '...',
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          Text(
            'Update NWC URI',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nwcController,
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'nostr+walletconnect://...',
              hintStyle: TextStyle(color: context.colors.textSecondary),
              filled: true,
              fillColor: context.colors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _isConnecting ? null : _updateConnection,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.buttonPrimary,
                borderRadius: BorderRadius.circular(40),
              ),
              child: _isConnecting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(context.colors.background),
                      ),
                    )
                  : Text(
                      'Update Connection',
                      style: TextStyle(
                        color: context.colors.buttonText,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          if (_currentConnection != null) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _isDisconnecting ? null : _disconnectWallet,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.colors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(40),
                ),
                child: _isDisconnecting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(context.colors.error),
                        ),
                      )
                    : Text(
                        'Disconnect Wallet',
                        style: TextStyle(
                          color: context.colors.error,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

