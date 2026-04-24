import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/di/app_di.dart';
import '../../../data/services/spark_service.dart';
import '../../../presentation/blocs/wallet/wallet_bloc.dart';
import '../../../presentation/blocs/wallet/wallet_event.dart';
import '../../../presentation/blocs/wallet/wallet_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/snackbar_widget.dart';
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

  static const String _backupDismissedKey = 'spark_backup_dismissed';

  final TextEditingController _lnUsernameController = TextEditingController();
  Timer? _availabilityDebounce;
  bool? _isUsernameAvailable;
  bool _isCheckingUsername = false;
  bool _isRegisteringAddress = false;
  bool _isConnecting = false;
  bool _showAllTransactions = false;
  bool _showBackupBanner = false;

  static const int _initialTransactionCount = 5;

  @override
  void initState() {
    super.initState();
    _loadBackupBannerState();
  }

  Future<void> _loadBackupBannerState() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_backupDismissedKey) ?? false;
    if (mounted && !dismissed) {
      setState(() => _showBackupBanner = true);
    }
  }

  Future<void> _dismissBackupBanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_backupDismissedKey, true);
    if (mounted) setState(() => _showBackupBanner = false);
  }

  @override
  void dispose() {
    _lnUsernameController.dispose();
    _availabilityDebounce?.cancel();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    _availabilityDebounce?.cancel();
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) {
      setState(() {
        _isUsernameAvailable = null;
        _isCheckingUsername = false;
      });
      return;
    }
    setState(() {
      _isCheckingUsername = true;
      _isUsernameAvailable = null;
    });
    _availabilityDebounce = Timer(const Duration(milliseconds: 600), () async {
      final result =
          await AppDI.get<SparkService>().checkLightningAddressAvailable(trimmed);
      if (!mounted) return;
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = result.isSuccess ? result.data : null;
      });
    });
  }

  Future<void> _registerAddress(
      BuildContext context, AppLocalizations l10n) async {
    final username = _lnUsernameController.text.trim().toLowerCase();
    if (username.isEmpty || _isUsernameAvailable != true) return;
    setState(() => _isRegisteringAddress = true);
    context.read<WalletBloc>().add(WalletLightningAddressRegistered(username));
  }

  int _getBalanceSats(WalletLoaded state) => state.balanceSats ?? 0;

  String _formatSats(num value) {
    final str = value.abs().toStringAsFixed(0);
    final buffer = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  String _formatTimestamp(int? timestamp) {
    if (timestamp == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    return '${dt.day}/${dt.month}/${dt.year}';
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
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
      ),
    );
  }

  Widget _buildTransactionsSliver(BuildContext context, WalletLoaded state) {
    if (state.isLoadingTransactions) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Center(
            child: CircularProgressIndicator(color: context.colors.textPrimary),
          ),
        ),
      );
    }

    final all = state.transactions;
    if (all == null || all.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Center(
            child: Text(
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

    final shown = _showAllTransactions
        ? all
        : all.take(_initialTransactionCount).toList();
    final hasMore = all.length > _initialTransactionCount;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 200),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          ...shown.asMap().entries.map((entry) {
            final isLast = entry.key == shown.length - 1;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
              child: _buildTransactionTile(context, entry.value),
            );
          }),
          if (hasMore) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(
                  () => _showAllTransactions = !_showAllTransactions),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.colors.overlayLight,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _showAllTransactions
                          ? AppLocalizations.of(context)!.showLess
                          : AppLocalizations.of(context)!
                              .showAllTransactions(all.length),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: context.colors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _showAllTransactions
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: context.colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildTransactionTile(
    BuildContext context,
    Map<String, dynamic> tx,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final isIncoming = tx['isIncoming'] as bool? ?? false;
    final amount = tx['amount'] as num? ?? 0;
    final timestamp = tx['timestamp'] as int?;
    final status = tx['status'] as String?;
    final isPending = status == 'pending';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.overlayLight,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isIncoming
                  ? context.colors.success.withValues(alpha: 0.12)
                  : context.colors.textSecondary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
              color: isIncoming
                  ? context.colors.success
                  : context.colors.textPrimary,
              size: 17,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isIncoming ? l10n.received : l10n.sent,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                ),
                if (timestamp != null || isPending) ...[
                  const SizedBox(height: 2),
                  Text(
                    isPending ? 'Pending' : _formatTimestamp(timestamp),
                    style: TextStyle(
                      fontSize: 12,
                      color: isPending
                          ? context.colors.accent
                          : context.colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '${isIncoming ? '+' : '-'}${_formatSats(amount)} sats',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isIncoming
                  ? context.colors.success
                  : context.colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            l10n.onboardingCoinosSubtitle,
            style: TextStyle(
              fontSize: 15,
              color: context.colors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _buildFeatureItem(context, Icons.bolt, l10n.onboardingCoinosFeatureSend),
          const SizedBox(height: 24),
          _buildFeatureItem(
              context, Icons.call_received, l10n.onboardingCoinosFeatureReceive),
          const SizedBox(height: 24),
          _buildFeatureItem(
              context, Icons.favorite, l10n.onboardingCoinosFeatureZap),
          const SizedBox(height: 24),
          Text(
            l10n.onboardingCoinosDisclaimer,
            style: TextStyle(
              fontSize: 13,
              color: context.colors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(
      BuildContext context, IconData icon, String description) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: context.colors.overlayLight,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: context.colors.textPrimary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            description,
            style: TextStyle(
              fontSize: 16,
              color: context.colors.textPrimary,
              height: 1.4,
            ),
          ),
        ),
      ],
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
            child: !state.isConnected
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
      onTap: _isConnecting
          ? null
          : () {
              setState(() => _isConnecting = true);
              context.read<WalletBloc>().add(const WalletInitialized());
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _isConnecting
              ? context.colors.textPrimary.withValues(alpha: 0.6)
              : context.colors.textPrimary,
          borderRadius: BorderRadius.circular(40),
        ),
        child: _isConnecting
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.colors.background,
                ),
              )
            : Text(
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
                borderRadius: BorderRadius.circular(40),
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
                borderRadius: BorderRadius.circular(40),
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

  Widget _buildLightningAddressSection(
      BuildContext context, WalletLoaded state) {
    if (state.isNwcMode) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final address = state.lightningAddress;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: address != null && address.isNotEmpty
          ? _buildLightningAddressChip(context, address, l10n)
          : _buildLightningAddressRegister(context, l10n),
    );
  }

  Widget _buildLightningAddressChip(
      BuildContext context, String address, AppLocalizations l10n) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: address));
        AppSnackbar.success(context, l10n.lightningAddressCopied);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: [
            Icon(Icons.bolt, size: 18, color: context.colors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                address,
                style: TextStyle(
                  fontSize: 14,
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.copy, size: 16, color: context.colors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildLightningAddressRegister(
      BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.overlayLight,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 8),
              Text(
                l10n.lightningAddressSetup,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: context.colors.background,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: _lnUsernameController,
                    onChanged: _onUsernameChanged,
                    enabled: !_isRegisteringAddress,
                    style: TextStyle(
                      fontSize: 14,
                      color: context.colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: l10n.lightningAddressHint,
                      hintStyle: TextStyle(
                        color: context.colors.textSecondary
                            .withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      suffixText: '@...',
                      suffixStyle: TextStyle(
                        fontSize: 13,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildRegisterButton(context, l10n),
            ],
          ),
          if (_isCheckingUsername) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.lightningAddressChecking,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ] else if (_isUsernameAvailable != null &&
              _lnUsernameController.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _isUsernameAvailable!
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
                  size: 14,
                  color: _isUsernameAvailable!
                      ? context.colors.success
                      : context.colors.error,
                ),
                const SizedBox(width: 6),
                Text(
                  _isUsernameAvailable!
                      ? l10n.lightningAddressAvailable
                      : l10n.lightningAddressTaken,
                  style: TextStyle(
                    fontSize: 12,
                    color: _isUsernameAvailable!
                        ? context.colors.success
                        : context.colors.error,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRegisterButton(BuildContext context, AppLocalizations l10n) {
    final canRegister = _isUsernameAvailable == true &&
        _lnUsernameController.text.trim().isNotEmpty &&
        !_isRegisteringAddress;

    return GestureDetector(
      onTap: canRegister ? () => _registerAddress(context, l10n) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: canRegister
              ? context.colors.textPrimary
              : context.colors.textPrimary.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
        ),
        child: _isRegisteringAddress
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.colors.background,
                ),
              )
            : Text(
                l10n.lightningAddressRegister,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.colors.background,
                ),
              ),
      ),
    );
  }

  Widget _buildBackupBanner(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: context.colors.overlayLight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.sparkBackupTitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.sparkBackupSubtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      _dismissBackupBanner();
                      context.push('/payments');
                    },
                    child: Text(
                      l10n.sparkBackupReveal,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _dismissBackupBanner,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReceiveDialog(BuildContext context, WalletLoaded state) {
    final lud16 = state.lightningAddress;
    final path = lud16 != null && lud16.isNotEmpty
        ? '/home/wallet/receive?lud16=${Uri.encodeComponent(lud16)}'
        : '/home/wallet/receive';
    context.push(path);
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
      child: BlocListener<WalletBloc, WalletState>(
        listener: (context, state) {
          if (state is WalletError) {
            if (_isConnecting) setState(() => _isConnecting = false);
            if (_isRegisteringAddress) {
              setState(() => _isRegisteringAddress = false);
            }
            AppSnackbar.error(context, state.message);
          }
          if (state is WalletLoaded) {
            if (_isConnecting) setState(() => _isConnecting = false);
            if (_isRegisteringAddress) {
              setState(() {
                _isRegisteringAddress = false;
                _lnUsernameController.clear();
                _isUsernameAvailable = null;
              });
              AppSnackbar.success(
                  context,
                  AppLocalizations.of(context)!.lightningAddressRegistered);
            }
          }
        },
        child: BlocBuilder<WalletBloc, WalletState>(
          builder: (context, state) {
            if (state is WalletLoading) {
              return Scaffold(
                backgroundColor: context.colors.background,
                body: Center(
                  child: CircularProgressIndicator(
                      color: context.colors.textPrimary),
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
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.wifi_off_rounded,
                                    size: 48,
                                    color: context.colors.textSecondary
                                        .withValues(alpha: 0.4),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    state.message,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: context.colors.textSecondary,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
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
                            color: context.colors.surface
                                .withValues(alpha: 0.8),
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
                  child: CircularProgressIndicator(
                      color: context.colors.textPrimary),
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
                      if (!state.isConnected) ...[
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(context),
                        ),
                      ] else ...[
                        SliverToBoxAdapter(
                          child: _buildBalanceSection(context, state),
                        ),
                        if (_showBackupBanner)
                          SliverToBoxAdapter(
                            child: _buildBackupBanner(context),
                          ),
                        SliverToBoxAdapter(
                          child: _buildLightningAddressSection(context, state),
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
      ),
    );
  }
}
