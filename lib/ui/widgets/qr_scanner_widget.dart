import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../l10n/app_localizations.dart';
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

class _QrScannerWidgetState extends State<QrScannerWidget>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
  );
  StreamSubscription<Object?>? _subscription;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = _controller.barcodes.listen(_handleBarcode);
    unawaited(_controller.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;

    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_subscription?.cancel());
        _subscription = null;
        unawaited(_controller.stop());
      case AppLifecycleState.resumed:
        _subscription = _controller.barcodes.listen(_handleBarcode);
        unawaited(_controller.start());
      case AppLifecycleState.inactive:
        unawaited(_subscription?.cancel());
        _subscription = null;
        unawaited(_controller.stop());
    }
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_scanned) return;

    final barcode = capture.barcodes.firstOrNull;
    final value = barcode?.rawValue;

    if (value != null && value.isNotEmpty) {
      _scanned = true;
      widget.onScanComplete(value);
      Navigator.pop(context);
    }
  }

  @override
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
    await _controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(controller: _controller),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: GestureDetector(
              onTap: () => _controller.toggleTorch(),
              child: ValueListenableBuilder(
                valueListenable: _controller,
                builder: (context, state, _) {
                  final torchOn = state.torchState == TorchState.on;
                  return Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: context.colors.textPrimary,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(
                      torchOn ? Icons.flash_on : Icons.flash_off,
                      color: context.colors.background,
                      size: 20,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
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
                    label: AppLocalizations.of(context)!.cancel,
            onPressed: () => Navigator.pop(context),
            size: ButtonSize.large,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
