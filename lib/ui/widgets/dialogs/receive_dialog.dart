import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../theme/theme_manager.dart';
import '../common/common_buttons.dart';

class ReceiveDialog extends StatefulWidget {
  final WalletRepository walletRepository;
  final String? lud16;

  const ReceiveDialog({
    super.key,
    required this.walletRepository,
    this.lud16,
  });

  @override
  State<ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<ReceiveDialog> {
  final TextEditingController _amountController = TextEditingController();

  bool _isLoading = false;
  String? _invoice;
  int? _amount;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData != null && clipboardData.text != null) {
      _amountController.text = clipboardData.text!;
    }
  }

  Future<void> _createInvoice() async {
    final amountValue = int.tryParse(_amountController.text.trim());
    if (amountValue == null || amountValue <= 0) {
      setState(() {
        _error = 'Please enter a valid amount';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await widget.walletRepository.makeInvoice(
        amountValue,
        'Receive $amountValue sats',
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          result.fold(
            (invoiceResult) {
              _invoice = invoiceResult;
              _amount = amountValue;
            },
            (errorResult) {
              _error = 'Failed to create invoice: $errorResult';
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
    if (_invoice != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _amount != null ? 'Receive $_amount sats' : 'Lightning Invoice',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.overlayLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _invoice!,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (widget.lud16 != null && widget.lud16!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Your Lightning Address',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.overlayLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  widget.lud16!,
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
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
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            enabled: !_isLoading,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
            ),
            decoration: InputDecoration(
              hintText: 'Enter amount in sats...',
              hintStyle: TextStyle(
                color: colors.textSecondary,
                fontSize: 15,
              ),
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
              filled: true,
              fillColor: colors.overlayLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              label: 'Create Invoice',
              onPressed: _isLoading ? null : _createInvoice,
              isLoading: _isLoading,
              size: ButtonSize.large,
            ),
          ),
        ],
      ),
    );
  }
}
