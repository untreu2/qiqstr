import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../theme/theme_manager.dart';
import '../common/common_buttons.dart';
import '../common/custom_input_field.dart';

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

  bool _isUpdating = false;
  String? _invoice;
  String? _error;
  Timer? _debounce;

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
      final result = await widget.walletRepository.makeInvoice(
        amountValue,
        'Receive $amountValue sats',
      );

      if (mounted) {
        setState(() {
          _isUpdating = false;
          result.fold(
            (invoiceResult) {
              _invoice = invoiceResult;
            },
            (errorResult) {
              _error = 'Failed to create invoice: $errorResult';
              _invoice = null;
            },
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUpdating = false;
          _error = 'Error: $e';
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

  bool _showLightningAddress() {
    return widget.lud16 != null &&
        widget.lud16!.isNotEmpty &&
        _amountController.text.trim().isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final qrData = _getQrData();
    final showLightningAddress = _showLightningAddress();

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
            const SizedBox(height: 8),
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
                        foregroundColor: colors.textPrimary,
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
            if (showLightningAddress) ...[
              Text(
                widget.lud16!,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 32),
            CustomInputField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              enabled: !_isUpdating,
              hintText: 'Amount (Optional)',
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
                  label: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: qrData));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Copied to clipboard'),
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
