import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/di/app_di.dart';
import '../../../data/services/coinos_service.dart';
import '../../../data/services/nwc_service.dart';
import '../../theme/theme_manager.dart';
import '../common/common_buttons.dart';
import '../common/custom_input_field.dart';
import '../../../l10n/app_localizations.dart';
import '../qr_scanner_widget.dart';

class SendDialog extends StatefulWidget {
  final VoidCallback onPaymentSuccess;

  const SendDialog({
    super.key,
    required this.onPaymentSuccess,
  });

  @override
  State<SendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends State<SendDialog> {
  final TextEditingController _invoiceController = TextEditingController();
  final CoinosService _coinosService = AppDI.get<CoinosService>();

  bool _isLoading = false;
  String? _error;
  String? _successMessage;

  @override
  void dispose() {
    _invoiceController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData != null && clipboardData.text != null) {
      _invoiceController.text = clipboardData.text!;
    }
  }

  Future<void> _scanQrCode() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QrScannerWidget(
          onScanComplete: (scannedText) {
            if (mounted) {
              setState(() {
                _invoiceController.text = scannedText;
              });
            }
          },
        ),
      ),
    );
  }

  bool get _isNwcMode => AppDI.get<NwcService>().isActive;

  Future<void> _payInvoice() async {
    final l10n = AppLocalizations.of(context)!;
    final invoice = _invoiceController.text.trim();
    if (invoice.isEmpty) {
      setState(() {
        _error = l10n.pleaseEnterInvoice;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _successMessage = null;
    });

    try {
      if (_isNwcMode) {
        final nwcService = AppDI.get<NwcService>();
        final result = await nwcService.payInvoice(invoice);

        if (mounted) {
          setState(() {
            _isLoading = false;
            result.fold(
              (paymentResult) {
                _successMessage = l10n.paymentSent;
                widget.onPaymentSuccess();
              },
              (errorResult) {
                _error = '${l10n.paymentFailed}: $errorResult';
              },
            );
          });
        }
      } else {
        final result = await _coinosService.payInvoice(invoice);

        if (mounted) {
          setState(() {
            _isLoading = false;
            result.fold(
              (paymentResult) {
                _successMessage = l10n.paymentSent;
                widget.onPaymentSuccess();
              },
              (errorResult) {
                _error = '${l10n.paymentFailed}: $errorResult';
              },
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '${l10n.error}: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    if (_successMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              color: colors.textPrimary,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _successMessage!,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.send,
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
          CustomInputField(
            controller: _invoiceController,
            enabled: !_isLoading,
            hintText: l10n.pasteInvoiceHere,
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _scanQrCode,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.background,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.qr_code_scanner,
                        color: colors.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _pasteFromClipboard,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.background,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.content_paste,
                        color: colors.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: colors.error, fontSize: 12),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: SecondaryButton(
              label: l10n.payInvoice,
              onPressed: _isLoading ? null : _payInvoice,
              isLoading: _isLoading,
              size: ButtonSize.large,
            ),
          ),
        ],
      ),
    );
  }
}
