import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../theme/theme_manager.dart';
import '../common/common_buttons.dart';
import '../common/custom_input_field.dart';
import '../qr_scanner_widget.dart';

class SendDialog extends StatefulWidget {
  final WalletRepository walletRepository;
  final VoidCallback onPaymentSuccess;

  const SendDialog({
    super.key,
    required this.walletRepository,
    required this.onPaymentSuccess,
  });

  @override
  State<SendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends State<SendDialog> {
  final TextEditingController _invoiceController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  String? _successMessage;
  String _paymentMethod = 'unknown';

  @override
  void initState() {
    super.initState();
    _invoiceController.addListener(_detectPaymentMethod);
  }

  @override
  void dispose() {
    _invoiceController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _detectPaymentMethod() {
    final data = _invoiceController.text.trim();
    if (data.isEmpty) {
      setState(() {
        _paymentMethod = 'unknown';
      });
      return;
    }

    if (data.toLowerCase().startsWith('lnbc') && !data.contains('@')) {
      setState(() {
        _paymentMethod = 'invoice';
      });
    } else if (data.contains('@') || data.toLowerCase().startsWith('lnurl')) {
      setState(() {
        _paymentMethod = 'lightning_address';
      });
    } else {
      setState(() {
        _paymentMethod = 'unknown';
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData != null && clipboardData.text != null) {
      _invoiceController.text = clipboardData.text!;
    }
  }

  Future<void> _scanQrCode() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QrScannerWidget(
          onScanComplete: (scannedText) {
            setState(() {
              _invoiceController.text = scannedText;
            });
          },
        ),
      ),
    );
  }

  Future<void> _payInvoice() async {
    final invoice = _invoiceController.text.trim();
    if (invoice.isEmpty) {
      setState(() {
        _error = 'Please enter an invoice or lightning address';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _successMessage = null;
    });

    try {
      if (_paymentMethod == 'invoice') {
        final result = await widget.walletRepository.payInvoice(invoice);

        if (mounted) {
          setState(() {
            _isLoading = false;
            result.fold(
              (paymentResult) {
                _successMessage = 'Payment sent! Preimage: ${paymentResult.preimage ?? 'N/A'}';
                widget.onPaymentSuccess();
              },
              (errorResult) {
                _error = 'Payment failed: $errorResult';
              },
            );
          });
        }
      } else if (_paymentMethod == 'lightning_address') {
        final amountText = _amountController.text.trim();
        final amount = int.tryParse(amountText);
        
        if (amount == null || amount <= 0) {
          setState(() {
            _isLoading = false;
            _error = 'Please enter a valid amount';
          });
          return;
        }

        final result = await widget.walletRepository.sendToLightningAddress(
          lightningAddress: invoice,
          amount: amount,
        );

        if (mounted) {
          setState(() {
            _isLoading = false;
            result.fold(
              (paymentResult) {
                _successMessage = 'Payment sent!';
                widget.onPaymentSuccess();
              },
              (errorResult) {
                _error = 'Payment failed: $errorResult';
              },
            );
          });
        }
      } else {
        setState(() {
          _isLoading = false;
          _error = 'Please enter a valid Lightning invoice or address';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          CustomInputField(
            controller: _invoiceController,
            enabled: !_isLoading,
            hintText: _paymentMethod == 'invoice'
                ? 'Paste invoice here...'
                : _paymentMethod == 'lightning_address'
                    ? 'Enter lightning address (user@domain.com)...'
                    : 'Paste invoice or lightning address...',
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
          if (_paymentMethod == 'lightning_address') ...[
            const SizedBox(height: 16),
            CustomInputField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              enabled: !_isLoading,
              hintText: 'Amount (sats)',
            ),
          ],
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
              label: _paymentMethod == 'lightning_address' 
                  ? 'Pay' 
                  : _paymentMethod == 'invoice'
                      ? 'Pay Invoice'
                      : 'Pay Invoice',
              onPressed: (_isLoading || _paymentMethod == 'unknown') ? null : _payInvoice,
              isLoading: _isLoading,
              size: ButtonSize.large,
            ),
          ),
        ],
      ),
    );
  }
}
