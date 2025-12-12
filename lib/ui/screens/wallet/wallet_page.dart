import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/di/app_di.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../models/wallet_model.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/dialogs/receive_dialog.dart';
import '../../widgets/dialogs/send_dialog.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> with AutomaticKeepAliveClientMixin {
  final _walletRepository = AppDI.get<WalletRepository>();

  CoinosUser? _user;
  CoinosBalance? _balance;
  List<CoinosPayment>? _transactions;
  bool _isConnecting = false;
  bool _isLoadingTransactions = false;
  String? _error;
  Timer? _balanceTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _autoConnect();
  }

  Future<void> _autoConnect() async {
    final result = await _walletRepository.autoConnect();
    result.fold(
      (user) {
        if (user != null) {
          setState(() {
            _user = user;
          });
          _getBalance();
          _getTransactions();
          _startBalanceTimer();
        }
      },
      (error) {},
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

    _balanceTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_user != null && mounted) {
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

  Future<void> _connectWithNostr() async {
    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      final result = await _walletRepository.authenticateWithNostr();

      if (mounted) {
        result.fold(
          (user) {
            setState(() {
              _user = user;
              _isConnecting = false;
            });
            _getBalance();
            _getTransactions();
            _startBalanceTimer();
          },
          (error) {
            setState(() {
              _error = error;
              _isConnecting = false;
            });
          },
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to connect: $e';
          _isConnecting = false;
        });
      }
    }
  }

  String? _getCoinosLud16() {
    if (_user == null) return null;
    return _user!.lud16;
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Wallet',
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionBottomBar(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
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
        child: GestureDetector(
          onTap: _isConnecting ? null : _connectWithNostr,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.colors.textPrimary,
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
                    'Connect Wallet',
                    style: TextStyle(
                      color: context.colors.background,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
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
              'Connect using your Nostr identity to get started',
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
    if (_user == null) {
      return const SizedBox.shrink();
    }

    return Expanded(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      _balance != null ? _balance!.balance.toString() : '0',
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
              ],
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

    final recentTransactions = _transactions!.take(6).toList();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: recentTransactions.length,
      itemBuilder: (context, index) {
        final tx = recentTransactions[index];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTransactionTile(context, tx),
            if (index < recentTransactions.length - 1) const _TransactionSeparator(),
          ],
        );
      },
    );
  }

  Widget _buildTransactionTile(BuildContext context, CoinosPayment tx) {
    final isIncoming = tx.isIncoming;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            child: Text(
                  isIncoming ? 'Received' : 'Sent',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                fontSize: 17,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${isIncoming ? '+' : '-'}${tx.amount.abs()} sats',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 17,
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => ReceiveDialog(
        walletRepository: _walletRepository,
        lud16: _getCoinosLud16(),
      ),
    );
  }

  void _showSendDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
                  if (_user == null) ...[
                    Expanded(child: _buildEmptyWalletState(context)),
                    const SizedBox(height: 80),
                  ] else ...[
                    _buildMainContent(context),
                  ],
                  _buildError(context),
                ],
              ),
              if (_user == null) _buildConnectionBottomBar(context),
              if (_user != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.colors.surface,
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
                                color: context.colors.textPrimary,
                                borderRadius: BorderRadius.circular(40),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_downward, size: 20, color: context.colors.background),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Receive',
                                    style: TextStyle(
                                      color: context.colors.background,
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
                                color: context.colors.textPrimary,
                                borderRadius: BorderRadius.circular(40),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_upward, size: 20, color: context.colors.background),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Send',
                                    style: TextStyle(
                                      color: context.colors.background,
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

class _TransactionSeparator extends StatelessWidget {
  const _TransactionSeparator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Center(
        child: Container(
          height: 0.5,
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}
