import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/di/app_di.dart';
import '../../../data/services/nwc_service.dart';
import '../../../data/services/spark_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../theme/theme_manager.dart';
import '../../widgets/common/snackbar_widget.dart';
import '../../widgets/common/top_action_bar_widget.dart';

class ReceivePage extends StatefulWidget {
  final String? lud16;

  const ReceivePage({super.key, this.lud16});

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  final TextEditingController _amountController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showTitleBubble = ValueNotifier(true);

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
    _amountController.dispose();
    _scrollController.dispose();
    _showTitleBubble.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final text = _amountController.text.trim();
    final newHasAmount = text.isNotEmpty;
    if (newHasAmount != _hasAmount) {
      setState(() => _hasAmount = newHasAmount);
    }
    if (text.isEmpty && (_invoice != null || _error != null)) {
      setState(() {
        _invoice = null;
        _error = null;
      });
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
      if (_isNwcMode) {
        final nwcService = AppDI.get<NwcService>();
        final result = await nwcService.makeInvoice(amountSats: amountValue);
        if (mounted) {
          setState(() {
            _isUpdating = false;
            result.fold(
              (invoice) => _invoice = invoice,
              (err) {
                _error = AppLocalizations.of(context)!
                    .failedToCreateInvoice(err.toString());
                _invoice = null;
              },
            );
          });
        }
      } else {
        final sparkService = AppDI.get<SparkService>();
        final result = await sparkService.createLightningInvoice(
          amountSats: amountValue,
        );
        if (mounted) {
          setState(() {
            _isUpdating = false;
            result.fold(
              (invoice) => _invoice = invoice,
              (err) {
                _error = AppLocalizations.of(context)!
                    .failedToCreateInvoice(err.toString());
                _invoice = null;
              },
            );
          });
        }
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

    return Scaffold(
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
            Icon(
              Icons.qr_code_2,
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
              Icon(Icons.copy, size: 20, color: colors.textSecondary),
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
