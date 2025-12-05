import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../theme/theme_manager.dart';
import '../common/common_buttons.dart';
import '../common/custom_input_field.dart';

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

  Future<void> _payInvoice() async {
    final invoice = _invoiceController.text.trim();
    if (invoice.isEmpty) {
      setState(() {
        _error = 'Please enter an invoice';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _successMessage = null;
    });

    try {
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
              hintText: 'Paste invoice here...',
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
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
              label: 'Pay Invoice',
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
