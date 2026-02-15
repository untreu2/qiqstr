import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/di/app_di.dart';
import '../../../data/services/coinos_service.dart';
import '../../../data/services/nwc_service.dart';
import '../../theme/theme_manager.dart';
import '../common/common_buttons.dart';
import '../common/custom_input_field.dart';
import '../../../l10n/app_localizations.dart';

class ReceiveDialog extends StatefulWidget {
  final String? lud16;

  const ReceiveDialog({
    super.key,
    this.lud16,
  });

  @override
  State<ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<ReceiveDialog> {
  final TextEditingController _amountController = TextEditingController();
  final CoinosService _coinosService = AppDI.get<CoinosService>();

  bool _isUpdating = false;
  String? _invoice;
  String? _error;
  Timer? _debounce;
  bool _addressCopied = false;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onInputChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _updateQr();
    });
  }

  bool get _isNwcMode => AppDI.get<NwcService>().isActive;

  Future<void> _updateQr() async {
    final amountText = _amountController.text.trim();

    if (amountText.isEmpty) {
      setState(() {
        _invoice = null;
      });
      return;
    }

    final amountValue = int.tryParse(amountText);
    if (amountValue == null || amountValue <= 0) {
      setState(() {
        _invoice = null;
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
              (invoice) {
                _invoice = invoice;
              },
              (errorResult) {
                _error = AppLocalizations.of(context)!
                    .failedToCreateInvoice(errorResult.toString());
                _invoice = null;
              },
            );
          });
        }
      } else {
        final result = await _coinosService.createInvoice(
          amount: amountValue,
          type: 'lightning',
        );

        if (mounted) {
          setState(() {
            _isUpdating = false;
            result.fold(
              (invoiceResult) {
                _invoice = invoiceResult['hash'] as String?;
              },
              (errorResult) {
                _error = AppLocalizations.of(context)!
                    .failedToCreateInvoice(errorResult.toString());
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

  String _getQrData() {
    if (_invoice != null) {
      return _invoice!;
    }
    if (widget.lud16 != null &&
        widget.lud16!.isNotEmpty &&
        _amountController.text.trim().isEmpty) {
      return widget.lud16!;
    }
    return '';
  }

  bool _hasLightningAddress() {
    return widget.lud16 != null && widget.lud16!.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final qrData = _getQrData();
    final hasLightningAddress = _hasLightningAddress();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 40,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.receive,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.overlayLight,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      size: 20,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (qrData.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: colors.textSecondary.withValues(alpha: 0.3),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(8),
                child: _isUpdating
                    ? SizedBox(
                        height: 200,
                        width: 200,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: colors.textPrimary,
                          ),
                        ),
                      )
                    : QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 200.0,
                        backgroundColor: colors.background,
                        eyeStyle: QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: colors.textPrimary,
                        ),
                        dataModuleStyle: QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: colors.textPrimary,
                        ),
                      ),
              ),
            const SizedBox(height: 16),
            if (_invoice != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.overlayLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  _invoice!.length > 20
                      ? '${_invoice!.substring(0, 20)}...'
                      : _invoice!,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            if (hasLightningAddress) ...[
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.lud16!));
                  setState(() => _addressCopied = true);
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) setState(() => _addressCopied = false);
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: colors.overlayLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _addressCopied
                      ? Text(
                          l10n.copiedToClipboard,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.lud16!,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.copy,
                                size: 14, color: colors.textSecondary),
                          ],
                        ),
                ),
              ),
            ],
            const SizedBox(height: 32),
            CustomInputField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              enabled: !_isUpdating,
              hintText: '${l10n.amount} (${l10n.optional})',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: colors.error, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            if (qrData.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: SecondaryButton(
                  label: l10n.copy,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: qrData));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.copiedToClipboard),
                        backgroundColor: colors.success,
                      ),
                    );
                  },
                  size: ButtonSize.large,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
