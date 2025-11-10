import 'package:flutter/material.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../theme/theme_manager.dart';

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
    if (_successMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              color: context.colors.textPrimary,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _successMessage!,
              style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
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
        children: [
          TextField(
            controller: _invoiceController,
            enabled: !_isLoading,
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Lightning Invoice',
              hintText: 'Paste invoice here...',
              labelStyle: TextStyle(
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
              ),
              hintStyle: TextStyle(color: context.colors.textSecondary),
              filled: true,
              fillColor: context.colors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            maxLines: 3,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: context.colors.error, fontSize: 12),
            ),
          ],
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _isLoading ? null : _payInvoice,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.buttonPrimary,
                borderRadius: BorderRadius.circular(40),
              ),
              child: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(context.colors.background),
                      ),
                    )
                  : Text(
                      'Pay Invoice',
                      style: TextStyle(
                        color: context.colors.buttonText,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

