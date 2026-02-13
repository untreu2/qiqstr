import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/di/app_di.dart';
import '../../../presentation/blocs/wallet/wallet_bloc.dart';
import '../../../presentation/blocs/wallet/wallet_event.dart';
import '../../../presentation/blocs/wallet/wallet_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/dialogs/receive_dialog.dart';
import '../../widgets/dialogs/send_dialog.dart';
import '../../widgets/wallet/recaptcha_widget.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _getBalanceSats(WalletLoaded state) {
    final balance = state.balance;
    if (balance == null) return 0;
    return (balance['balance'] as num?)?.toInt() ?? 0;
  }

  String _formatSats(num value) {
    final str = value.abs().toStringAsFixed(0);
    final buffer = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  String _formatUsd(double value) {
    if (value < 0.01) return '\$${value.toStringAsFixed(4)}';
    if (value < 1) return '\$${value.toStringAsFixed(2)}';
    final whole = value.truncate();
    final decimal = (value % 1).toStringAsFixed(2).substring(2);
    return '\$${_formatSats(whole)}.$decimal';
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
      child: Text(
        l10n.wallet,
        style: GoogleFonts.poppins(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: context.colors.textPrimary,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _buildBalanceSection(BuildContext context, WalletLoaded state) {
    final sats = _getBalanceSats(state);
    final btcPrice = state.btcPriceUsd;
    final balanceUsd =
        btcPrice != null ? sats * (btcPrice / 100000000) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    _formatSats(sats),
                    style: GoogleFonts.poppins(
                      fontSize: sats > 9999999 ? 36 : 48,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                      height: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'sats',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
            if (balanceUsd != null) ...[
              const SizedBox(height: 4),
              Text(
                _formatUsd(balanceUsd),
                style: TextStyle(
                  fontSize: 16,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPriceRow(BuildContext context, WalletLoaded state) {
    final btcPrice = state.btcPriceUsd;
    if (btcPrice == null) return const SizedBox.shrink();

    final satPrice = btcPrice / 100000000;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '1 BTC = ${_formatUsd(btcPrice)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            Text(
              '1 sat = \$${satPrice.toStringAsFixed(4)}',
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsSliver(BuildContext context, WalletLoaded state) {
    if (state.isLoadingTransactions) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Center(
            child:
                CircularProgressIndicator(color: context.colors.textPrimary),
          ),
        ),
      );
    }

    if (state.transactions == null || state.transactions!.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Center(
            child:               Text(
              AppLocalizations.of(context)!.noTransactionsYet,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
    }

    final txs = state.transactions!.take(10).toList();

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 200),
      sliver: SliverList.separated(
        itemCount: txs.length,
        itemBuilder: (context, index) =>
            _buildTransactionTile(context, txs[index], state.btcPriceUsd),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
      ),
    );
  }

  Widget _buildTransactionTile(
    BuildContext context,
    Map<String, dynamic> tx,
    double? btcPrice,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final isIncoming = tx['isIncoming'] as bool? ?? false;
    final amount = tx['amount'] as num? ?? 0;
    final txUsd = btcPrice != null
        ? amount.abs() * (btcPrice / 100000000)
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.overlayLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
            color: context.colors.textPrimary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isIncoming ? l10n.received : l10n.sent,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          if (txUsd != null) ...[
            Text(
              _formatUsd(txUsd),
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            '${isIncoming ? '+' : '-'}${_formatSats(amount)} sats',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 64,
              color: context.colors.textSecondary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.connectYourWallet,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.connectWalletDescription,
              style: TextStyle(
                fontSize: 15,
                color: context.colors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, WalletLoaded state) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            color: context.colors.surface.withValues(alpha: 0.8),
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(context).padding.bottom + 12,
            ),
            child: state.user == null
                ? _buildConnectButton(context)
                : _buildActionButtons(context, state),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectButton(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () async {
        final token = await resolveRecaptcha(context);
        if (!context.mounted) return;
        context
            .read<WalletBloc>()
            .add(WalletAutoConnectRequested(recaptchaToken: token));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.textPrimary,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          l10n.connectWallet,
          style: TextStyle(
            color: context.colors.background,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, WalletLoaded state) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _showReceiveDialog(context, state),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.textPrimary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_downward,
                      size: 18, color: context.colors.background),
                  const SizedBox(width: 8),
                  Text(
                    l10n.receive,
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
            onTap: () => _showSendDialog(context, state),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.textPrimary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_upward,
                      size: 18, color: context.colors.background),
                  const SizedBox(width: 8),
                  Text(
                    l10n.send,
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
    );
  }

  void _showReceiveDialog(BuildContext context, WalletLoaded state) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final username = state.user?['username'] as String? ?? '';
        final lud16 = username.isNotEmpty ? '$username@coinos.io' : '';
        return ReceiveDialog(lud16: lud16);
      },
    );
  }

  void _showSendDialog(BuildContext context, WalletLoaded state) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SendDialog(
        onPaymentSuccess: () {
          context.read<WalletBloc>().add(const WalletBalanceRequested());
        },
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
          if (state is WalletLoading) {
            return Scaffold(
              backgroundColor: context.colors.background,
              body: Center(
                child:
                    CircularProgressIndicator(color: context.colors.textPrimary),
              ),
            );
          }

          if (state is WalletError) {
            return Scaffold(
              backgroundColor: context.colors.background,
              body: Stack(
                children: [
                  CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _buildHeader(context)),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: context.colors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              state.message,
                              style: TextStyle(
                                color: context.colors.error,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                        child: Container(
                          color: context.colors.surface.withValues(alpha: 0.8),
                          padding: EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 12,
                            bottom:
                                MediaQuery.of(context).padding.bottom + 12,
                          ),
                          child: _buildConnectButton(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          if (state is! WalletLoaded) {
            return Scaffold(
              backgroundColor: context.colors.background,
              body: Center(
                child:
                    CircularProgressIndicator(color: context.colors.textPrimary),
              ),
            );
          }

          return Scaffold(
            backgroundColor: context.colors.background,
            body: Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader(context)),
                    if (state.user == null) ...[
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(context),
                      ),
                    ] else ...[
                      SliverToBoxAdapter(
                        child: _buildBalanceSection(context, state),
                      ),
                      SliverToBoxAdapter(
                        child: _buildPriceRow(context, state),
                      ),
                      if (state.transactions != null &&
                          state.transactions!.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 24, 16, 12),
                            child: Text(
                              AppLocalizations.of(context)!.recentTransactions,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      _buildTransactionsSliver(context, state),
                    ],
                  ],
                ),
                _buildBottomBar(context, state),
              ],
            ),
          );
        },
      ),
    );
  }
}
