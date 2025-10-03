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
  List<TransactionDetails>? _transactions;
  bool _isConnecting = false;
  bool _isLoadingTransactions = false;
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
          _getTransactions();
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
        _getTransactions();
        _startBalanceTimer();
        _nwcController.clear();
      },
      (error) {
        _setError(error);
      },
    );
  }

  Future<void> _getBalance() async {
    final result = await _walletRepository.getBalance();

    result.fold(
      (balance) {
        if (mounted) {
          setState(() {
            _balance = balance;
          });
        }
      },
      (error) {
        _setError('Failed to get balance: $error');
      },
    );
  }

  Future<void> _getTransactions() async {
    setState(() {
      _isLoadingTransactions = true;
    });

    final result = await _walletRepository.listTransactions();

    result.fold(
      (transactions) {
        setState(() {
          _transactions = transactions;
          _isLoadingTransactions = false;
        });
      },
      (error) {
        setState(() {
          _isLoadingTransactions = false;
        });
        debugPrint('Failed to get transactions: $error');
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
      _transactions = null;
      _error = null;
    });
  }

  void _setError(String error) {
    setState(() {
      _error = error;
      _isConnecting = false;
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

  Widget _buildMainContent(BuildContext context) {
    if (_connection == null) {
      return const SizedBox.shrink();
    }

    return Expanded(
      child: Column(
        children: [
          // Balance at top
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: Text(
              _balance != null
                  ? '${((_balance!.balance / 1000).floor()).toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} sats'
                  : 'Loading...',
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.bold,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          // Transactions in the middle
          Expanded(
            child: _buildTransactionsList(context),
          ),
          // Buttons at bottom
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _showReceiveDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: context.colors.overlayLight,
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: context.colors.borderAccent),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_downward, size: 18, color: context.colors.textPrimary),
                          const SizedBox(width: 8),
                          Text(
                            'Receive',
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _showSendDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: context.colors.overlayLight,
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: context.colors.borderAccent),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_upward, size: 18, color: context.colors.textPrimary),
                          const SizedBox(width: 8),
                          Text(
                            'Send',
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildTransactionsList(BuildContext context) {
    if (_isLoadingTransactions) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.textPrimary),
      );
    }

    if (_transactions == null || _transactions!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, color: context.colors.textTertiary, size: 48),
            const SizedBox(height: 12),
            Text(
              'No transactions yet',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _transactions!.length,
      separatorBuilder: (context, index) => Divider(
        color: context.colors.border,
        height: 1,
      ),
      itemBuilder: (context, index) {
        final tx = _transactions![index];
        return _buildTransactionTile(context, tx);
      },
    );
  }

  Widget _buildTransactionTile(BuildContext context, TransactionDetails tx) {
    final isIncoming = tx.type == 'incoming';
    final dateTime = DateTime.fromMillisecondsSinceEpoch(tx.createdAt * 1000);
    final formatted = '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        horizontalTitleGap: 12,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: context.colors.grey800,
          child: Icon(
            isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
            color: context.colors.textPrimary,
            size: 16,
          ),
        ),
        title: Text(
          tx.description.isEmpty ? (isIncoming ? 'Received' : 'Sent') : tx.description,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              formatted,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12,
              ),
            ),
            if (tx.feesPaid > 0) ...[
              const SizedBox(height: 2),
              Text(
                'Fee: ${(tx.feesPaid / 1000).floor()} sats',
                style: TextStyle(
                  color: context.colors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${isIncoming ? '+' : '-'}${(tx.amount / 1000).floor().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'sats',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNwcSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SettingsDialog(
        nwcController: _nwcController,
        onUpdate: () {
          _connectWallet();
        },
        onDisconnect: () {
          _disconnect();
        },
      ),
    );
  }

  void _showReceiveDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ReceiveDialog(
        walletRepository: _walletRepository,
      ),
    );
  }

  void _showSendDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SendDialog(
        walletRepository: _walletRepository,
        onPaymentSuccess: () {
          _getBalance();
          _getTransactions();
        },
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
                _buildMainContent(context),
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
    if (_invoice != null) {
      // Invoice display phase
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _amount != null ? 'Receive $_amount sats' : 'Lightning Invoice',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _invoice!,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 45),
          ],
        ),
      );
    }

    // Input phase
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            top: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                enabled: !_isLoading,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Amount (sats)',
                  labelStyle: TextStyle(color: context.colors.secondary),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: context.colors.secondary),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: context.colors.textPrimary),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _memoController,
                enabled: !_isLoading,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Memo (optional)',
                  labelStyle: TextStyle(color: context.colors.secondary),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: context.colors.secondary),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: context.colors.textPrimary),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        ListTile(
          leading: _isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.add_circle_outline, color: context.colors.iconPrimary),
          title: Text(
            _isLoading ? 'Creating invoice...' : 'Create Invoice',
            style: TextStyle(color: context.colors.textPrimary, fontSize: 16),
          ),
          onTap: _isLoading ? null : _createInvoice,
        ),
        const SizedBox(height: 45),
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
    if (_successMessage != null) {
      // Success phase
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              color: context.colors.textPrimary,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _successMessage!,
              style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 45),
          ],
        ),
      );
    }

    // Input phase
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            top: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _invoiceController,
                enabled: !_isLoading,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Lightning Invoice',
                  hintText: 'Paste invoice here...',
                  labelStyle: TextStyle(color: context.colors.secondary),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: context.colors.secondary),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: context.colors.textPrimary),
                  ),
                ),
                maxLines: 3,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        ListTile(
          leading: _isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.flash_on, color: context.colors.iconPrimary),
          title: Text(
            _isLoading ? 'Sending payment...' : 'Pay Invoice',
            style: TextStyle(color: context.colors.textPrimary, fontSize: 16),
          ),
          onTap: _isLoading ? null : _payInvoice,
        ),
        const SizedBox(height: 45),
      ],
    );
  }
}

class SettingsDialog extends StatefulWidget {
  final TextEditingController nwcController;
  final VoidCallback onUpdate;
  final VoidCallback onDisconnect;

  const SettingsDialog({
    super.key,
    required this.nwcController,
    required this.onUpdate,
    required this.onDisconnect,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            top: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Update NWC URI',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: widget.nwcController,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'NWC Connection',
                  hintText: 'nostr+walletconnect://...',
                  labelStyle: TextStyle(color: context.colors.secondary),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: context.colors.secondary),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: context.colors.textPrimary),
                  ),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        ListTile(
          leading: Icon(Icons.sync, color: context.colors.iconPrimary),
          title: Text(
            'Update Connection',
            style: TextStyle(color: context.colors.textPrimary, fontSize: 16),
          ),
          onTap: () {
            Navigator.pop(context);
            widget.onUpdate();
          },
        ),
        Divider(
          color: context.colors.border,
          height: 1,
        ),
        ListTile(
          leading: Icon(Icons.logout, color: Colors.red),
          title: Text(
            'Disconnect Wallet',
            style: TextStyle(color: Colors.red, fontSize: 16),
          ),
          onTap: () {
            Navigator.pop(context);
            widget.onDisconnect();
          },
        ),
        const SizedBox(height: 45),
      ],
    );
  }
}
