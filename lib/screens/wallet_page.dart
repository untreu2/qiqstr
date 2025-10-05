import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  void _setError(String error) {
    setState(() {
      _error = error;
      _isConnecting = false;
    });
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 8),
      child: Text(
        'Wallet',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: context.colors.textPrimary,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData != null && clipboardData.text != null) {
      _nwcController.text = clipboardData.text!;
      // Auto-connect after paste
      if (_nwcController.text.trim().isNotEmpty) {
        _connectWallet();
      }
    }
  }

  Widget _buildConnectionBottomBar(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.background,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        child: TextField(
          controller: _nwcController,
          style: TextStyle(color: context.colors.buttonText),
          enabled: !_isConnecting,
          decoration: InputDecoration(
            hintText: 'Paste NWC URI here...',
            hintStyle: TextStyle(color: context.colors.buttonText.withValues(alpha: 0.6)),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: _isConnecting ? null : _pasteFromClipboard,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _isConnecting ? context.colors.background.withValues(alpha: 0.5) : context.colors.background,
                    shape: BoxShape.circle,
                  ),
                  child: _isConnecting
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            color: context.colors.textPrimary,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          Icons.content_paste,
                          color: context.colors.textPrimary,
                          size: 20,
                        ),
                ),
              ),
            ),
            filled: true,
            fillColor: context.colors.buttonPrimary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(40),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          ),
          maxLines: 1,
          onSubmitted: (_) => _connectWallet(),
        ),
      ),
    );
  }

  Widget _buildEmptyWalletState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 80,
              color: context.colors.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Connect Your Wallet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Paste your NWC connection URI below to get started',
              style: TextStyle(
                fontSize: 16,
                color: context.colors.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _balance != null
                        ? ((_balance!.balance / 1000).floor()).toString()
                        : '0',
                    style: TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'sats',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w400,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 12,
            child: Center(
              child: Container(
                height: 0.5,
                decoration: BoxDecoration(
                  color: context.colors.textSecondary.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recent transactions',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
          Expanded(
            child: _buildTransactionsList(context),
          ),
          const SizedBox(height: 80),
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

    final recentTransactions = _transactions!.take(4).toList();
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: recentTransactions.length,
      itemBuilder: (context, index) {
        final tx = recentTransactions[index];
        return _buildTransactionTile(context, tx);
      },
    );
  }

  Widget _buildTransactionTile(BuildContext context, TransactionDetails tx) {
    final isIncoming = tx.type == 'incoming';
    final dateTime = DateTime.fromMillisecondsSinceEpoch(tx.createdAt * 1000);
    final formatted = '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
              color: context.colors.textPrimary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isIncoming ? 'Received' : 'Sent',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  formatted,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${isIncoming ? '+' : '-'}${(tx.amount / 1000).floor()} sats',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  void _showReceiveDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
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
        borderRadius: BorderRadius.zero,
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
          body: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  if (_connection == null) ...[
                    Expanded(child: _buildEmptyWalletState(context)),
                    const SizedBox(height: 80),
                  ] else ...[
                    _buildMainContent(context),
                  ],
                  _buildError(context),
                ],
              ),
              if (_connection == null)
                _buildConnectionBottomBar(context),
              if (_connection != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.colors.background,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 12,
                      bottom: MediaQuery.of(context).padding.bottom + 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _showReceiveDialog,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: context.colors.buttonPrimary,
                                borderRadius: BorderRadius.circular(40),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_downward, size: 20, color: context.colors.buttonText),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Receive',
                                    style: TextStyle(
                                      color: context.colors.buttonText,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
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
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: context.colors.buttonPrimary,
                                borderRadius: BorderRadius.circular(40),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_upward, size: 20, color: context.colors.buttonText),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Send',
                                    style: TextStyle(
                                      color: context.colors.buttonText,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
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
                ),
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

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 40,
        top: 16,
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
              labelStyle: TextStyle(
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
              ),
              filled: true,
              fillColor: context.colors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _memoController,
            enabled: !_isLoading,
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Memo (Optional)',
              labelStyle: TextStyle(
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
              ),
              filled: true,
              fillColor: context.colors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: context.colors.error, fontSize: 12),
            ),
          ],
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _isLoading ? null : _createInvoice,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.buttonPrimary,
                borderRadius: BorderRadius.circular(40),
              ),
              child: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(context.colors.background),
                      ),
                    )
                  : Text(
                      'Create Invoice',
                      style: TextStyle(
                        color: context.colors.buttonText,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
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

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 40,
        top: 16,
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
              labelStyle: TextStyle(
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
              ),
              hintStyle: TextStyle(color: context.colors.textSecondary),
              filled: true,
              fillColor: context.colors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            maxLines: 3,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: context.colors.error, fontSize: 12),
            ),
          ],
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _isLoading ? null : _payInvoice,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.buttonPrimary,
                borderRadius: BorderRadius.circular(40),
              ),
              child: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(context.colors.background),
                      ),
                    )
                  : Text(
                      'Pay Invoice',
                      style: TextStyle(
                        color: context.colors.buttonText,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
