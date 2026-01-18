import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../presentation/blocs/wallet/wallet_bloc.dart';
import '../../../presentation/blocs/wallet/wallet_event.dart';
import '../../../presentation/blocs/wallet/wallet_state.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../core/di/app_di.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/dialogs/receive_dialog.dart';
import '../../widgets/dialogs/send_dialog.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

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

  Widget _buildConnectionBottomBar(BuildContext context, WalletState state) {
    final isLoading = state is WalletLoading;
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
          onTap: isLoading
              ? null
              : () {
                  context
                      .read<WalletBloc>()
                      .add(const WalletAutoConnectRequested());
                },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.colors.textPrimary,
              borderRadius: BorderRadius.circular(40),
            ),
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          context.colors.background),
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

  Widget _buildBalanceSection(BuildContext context, WalletLoaded state) {
    return Padding(
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
                () {
                  final balance = state.balance;
                  if (balance != null) {
                    final balanceValue = balance['balance'] as num?;
                    return balanceValue?.toString() ?? '0';
                  }
                  return '0';
                }(),
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
    );
  }

  Widget _buildTransactionsSliver(BuildContext context, WalletLoaded state) {
    if (state.isLoadingTransactions) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: CircularProgressIndicator(color: context.colors.textPrimary),
        ),
      );
    }

    if (state.transactions == null || state.transactions!.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long,
                  color: context.colors.textTertiary, size: 48),
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
        ),
      );
    }

    final recentTransactions = state.transactions!.take(6).toList();

    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 100),
      sliver: SliverList.separated(
        itemCount: recentTransactions.length,
        itemBuilder: (context, index) {
          final tx = recentTransactions[index];
          return _buildTransactionTile(context, tx);
        },
        separatorBuilder: (_, __) => const _TransactionSeparator(),
      ),
    );
  }

  Widget _buildTransactionTile(BuildContext context, Map<String, dynamic> tx) {
    final isIncoming = tx['isIncoming'] as bool? ?? false;
    final amount = tx['amount'] as num? ?? 0;

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
            '${isIncoming ? '+' : '-'}${amount.abs()} sats',
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

  void _showReceiveDialog(BuildContext context, WalletLoaded state) {
    final walletRepository = AppDI.get<WalletRepository>();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => ReceiveDialog(
        walletRepository: walletRepository,
        lud16: state.user?['lud16'] as String? ?? '',
      ),
    );
  }

  void _showSendDialog(BuildContext context, WalletLoaded state) {
    final walletRepository = AppDI.get<WalletRepository>();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SendDialog(
        walletRepository: walletRepository,
        onPaymentSuccess: () {
          context.read<WalletBloc>().add(const WalletBalanceRequested());
        },
      ),
    );
  }

  Widget _buildError(BuildContext context, WalletError state) {
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
                state.message,
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
  Widget build(BuildContext context) {
    super.build(context);
    return BlocProvider<WalletBloc>.value(
      value: AppDI.get<WalletBloc>(),
      child: BlocBuilder<WalletBloc, WalletState>(
        builder: (context, state) {
          if (state is! WalletLoaded) {
            return Scaffold(
              backgroundColor: context.colors.background,
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          return Scaffold(
            backgroundColor: context.colors.background,
            body: Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _buildHeader(context),
                    ),
                    if (state.user == null) ...[
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyWalletState(context),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 80),
                      ),
                    ] else ...[
                      SliverToBoxAdapter(
                        child: _buildBalanceSection(context, state),
                      ),
                      _buildTransactionsSliver(context, state),
                    ],
                    if (state is WalletError)
                      SliverToBoxAdapter(
                        child: _buildError(context, state as WalletError),
                      ),
                  ],
                ),
                if (state.user == null)
                  _buildConnectionBottomBar(context, state),
                if (state.user != null)
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
                              onTap: () {
                                _showReceiveDialog(context, state);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 20),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: context.colors.textPrimary,
                                  borderRadius: BorderRadius.circular(40),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.arrow_downward,
                                        size: 20,
                                        color: context.colors.background),
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
                              onTap: () {
                                _showSendDialog(context, state);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 20),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: context.colors.textPrimary,
                                  borderRadius: BorderRadius.circular(40),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.arrow_upward,
                                        size: 20,
                                        color: context.colors.background),
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
      ),
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
