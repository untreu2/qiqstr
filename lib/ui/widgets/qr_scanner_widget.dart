import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import '../theme/theme_manager.dart';
import 'common/common_buttons.dart';

class QrScannerWidget extends StatefulWidget {
  final Function(String) onScanComplete;

  const QrScannerWidget({
    super.key,
    required this.onScanComplete,
  });

  @override
  State<QrScannerWidget> createState() => _QrScannerWidgetState();
}

class _QrScannerWidgetState extends State<QrScannerWidget> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  bool _scanned = false;

  @override
  void reassemble() {
    super.reassemble();
    if (controller != null) {
      if (Theme.of(context).platform == TargetPlatform.android) {
        controller!.pauseCamera();
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        controller!.resumeCamera();
      }
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      if (!_scanned) {
        _scanned = true;
        final scannedText = scanData.code ?? "";
        if (scannedText.isNotEmpty) {
          widget.onScanComplete(scannedText);
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Scan failed, please try again"),
              backgroundColor: context.colors.error,
            ),
          );
          _scanned = false;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: QRView(
        key: qrKey,
        onQRViewCreated: _onQRViewCreated,
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        child: SizedBox(
          width: double.infinity,
          child: SecondaryButton(
            label: 'Cancel',
            onPressed: () {
              Navigator.pop(context);
            },
            size: ButtonSize.large,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
