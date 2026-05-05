import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/di/app_di.dart';
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
  final TextEditingController _amountController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showTitleBubble = ValueNotifier(true);

  bool _isUpdating = false;
  String? _invoice;
  String? _error;
  bool _hasAmount = false;

  late AnimationController _receivedAnimController;
  late Animation<double> _receivedScaleAnim;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_onInputChanged);

    _receivedAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _receivedScaleAnim = CurvedAnimation(
      parent: _receivedAnimController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    final invoice = _invoice;
    if (invoice != null) {
      AppDI.get<WalletBloc>().add(const WalletInvoiceCleared());
    }
    _amountController.dispose();
    _scrollController.dispose();
    _showTitleBubble.dispose();
    _receivedAnimController.dispose();
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
                _error = AppLocalizations.of(context)!
                    .failedToCreateInvoice(err.toString());
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
                _error = AppLocalizations.of(context)!
                    .failedToCreateInvoice(err.toString());
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
          _error = '${AppLocalizations.of(context)!.error}: $e';
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

    return BlocProvider<WalletBloc>.value(
      value: AppDI.get<WalletBloc>(),
      child: _buildContent(context, l10n, colors),
    );
  }

  Widget _buildContent(
      BuildContext context, AppLocalizations l10n, dynamic colors) {
    return BlocListener<WalletBloc, WalletState>(
      listenWhen: (prev, curr) {
        if (curr is WalletLoaded && prev is WalletLoaded) {
          return curr.invoiceReceived && !prev.invoiceReceived;
        }
        return false;
      },
      listener: (context, state) {
        if (state is WalletLoaded && state.invoiceReceived) {
          _receivedAnimController.forward(from: 0);
        }
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: Stack(
          children: [
            CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.of(context).padding.top + 100,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildQrSection(context, colors, l10n),
                ),
                SliverToBoxAdapter(
                  child: _buildReceivedIndicator(context, colors, l10n),
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
            TopActionBarWidget(
              showShareButton: false,
              centerBubble: Text(
                l10n.receive,
                style: TextStyle(
                  color: colors.background,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              centerBubbleVisibility: _showTitleBubble,
              onCenterBubbleTap: () {
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceivedIndicator(
      BuildContext context, dynamic colors, AppLocalizations l10n) {
    return BlocBuilder<WalletBloc, WalletState>(
      buildWhen: (prev, curr) {
        if (prev is WalletLoaded && curr is WalletLoaded) {
          return prev.invoiceReceived != curr.invoiceReceived;
        }
        return false;
      },
      builder: (context, state) {
        final received =
            state is WalletLoaded && state.invoiceReceived && _invoice != null;

        if (!received) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: ScaleTransition(
            scale: _receivedScaleAnim,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PhosphorIcon(
                    PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                    size: 22,
                    color: const Color(0xFF22C55E),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.paymentReceived,
                    style: const TextStyle(
                      color: Color(0xFF22C55E),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQrSection(
      BuildContext context, dynamic colors, AppLocalizations l10n) {
    final screenWidth = MediaQuery.of(context).size.width;
    final qrSize = screenWidth - 80;
    final qrData = _qrData;

    return BlocBuilder<WalletBloc, WalletState>(
      buildWhen: (prev, curr) {
        if (prev is WalletLoaded && curr is WalletLoaded) {
          return prev.invoiceReceived != curr.invoiceReceived;
        }
        return false;
      },
      builder: (context, state) {
        final received =
            state is WalletLoaded && state.invoiceReceived && _invoice != null;

        return Center(
          child: GestureDetector(
            onTap: qrData.isNotEmpty ? () => _copyToClipboard(qrData) : null,
            child: SizedBox(
              width: qrSize,
              height: qrSize,
              child: received
                  ? _buildReceivedQrOverlay(qrData, qrSize, colors, l10n)
                  : _buildQrContent(qrData, qrSize, colors, l10n),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReceivedQrOverlay(
      String qrData, double qrSize, dynamic colors, AppLocalizations l10n) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: 0.3,
          child: _buildQrContent(qrData, qrSize, colors, l10n),
        ),
        Container(
          width: qrSize * 0.5,
          height: qrSize * 0.5,
          decoration: BoxDecoration(
            color: colors.background,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF22C55E).withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Center(
            child: PhosphorIcon(
              PhosphorIconsFill.checkCircle,
              size: 64,
              color: Color(0xFF22C55E),
            ),
          ),
        ),
      ],
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


