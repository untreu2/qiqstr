import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/di/app_di.dart';
import '../data/repositories/wallet_repository.dart';
import '../models/wallet_model.dart';
import '../theme/theme_manager.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final TextEditingController _nwcController = TextEditingController();
  final _walletRepository = AppDI.get<WalletRepository>();

  WalletConnection? _connection;
  WalletBalance? _balance;
  bool _isConnecting = false;
  bool _isLoadingBalance = false;
  String? _error;
  Timer? _balanceTimer;

  @override
  void initState() {
    super.initState();
    _autoConnect();
  }

  Future<void> _autoConnect() async {
    final result = await _walletRepository.autoConnect();
    result.fold(
      (connection) {
        if (connection != null) {
          setState(() {
            _connection = connection;
          });
          _getBalance();
          _startBalanceTimer();
        }
      },
      (error) {
        // Ignore auto-connect errors
      },
    );
  }

  Future<void> _connectWallet() async {
    if (_nwcController.text.trim().isEmpty) {
      _setError('Please enter a valid NWC URI');
      return;
    }

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    final result = await _walletRepository.connectWallet(_nwcController.text.trim());

    result.fold(
      (connection) {
        setState(() {
          _connection = connection;
          _isConnecting = false;
        });
        _getBalance();
        _startBalanceTimer();
        _nwcController.clear();
      },
      (error) {
        _setError(error);
      },
    );
  }

  Future<void> _getBalance() async {
    setState(() {
      _isLoadingBalance = true;
    });

    final result = await _walletRepository.getBalance();

    result.fold(
      (balance) {
        setState(() {
          _balance = balance;
          _isLoadingBalance = false;
        });
      },
      (error) {
        setState(() {
          _isLoadingBalance = false;
        });
        _setError('Failed to get balance: $error');
      },
    );
  }

  void _startBalanceTimer() {
    _balanceTimer?.cancel();
    _balanceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_connection != null && mounted) {
        _getBalance();
      }
    });
  }

  void _stopBalanceTimer() {
    _balanceTimer?.cancel();
    _balanceTimer = null;
  }

  Future<void> _disconnect() async {
    _stopBalanceTimer();
    await _walletRepository.disconnect();
    setState(() {
      _connection = null;
      _balance = null;
      _error = null;
    });
  }

  void _setError(String error) {
    setState(() {
      _error = error;
      _isConnecting = false;
      _isLoadingBalance = false;
    });
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Wallet',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              if (_connection != null)
                IconButton(
                  onPressed: _showNwcSettings,
                  icon: Icon(
                    Icons.settings_outlined,
                    color: context.colors.textSecondary,
                    size: 24,
                  ),
                ),
            ],
          ),
          Text(
            _connection == null ? "Connect to your Lightning wallet using Nostr Wallet Connect." : "Your Lightning wallet is connected.",
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

  Widget _buildConnectionInput(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: TextField(
        controller: _nwcController,
        style: TextStyle(color: context.colors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Enter NWC URI (nostr+walletconnect://...)',
          hintStyle: TextStyle(color: context.colors.textTertiary),
          prefixIcon: Icon(Icons.account_balance_wallet, color: context.colors.textPrimary),
          filled: true,
          fillColor: context.colors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        maxLines: 2,
        onSubmitted: (_) => _connectWallet(),
      ),
    );
  }

  Widget _buildConnectButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isConnecting ? null : _connectWallet,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.colors.accent,
            foregroundColor: context.colors.background,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: _isConnecting
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: context.colors.background,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Connect Wallet'),
        ),
      ),
    );
  }

  Widget _buildBalance(BuildContext context) {
    if (_connection == null) {
      return const SizedBox.shrink();
    }

    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_balance != null) ...[
              Text(
                '${((_balance!.balance / 1000).floor()).toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} sats',
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 40),
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      context: context,
                      label: 'Receive',
                      icon: Icons.arrow_downward,
                      onTap: _showReceiveDialog,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildActionButton(
                      context: context,
                      label: 'Send',
                      icon: Icons.arrow_upward,
                      onTap: _showSendDialog,
                    ),
                  ),
                ],
              ),
            ] else if (_isLoadingBalance) ...[
              CircularProgressIndicator(
                color: context.colors.textSecondary,
                strokeWidth: 3,
              ),
              const SizedBox(height: 24),
              Text(
                'Loading balance...',
                style: TextStyle(
                  fontSize: 18,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showNwcSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wallet Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Update NWC URI:'),
            const SizedBox(height: 12),
            TextField(
              controller: _nwcController,
              decoration: InputDecoration(
                hintText: 'nostr+walletconnect://...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            const Text('Or disconnect current wallet:'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _disconnect();
            },
            child: Text(
              'Disconnect',
              style: TextStyle(color: Colors.red),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _connectWallet();
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.colors.textTertiary.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: context.colors.textPrimary,
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReceiveDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ReceiveDialog(
        walletRepository: _walletRepository,
      ),
    );
  }

  void _showSendDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SendDialog(
        walletRepository: _walletRepository,
        onPaymentSuccess: () => _getBalance(),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    if (_error == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _error!,
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _stopBalanceTimer();
    _nwcController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              if (_connection == null) ...[
                _buildConnectionInput(context),
                _buildConnectButton(context),
              ] else ...[
                _buildBalance(context),
              ],
              _buildError(context),
            ],
          ),
        );
      },
    );
  }
}

class ReceiveDialog extends StatefulWidget {
  final WalletRepository walletRepository;

  const ReceiveDialog({
    super.key,
    required this.walletRepository,
  });

  @override
  State<ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<ReceiveDialog> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();

  bool _isLoading = false;
  String? _invoice;
  int? _amount;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _createInvoice() async {
    final amountValue = int.tryParse(_amountController.text.trim());
    if (amountValue == null || amountValue <= 0) {
      setState(() {
        _error = 'Please enter a valid amount';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await widget.walletRepository.makeInvoice(
        amountValue * 1000, // Convert sats to millisats
        _memoController.text.trim().isEmpty ? 'Receive $amountValue sats' : _memoController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          result.fold(
            (invoiceResult) {
              _invoice = invoiceResult;
              _amount = amountValue;
            },
            (errorResult) {
              _error = 'Failed to create invoice: $errorResult';
            },
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_invoice == null ? 'Receive Payment' : 'Receive $_amount sats'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_invoice == null) ...[
            // Input phase
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              enabled: !_isLoading,
              decoration: const InputDecoration(
                labelText: 'Amount (sats)',
                hintText: 'Enter amount in sats',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _memoController,
              enabled: !_isLoading,
              decoration: const InputDecoration(
                labelText: 'Memo (optional)',
                hintText: 'Description for the invoice',
              ),
            ),
            if (_isLoading) ...[
              const SizedBox(height: 20),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Creating invoice...'),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ] else ...[
            // Invoice display phase
            const Text('Share this Lightning invoice:'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SelectableText(
                _invoice!,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: Text(_invoice == null ? 'Cancel' : 'Close'),
        ),
        if (_invoice == null)
          ElevatedButton(
            onPressed: _isLoading ? null : _createInvoice,
            child: const Text('Create Invoice'),
          ),
      ],
    );
  }
}

class SendDialog extends StatefulWidget {
  final WalletRepository walletRepository;
  final VoidCallback onPaymentSuccess;

  const SendDialog({
    super.key,
    required this.walletRepository,
    required this.onPaymentSuccess,
  });

  @override
  State<SendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends State<SendDialog> {
  final TextEditingController _invoiceController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  String? _successMessage;

  @override
  void dispose() {
    _invoiceController.dispose();
    super.dispose();
  }

  Future<void> _payInvoice() async {
    final invoice = _invoiceController.text.trim();
    if (invoice.isEmpty) {
      setState(() {
        _error = 'Please enter an invoice';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final result = await widget.walletRepository.payInvoice(invoice);

      if (mounted) {
        setState(() {
          _isLoading = false;
          result.fold(
            (paymentResult) {
              _successMessage = 'Payment sent! Preimage: ${paymentResult.preimage}';
              widget.onPaymentSuccess();
            },
            (errorResult) {
              _error = 'Payment failed: $errorResult';
            },
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send Payment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_successMessage == null) ...[
            TextField(
              controller: _invoiceController,
              enabled: !_isLoading,
              decoration: const InputDecoration(
                labelText: 'Lightning Invoice',
                hintText: 'Paste invoice here...',
              ),
              maxLines: 3,
            ),
            if (_isLoading) ...[
              const SizedBox(height: 20),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Sending payment...'),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ] else ...[
            // Success phase
            const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _successMessage!,
              style: const TextStyle(color: Colors.green),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: Text(_successMessage == null ? 'Cancel' : 'Close'),
        ),
        if (_successMessage == null)
          ElevatedButton(
            onPressed: _isLoading ? null : _payInvoice,
            child: const Text('Pay Invoice'),
          ),
      ],
    );
  }
}
