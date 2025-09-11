import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:bounce/bounce.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/theme_manager.dart';
import '../providers/wallet_provider.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  final TextEditingController _invoiceController = TextEditingController();
  bool _isLoading = false;
  bool _showApiKeyInput = false;
  Timer? _balanceTimer;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
    _startBalanceTimer();
  }

  @override
  void dispose() {
    _balanceTimer?.cancel();
    _apiKeyController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    _invoiceController.dispose();
    super.dispose();
  }

  void _startBalanceTimer() {
    _balanceTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!_showApiKeyInput && !_isLoading) {
        final walletProvider = Provider.of<WalletProvider>(context, listen: false);
        await walletProvider.fetchBalance();
      }
    });
  }

  Future<void> _checkLoginStatus() async {
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final isLoggedIn = await walletProvider.isLoggedIn();
    setState(() {
      _showApiKeyInput = !isLoggedIn;
    });
  }

  Future<void> _saveApiKey() async {
    if (_apiKeyController.text.trim().isEmpty) {
      _showSnackBar('Please enter an API key');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final walletProvider = Provider.of<WalletProvider>(context, listen: false);
      await walletProvider.saveApiKey(_apiKeyController.text.trim());

      setState(() {
        _showApiKeyInput = false;
        _isLoading = false;
      });

      _showSnackBar('API key saved successfully!');
      _apiKeyController.clear();
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Failed to save API key');
    }
  }

  Future<void> _refreshBalance() async {
    _showSnackBar('Refreshing balance...');
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    await walletProvider.fetchBalance();
    _showSnackBar('Balance updated!');
  }

  Future<void> _createInvoice() async {
    if (_amountController.text.trim().isEmpty) {
      _showSnackBar('Please enter an amount');
      return;
    }

    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      _showSnackBar('Please enter a valid amount');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final walletProvider = Provider.of<WalletProvider>(context, listen: false);
      await walletProvider.createInvoice(amount, _memoController.text.trim());

      // Automatically copy invoice to clipboard
      if (walletProvider.invoice != null && walletProvider.invoice!.isNotEmpty) {
        _copyToClipboard(walletProvider.invoice!, 'Invoice');
      }

      setState(() => _isLoading = false);
      _showSnackBar('Invoice created and copied to clipboard!');
      Navigator.pop(context);
      _amountController.clear();
      _memoController.clear();
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Failed to create invoice');
    }
  }

  Future<void> _sendPayment() async {
    if (_invoiceController.text.trim().isEmpty) {
      _showSnackBar('Please enter a Lightning invoice');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final walletProvider = Provider.of<WalletProvider>(context, listen: false);
      await walletProvider.payInvoice(_invoiceController.text.trim());
      setState(() => _isLoading = false);

      if (walletProvider.status?.toLowerCase().contains('success') == true) {
        _showSnackBar('Payment sent successfully!');
        Navigator.pop(context);
        _invoiceController.clear();
        await _refreshBalance();
      } else {
        _showSnackBar('Payment failed');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Failed to send payment');
    }
  }

  Future<void> _logout() async {
    setState(() => _isLoading = true);

    try {
      final walletProvider = Provider.of<WalletProvider>(context, listen: false);
      await walletProvider.clearApiKey();
      setState(() {
        _showApiKeyInput = true;
        _isLoading = false;
      });
      _showSnackBar('Logged out successfully!');
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Failed to logout');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnackBar('$label copied to clipboard!');
  }

  Future<void> _openBlinkDashboard() async {
    final url = Uri.parse('https://dashboard.blink.sv/api/auth/signin');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        _showSnackBar('Could not open Blink dashboard');
      }
    } catch (e) {
      _showSnackBar('Could not open Blink dashboard');
    }
  }

  void _showSendDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.background,
        title: Text('Send Payment', style: TextStyle(color: context.colors.textPrimary)),
        content: TextField(
          controller: _invoiceController,
          style: TextStyle(color: context.colors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Lightning Invoice',
            labelStyle: TextStyle(color: context.colors.textSecondary),
            filled: true,
            fillColor: context.colors.inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(25),
              borderSide: BorderSide.none,
            ),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: context.colors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _sendPayment();
            },
            child: Text('Send', style: TextStyle(color: context.colors.buttonPrimary)),
          ),
        ],
      ),
    );
  }

  void _showReceiveDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.background,
        title: Text('Receive Payment', style: TextStyle(color: context.colors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              style: TextStyle(color: context.colors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Amount (sats)',
                labelStyle: TextStyle(color: context.colors.textSecondary),
                filled: true,
                fillColor: context.colors.inputFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _memoController,
              style: TextStyle(color: context.colors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Memo (optional)',
                labelStyle: TextStyle(color: context.colors.textSecondary),
                filled: true,
                fillColor: context.colors.inputFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: context.colors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _createInvoice();
            },
            child: Text('Create', style: TextStyle(color: context.colors.buttonPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingTopBar(BuildContext context, WalletProvider walletProvider) {
    final double topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back button
          ClipRRect(
            borderRadius: BorderRadius.circular(25.0),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.colors.backgroundTransparent,
                  border: Border.all(
                    color: context.colors.borderLight,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(25.0),
                ),
                child: Bounce(
                  scaleFactor: 0.85,
                  onTap: () => Navigator.pop(context),
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    Icons.arrow_back,
                    color: context.colors.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          // Refresh and logout buttons (only show when wallet is connected)
          if (!_showApiKeyInput)
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(25.0),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: context.colors.backgroundTransparent,
                        border: Border.all(
                          color: context.colors.borderLight,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(25.0),
                      ),
                      child: Bounce(
                        scaleFactor: 0.85,
                        onTap: _refreshBalance,
                        behavior: HitTestBehavior.opaque,
                        child: Icon(
                          Icons.refresh,
                          color: context.colors.textSecondary,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(25.0),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: context.colors.backgroundTransparent,
                        border: Border.all(
                          color: context.colors.borderLight,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(25.0),
                      ),
                      child: Bounce(
                        scaleFactor: 0.85,
                        onTap: _logout,
                        behavior: HitTestBehavior.opaque,
                        child: Icon(
                          Icons.logout,
                          color: context.colors.textSecondary,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildApiKeyInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Connect Your Blink Wallet',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _apiKeyController,
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Enter your API key...',
              labelStyle: TextStyle(color: context.colors.textSecondary),
              filled: true,
              fillColor: context.colors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _saveApiKey,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.buttonPrimary,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: context.colors.borderAccent),
              ),
              child: Text(
                'Connect',
                style: TextStyle(
                  color: context.colors.background,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _openBlinkDashboard,
            child: Text(
              'Get your API key',
              style: TextStyle(
                fontSize: 16,
                color: context.colors.buttonPrimary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletInfo(WalletProvider walletProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // Balance Display (without title)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                walletProvider.balance ?? '0',
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'sats',
                style: TextStyle(
                  fontSize: 18,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
          // Lightning Address (clickable to copy)
          if (walletProvider.lightningAddress != null && walletProvider.lightningAddress!.isNotEmpty) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _copyToClipboard(walletProvider.lightningAddress!, 'Lightning address'),
              child: Text(
                walletProvider.lightningAddress!,
                style: TextStyle(
                  fontSize: 16,
                  color: context.colors.textSecondary,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 40),
          // Send Button
          GestureDetector(
            onTap: _showSendDialog,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.buttonPrimary,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: context.colors.borderAccent),
              ),
              child: Text(
                'Send',
                style: TextStyle(
                  color: context.colors.background,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Receive Button
          GestureDetector(
            onTap: _showReceiveDialog,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.overlayLight,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: context.colors.borderAccent),
              ),
              child: Text(
                'Receive',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: context.colors.loading),
        const SizedBox(height: 20),
        Text(
          'Loading...',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 16),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WalletProvider>(
      builder: (context, walletProvider, child) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: Stack(
            children: [
              SafeArea(
                child: Center(
                  child: _isLoading
                      ? _buildLoadingScreen()
                      : SingleChildScrollView(
                          child: _showApiKeyInput ? _buildApiKeyInput() : _buildWalletInfo(walletProvider),
                        ),
                ),
              ),
              _buildFloatingTopBar(context, walletProvider),
            ],
          ),
        );
      },
    );
  }
}
