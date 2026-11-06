import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/di/app_di.dart';
import '../../../data/services/cashu_service.dart';
import '../../../data/services/nwc_service.dart';
import '../../../data/services/spark_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../presentation/blocs/wallet/wallet_bloc.dart';
import '../../../presentation/blocs/wallet/wallet_event.dart';
import '../../../presentation/blocs/wallet/wallet_state.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../widgets/common/top_action_bar_widget.dart';

class ReceivePage extends StatefulWidget {
  final String? lud16;

  const ReceivePage({super.key, this.lud16});

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return BlocProvider<WalletBloc>.value(
      value: AppDI.get<WalletBloc>(),
      child: Scaffold(
        backgroundColor: colors.background,
        body: Stack(
          children: [
            Column(
              children: [
                SizedBox(height: MediaQuery.of(context).padding.top + 90),
                _TabBar(
                  controller: _tabController,
                  lightningLabel: l10n.invoice,
                  cashuLabel: l10n.token,
                  colors: colors,
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _LightningReceiveTab(lud16: widget.lud16),
                      const _CashuRedeemTab(),
                    ],
                  ),
                ),
              ],
            ),
            const TopActionBarWidget(
              showShareButton: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final TabController controller;
  final String lightningLabel;
  final String cashuLabel;
  final dynamic colors;

  const _TabBar({
    required this.controller,
    required this.lightningLabel,
    required this.cashuLabel,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final selected = controller.index;
          return Container(
            height: 48,
            decoration: BoxDecoration(
              color: colors.overlayLight,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Row(
              children: [
                _buildPill(context, label: lightningLabel, index: 0, selected: selected == 0),
                _buildPill(context, label: cashuLabel, index: 1, selected: selected == 1),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPill(
    BuildContext context, {
    required String label,
    required int index,
    required bool selected,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () => controller.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: selected ? colors.textPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(36),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? colors.background : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _LightningReceiveTab extends StatefulWidget {
  final String? lud16;

  const _LightningReceiveTab({this.lud16});

  @override
  State<_LightningReceiveTab> createState() => _LightningReceiveTabState();
}

class _LightningReceiveTabState extends State<_LightningReceiveTab> {
  final TextEditingController _amountController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isUpdating = false;
  String? _invoice;
  String? _error;
  bool _hasAmount = false;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    if (_invoice != null) {
      AppDI.get<WalletBloc>().add(const WalletInvoiceCleared());
    }
    _amountController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final text = _amountController.text.trim();
    final newHasAmount = text.isNotEmpty;
    if (newHasAmount != _hasAmount) {
      setState(() => _hasAmount = newHasAmount);
    }
    if (text.isEmpty && (_invoice != null || _error != null)) {
      final hadInvoice = _invoice != null;
      setState(() {
        _invoice = null;
        _error = null;
      });
      if (hadInvoice) {
        AppDI.get<WalletBloc>().add(const WalletInvoiceCleared());
      }
    }
  }

  bool get _isNwcMode => AppDI.get<NwcService>().isActive;

  Future<void> _updateQr() async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      setState(() {
        _invoice = null;
        _error = null;
      });
      return;
    }

    final amountValue = int.tryParse(amountText);
    if (amountValue == null || amountValue <= 0) {
      setState(() {
        _invoice = null;
        _error = null;
      });
      return;
    }

    setState(() {
      _isUpdating = true;
      _error = null;
    });

    final l10n = AppLocalizations.of(context)!;

    try {
      String? newInvoice;

      if (_isNwcMode) {
        final nwcService = AppDI.get<NwcService>();
        final result = await nwcService.makeInvoice(amountSats: amountValue);
        if (mounted) {
          result.fold(
            (invoice) => newInvoice = invoice,
            (err) {
              setState(() {
                _isUpdating = false;
                _error = l10n.failedToCreateInvoice(err.toString());
                _invoice = null;
              });
            },
          );
        }
      } else {
        final sparkResult = await AppDI.get<SparkService>()
            .createLightningInvoice(amountSats: amountValue);
        if (mounted) {
          sparkResult.fold(
            (invoice) => newInvoice = invoice,
            (err) {
              setState(() {
                _isUpdating = false;
                _error = l10n.failedToCreateInvoice(err.toString());
                _invoice = null;
              });
            },
          );
        }
      }

      if (newInvoice != null && mounted) {
        setState(() {
          _isUpdating = false;
          _invoice = newInvoice;
        });
        AppDI.get<WalletBloc>().add(WalletInvoiceWatched(newInvoice!));
      } else if (mounted) {
        setState(() => _isUpdating = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUpdating = false;
          _error = '${l10n.error}: $e';
          _invoice = null;
        });
      }
    }
  }

  String get _qrData {
    if (_invoice != null) return _invoice!;
    if (widget.lud16 != null && widget.lud16!.isNotEmpty && !_hasAmount) {
      return widget.lud16!;
    }
    return '';
  }

  bool get _hasLightningAddress =>
      widget.lud16 != null && widget.lud16!.isNotEmpty;

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    AppSnackbar.success(
        context, AppLocalizations.of(context)!.copiedToClipboard);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return BlocListener<WalletBloc, WalletState>(
      listenWhen: (prev, curr) {
        if (curr is WalletLoaded && prev is WalletLoaded) {
          return curr.invoiceReceived && !prev.invoiceReceived;
        }
        return false;
      },
      listener: (context, state) {
        if (state is WalletLoaded && state.invoiceReceived) {
          AppSnackbar.success(context, l10n.paymentReceived);
          final nav = Navigator.of(context);
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) nav.pop();
          });
        }
      },
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: _buildQrSection(context, colors, l10n),
          ),
          SliverToBoxAdapter(
            child: _buildAddressOrInvoiceChip(context, colors, l10n),
          ),
          SliverToBoxAdapter(
            child: _buildAmountSection(context, colors, l10n),
          ),
          if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(
                  _error!,
                  style: TextStyle(color: colors.error, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ],
      ),
    );
  }

  Widget _buildQrSection(
      BuildContext context, dynamic colors, AppLocalizations l10n) {
    final screenWidth = MediaQuery.of(context).size.width;
    final qrSize = screenWidth - 80;
    final qrData = _qrData;

    return Center(
      child: GestureDetector(
        onTap: qrData.isNotEmpty ? () => _copyToClipboard(qrData) : null,
        child: SizedBox(
          width: qrSize,
          height: qrSize,
          child: _buildQrContent(qrData, qrSize, colors, l10n),
        ),
      ),
    );
  }

  Widget _buildQrContent(
      String qrData, double qrSize, dynamic colors, AppLocalizations l10n) {
    if (_isUpdating) {
      return Center(
        child: CircularProgressIndicator(
          color: colors.textPrimary,
          strokeWidth: 2,
        ),
      );
    }

    if (qrData.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(
              PhosphorIcons.qrCode(),
              size: 80,
              color: colors.textSecondary.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.enterAmountToGenerateInvoice,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return QrImageView(
      data: qrData,
      version: QrVersions.auto,
      size: qrSize,
      backgroundColor: colors.background,
      eyeStyle: QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: colors.textPrimary,
      ),
      dataModuleStyle: QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: colors.textPrimary,
      ),
    );
  }

  Widget _buildAddressOrInvoiceChip(
      BuildContext context, dynamic colors, AppLocalizations l10n) {
    final qrData = _qrData;
    if (qrData.isEmpty) return const SizedBox(height: 16);

    String displayText;
    if (_invoice != null) {
      displayText = _invoice!.length > 24
          ? '${_invoice!.substring(0, 12)}...${_invoice!.substring(_invoice!.length - 8)}'
          : _invoice!;
    } else if (_hasLightningAddress) {
      displayText = widget.lud16!;
    } else {
      return const SizedBox(height: 16);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GestureDetector(
        onTap: () => _copyToClipboard(qrData),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colors.overlayLight,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  displayText,
                  style: TextStyle(
                    fontFamily: _invoice != null ? 'monospace' : null,
                    fontSize: 16,
                    color: colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              PhosphorIcon(PhosphorIcons.copy(),
                  size: 20, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmountSection(
      BuildContext context, dynamic colors, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.amount,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: colors.overlayLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      FocusScope.of(context).unfocus();
                      _updateQr();
                    },
                    enabled: !_isUpdating,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: l10n.amountInSats,
                      hintStyle: TextStyle(
                        color: colors.textSecondary.withValues(alpha: 0.4),
                        fontSize: 16,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(right: _hasAmount ? 12 : 16),
                  child: Text(
                    'sats',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (_hasAmount)
                  GestureDetector(
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      _updateQr();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: colors.textPrimary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        l10n.confirm,
                        style: TextStyle(
                          color: colors.background,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CashuRedeemTab extends StatefulWidget {
  const _CashuRedeemTab();

  @override
  State<_CashuRedeemTab> createState() => _CashuRedeemTabState();
}

class _CashuRedeemTabState extends State<_CashuRedeemTab> {
  final TextEditingController _tokenController = TextEditingController();
  final _cashuService = const CashuService();

  String? _decodedMintUrl;
  int? _decodedAmount;
  String? _decodeError;

  @override
  void initState() {
    super.initState();
    _tokenController.addListener(_onTokenChanged);
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  void _onTokenChanged() {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() {
        _decodedMintUrl = null;
        _decodedAmount = null;
        _decodeError = null;
      });
      return;
    }

    if (token.startsWith('cashuA') || token.startsWith('cashuB')) {
      final result = _cashuService.decodeToken(token);
      result.fold(
        (info) {
          setState(() {
            _decodedMintUrl = info.mintUrl;
            _decodedAmount = info.amountSats;
            _decodeError = null;
          });
        },
        (error) {
          setState(() {
            _decodedMintUrl = null;
            _decodedAmount = null;
            _decodeError = error;
          });
        },
      );
    } else {
      setState(() {
        _decodedMintUrl = null;
        _decodedAmount = null;
        _decodeError = null;
      });
    }
  }

  void _redeem(BuildContext context, WalletLoaded walletState) {
    final l10n = AppLocalizations.of(context)!;
    final lud16 = walletState.lightningAddress;
    if (lud16 == null || lud16.isEmpty) {
      AppSnackbar.error(context, l10n.cashuNoLightningAddress);
      return;
    }

    final token = _tokenController.text.trim();
    if (token.isNotEmpty) {
      AppDI.get<WalletBloc>().add(WalletCashuTokenRedeemRequested(
        token: token,
        lightningTarget: lud16,
      ));
    } else {
      AppDI.get<WalletBloc>().add(WalletCashuMeltAllRequested(lud16));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return BlocConsumer<WalletBloc, WalletState>(
      listenWhen: (prev, curr) {
        if (curr is WalletLoaded && prev is WalletLoaded) {
          final prevAmount = prev.cashuRedeemedAmountSats;
          final currAmount = curr.cashuRedeemedAmountSats;
          return currAmount != null && currAmount != prevAmount;
        }
        return false;
      },
      listener: (context, state) {
        if (state is WalletLoaded && state.cashuRedeemedAmountSats != null) {
          AppSnackbar.success(
            context,
            l10n.cashuRedeemSuccess(state.cashuRedeemedAmountSats!),
          );
          _tokenController.clear();
          final nav = Navigator.of(context);
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) nav.pop();
          });
        }
      },
      builder: (context, state) {
        final walletLoaded = state is WalletLoaded ? state : null;
        final isRedeeming = walletLoaded?.isRedeemingCashu ?? false;
        final redeemError = walletLoaded?.cashuRedeemError;
        final cashuBalance = walletLoaded?.cashuBalanceSats ?? 0;
        final hasToken = _tokenController.text.trim().isNotEmpty;
        final canAct = !isRedeeming &&
            walletLoaded != null &&
            (hasToken || cashuBalance > 0);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 60),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: colors.overlayLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextField(
                  controller: _tokenController,
                  maxLines: 4,
                  minLines: 3,
                  enabled: !isRedeeming,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: l10n.cashuTokenHint,
                    hintStyle: TextStyle(
                      color: colors.textSecondary.withValues(alpha: 0.4),
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
              if (_decodedMintUrl != null) ...[
                const SizedBox(height: 12),
                _InfoCard(
                  mintUrl: _decodedMintUrl!,
                  amountSats: _decodedAmount ?? 0,
                  colors: colors,
                  l10n: l10n,
                ),
              ],
              if (_decodeError != null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.cashuInvalidToken,
                  style: TextStyle(color: colors.error, fontSize: 13),
                ),
              ],
              if (cashuBalance > 0 && !hasToken) ...[
                const SizedBox(height: 16),
                Text(
                  '$cashuBalance sats ${l10n.cashu}',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
              if (redeemError != null) ...[
                const SizedBox(height: 8),
                Text(
                  redeemError,
                  style: TextStyle(color: colors.error, fontSize: 13),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: canAct
                      // ignore: unnecessary_non_null_assertion
                      ? () => _redeem(context, walletLoaded!)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: canAct
                          ? colors.textPrimary
                          : colors.textSecondary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: isRedeeming
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: colors.background,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              l10n.cashuRedeem,
                              style: TextStyle(
                                color: canAct
                                    ? colors.background
                                    : colors.textSecondary
                                        .withValues(alpha: 0.5),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
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

class _InfoCard extends StatelessWidget {
  final String mintUrl;
  final int amountSats;
  final dynamic colors;
  final AppLocalizations l10n;

  const _InfoCard({
    required this.mintUrl,
    required this.amountSats,
    required this.colors,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.overlayLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PhosphorIcon(PhosphorIcons.bank(), size: 16, color: colors.textSecondary),
              const SizedBox(width: 6),
              Text(
                l10n.cashuMintUrl,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            mintUrl,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (amountSats > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                PhosphorIcon(PhosphorIcons.lightning(), size: 16, color: colors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  '$amountSats sats',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
