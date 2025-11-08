import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../theme/theme_manager.dart';
import '../snackbar_widget.dart';

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
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  bool _isLoading = false;
  String? _error;

  bool get _isLightningAddress {
    final text = _inputController.text.trim();
    return text.contains('@') && text.split('@').length == 2;
  }

  Future<void> _openCamera() async {
    if (!mounted) return;
    
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _QRScannerPage(
          onScanned: (value) {
            setState(() {
              _inputController.text = value;
            });
          },
        ),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData != null && clipboardData.text != null && clipboardData.text!.isNotEmpty) {
      setState(() {
        _inputController.text = clipboardData.text!;
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<String> _getInvoiceFromLightningAddress(String lightningAddress, int amount) async {
    if (!lightningAddress.contains('@')) {
      throw Exception('Invalid lightning address format');
    }

    final parts = lightningAddress.split('@');
    if (parts.length != 2 || parts.any((p) => p.isEmpty)) {
      throw Exception('Invalid lightning address format');
    }

    final displayName = parts[0];
    final domain = parts[1];

    final uri = Uri.parse('https://$domain/.well-known/lnurlp/$displayName');
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('LNURL fetch failed with status: ${response.statusCode}');
    }

    final lnurlJson = jsonDecode(response.body);
    final callback = lnurlJson['callback'];
    if (callback == null || callback.isEmpty) {
      throw Exception('Callback URL is missing');
    }

    final amountMillisats = (amount * 1000).toString();
    final callbackUrl = Uri.parse('$callback?amount=$amountMillisats');
    final invoiceResponse = await http.get(callbackUrl);
    if (invoiceResponse.statusCode != 200) {
      throw Exception('Invoice fetch failed: ${invoiceResponse.body}');
    }

    final invoiceJson = jsonDecode(invoiceResponse.body);
    final invoice = invoiceJson['pr'];
    if (invoice == null || invoice.toString().isEmpty) {
      throw Exception('Invoice not returned');
    }

    return invoice.toString();
  }

  Future<void> _pay() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      String invoice;
      final input = _inputController.text.trim();

      if (input.isEmpty) {
        setState(() {
          _isLoading = false;
          _error = 'Please enter an invoice or lightning address';
        });
        return;
      }

      if (_isLightningAddress) {
        final amountValue = int.tryParse(_amountController.text.trim());
        if (amountValue == null || amountValue <= 0) {
          setState(() {
            _isLoading = false;
            _error = 'Please enter a valid amount';
          });
          return;
        }

        invoice = await _getInvoiceFromLightningAddress(input, amountValue);
      } else {
        invoice = input;
      }

      final result = await widget.walletRepository.payInvoice(invoice);

      if (mounted) {
        setState(() {
          _isLoading = false;
          result.fold(
            (paymentResult) {
              widget.onPaymentSuccess();
              Navigator.of(context).pop();
              AppSnackbar.success(
                context,
                'Payment sent successfully',
                duration: const Duration(seconds: 2),
              );
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
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  enabled: !_isLoading,
                  onChanged: (value) {
                    setState(() {});
                  },
                  style: TextStyle(color: context.colors.textPrimary),
                  decoration: InputDecoration(
                    labelText: _isLightningAddress ? 'Lightning Address' : 'Lightning Invoice',
                    hintText: _isLightningAddress ? 'user@domain.com' : 'Paste invoice here...',
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
                  maxLines: _isLightningAddress ? 1 : 3,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _isLoading ? null : _pasteFromClipboard,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: context.colors.buttonPrimary,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.paste,
                        color: context.colors.buttonText,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _isLoading ? null : _openCamera,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: context.colors.buttonPrimary,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.qr_code_scanner,
                        color: context.colors.buttonText,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
            if (_isLightningAddress) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                enabled: !_isLoading,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Amount (sats)',
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                  ),
                  filled: true,
                  fillColor: context.colors.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: context.colors.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _isLoading ? null : _pay,
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
                        'Send',
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

class _ScannerOverlay extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final scanArea = size.width * 0.7;
    final left = (size.width - scanArea) / 2;
    final top = (size.height - scanArea) / 2;

    final scanPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, scanArea, scanArea),
          const Radius.circular(20),
        ),
      );

    final combinedPath = Path.combine(
      PathOperation.difference,
      path,
      scanPath,
    );

    canvas.drawPath(combinedPath, paint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, scanArea, scanArea),
        const Radius.circular(20),
      ),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _QRScannerPage extends StatefulWidget {
  final Function(String) onScanned;

  const _QRScannerPage({
    required this.onScanned,
  });

  @override
  State<_QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<_QRScannerPage> {
  late MobileScannerController _scannerController;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  _scannerController.stop();
                  widget.onScanned(barcode.rawValue!);
                  if (mounted) {
                    Navigator.of(context).pop();
                  }
                  break;
                }
              }
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomPaint(
              painter: _ScannerOverlay(),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Scan QR Code',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.flash_on, color: Colors.white),
                  onPressed: () {
                    _scannerController.toggleTorch();
                  },
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).padding.bottom + 12,
              ),
              child: GestureDetector(
                onTap: () {
                  _scannerController.stop();
                  if (mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.colors.buttonPrimary,
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Text(
                    'Close',
                    style: TextStyle(
                      color: context.colors.buttonText,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

