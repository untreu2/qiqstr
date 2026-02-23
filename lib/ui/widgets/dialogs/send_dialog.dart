import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/di/app_di.dart';
import '../../../data/services/coinos_service.dart';
import '../../../data/services/nwc_service.dart';
import '../../theme/theme_manager.dart';
import '../common/common_buttons.dart';
import '../common/custom_input_field.dart';
import '../common/snackbar_widget.dart';
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
  int? _parsedSats;

  @override
  void initState() {
    super.initState();
    _invoiceController.addListener(_onInvoiceChanged);
  }

  @override
  void dispose() {
    _invoiceController.removeListener(_onInvoiceChanged);
    _invoiceController.dispose();
    super.dispose();
  }

  void _onInvoiceChanged() {
    final sats = _parseBolt11Sats(_invoiceController.text.trim());
    if (sats != _parsedSats) {
      setState(() => _parsedSats = sats);
    }
  }

  int? _parseBolt11Sats(String bolt11) {
    if (bolt11.isEmpty) return null;
    final lower = bolt11.toLowerCase();
    final sepPos = lower.lastIndexOf('1');
    if (sepPos < 0) return null;
    final hrPart = lower.substring(0, sepPos);

    String afterPrefix;
    if (hrPart.startsWith('lnbcrt')) {
      afterPrefix = hrPart.substring(6);
    } else if (hrPart.startsWith('lnbc')) {
      afterPrefix = hrPart.substring(4);
    } else if (hrPart.startsWith('lntbs')) {
      afterPrefix = hrPart.substring(5);
    } else if (hrPart.startsWith('lntb')) {
      afterPrefix = hrPart.substring(4);
    } else {
      return null;
    }

    if (afterPrefix.isEmpty) return null;

    var i = 0;
    while (i < afterPrefix.length &&
        afterPrefix.codeUnitAt(i) >= 48 &&
        afterPrefix.codeUnitAt(i) <= 57) {
      i++;
    }
    if (i == 0) return null;

    final amount = int.tryParse(afterPrefix.substring(0, i));
    if (amount == null) return null;

    int msats;
    if (i < afterPrefix.length) {
      switch (afterPrefix[i]) {
        case 'm':
          msats = amount * 100000000;
        case 'u':
          msats = amount * 100000;
        case 'n':
          msats = amount * 100;
        case 'p':
          msats = amount ~/ 10;
        default:
          return null;
      }
    } else {
      msats = amount * 100000000000;
    }

    return msats ~/ 1000;
  }

  String _formatSats(int sats) {
    final str = sats.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return buffer.toString();
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
      AppSnackbar.error(context, l10n.pleaseEnterInvoice);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isNwcMode) {
        final nwcService = AppDI.get<NwcService>();
        final result = await nwcService.payInvoice(invoice);

        if (mounted) {
          setState(() => _isLoading = false);
          result.fold(
            (_) {
              AppSnackbar.success(context, l10n.paymentSent);
              widget.onPaymentSuccess();
              Navigator.pop(context);
            },
            (error) =>
                AppSnackbar.error(context, '${l10n.paymentFailed}: $error'),
          );
        }
      } else {
        final result = await _coinosService.payInvoice(invoice);

        if (mounted) {
          setState(() => _isLoading = false);
          result.fold(
            (_) {
              AppSnackbar.success(context, l10n.paymentSent);
              widget.onPaymentSuccess();
              Navigator.pop(context);
            },
            (error) =>
                AppSnackbar.error(context, '${l10n.paymentFailed}: $error'),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppSnackbar.error(context, '${l10n.error}: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

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
          if (_parsedSats != null) ...[
            const SizedBox(height: 12),
            Center(
              child: Text(
                '${_formatSats(_parsedSats!)} sats',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
