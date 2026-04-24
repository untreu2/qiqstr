import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../core/di/app_di.dart';
import '../../../data/services/nwc_service.dart';
import '../../../data/services/spark_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../theme/theme_manager.dart';
import '../common/snackbar_widget.dart';
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
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _lnAmountController = TextEditingController();

  bool _isLoading = false;
  bool _isResolvingAddress = false;
  int? _parsedSats;
  _InputType _inputType = _InputType.unknown;
  String? _lnAddressCallback;
  int? _lnMinSendable;
  int? _lnMaxSendable;
  String? _resolveError;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _lnAmountController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final text = _inputController.text.trim();
    final newType = _detectInputType(text);

    if (newType != _inputType) {
      setState(() {
        _inputType = newType;
        _parsedSats = null;
        _lnAddressCallback = null;
        _lnMinSendable = null;
        _lnMaxSendable = null;
        _resolveError = null;
      });
    }

    if (newType == _InputType.bolt11) {
      final sats = _parseBolt11Sats(text);
      if (sats != _parsedSats) {
        setState(() => _parsedSats = sats);
      }
    } else if (newType == _InputType.lightningAddress) {
      _resolveLightningAddress(text);
    }
  }

  _InputType _detectInputType(String text) {
    if (text.isEmpty) return _InputType.unknown;
    final lower = text.toLowerCase();
    if (lower.startsWith('lnbc') ||
        lower.startsWith('lntb') ||
        lower.startsWith('lnbcrt')) {
      return _InputType.bolt11;
    }
    if (_isLightningAddress(text)) return _InputType.lightningAddress;
    return _InputType.unknown;
  }

  bool _isLightningAddress(String text) {
    final parts = text.split('@');
    if (parts.length != 2) return false;
    final user = parts[0];
    final domain = parts[1];
    return user.isNotEmpty &&
        domain.contains('.') &&
        !domain.startsWith('.') &&
        !domain.endsWith('.');
  }

  Future<void> _resolveLightningAddress(String address) async {
    final parts = address.split('@');
    if (parts.length != 2) return;
    final username = parts[0];
    final domain = parts[1];

    setState(() {
      _isResolvingAddress = true;
      _resolveError = null;
      _lnAddressCallback = null;
    });

    try {
      final url = Uri.parse('https://$domain/.well-known/lnurlp/$username');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final callback = data['callback'] as String?;
        final minSendable = (data['minSendable'] as num?)?.toInt();
        final maxSendable = (data['maxSendable'] as num?)?.toInt();

        setState(() {
          _isResolvingAddress = false;
          _lnAddressCallback = callback;
          _lnMinSendable = minSendable != null ? minSendable ~/ 1000 : null;
          _lnMaxSendable = maxSendable != null ? maxSendable ~/ 1000 : null;
        });
      } else {
        setState(() {
          _isResolvingAddress = false;
          _resolveError = AppLocalizations.of(context)!.resolveAddressFailed;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isResolvingAddress = false;
          _resolveError = AppLocalizations.of(context)!.resolveAddressFailed;
        });
      }
    }
  }

  Future<String?> _fetchInvoiceFromCallback(int amountSats) async {
    if (_lnAddressCallback == null) return null;
    try {
      final uri = Uri.parse(_lnAddressCallback!)
          .replace(queryParameters: {'amount': '${amountSats * 1000}'});
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['pr'] as String?;
      }
    } catch (_) {}
    return null;
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
    if (clipboardData?.text != null) {
      _inputController.text = clipboardData!.text!.trim();
      _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: _inputController.text.length),
      );
    }
  }

  Future<void> _scanQrCode() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QrScannerWidget(
          onScanComplete: (scannedText) {
            if (mounted) {
              _inputController.text = scannedText.trim();
              _inputController.selection = TextSelection.fromPosition(
                TextPosition(offset: _inputController.text.length),
              );
            }
          },
        ),
      ),
    );
  }

  bool get _isNwcMode => AppDI.get<NwcService>().isActive;

  Future<void> _pay() async {
    final l10n = AppLocalizations.of(context)!;

    if (_inputType == _InputType.lightningAddress) {
      await _payLightningAddress(l10n);
    } else {
      await _payBolt11(l10n);
    }
  }

  Future<void> _payLightningAddress(AppLocalizations l10n) async {
    if (_lnAddressCallback == null) {
      AppSnackbar.error(context, l10n.resolveAddressFailed);
      return;
    }

    final amountText = _lnAmountController.text.trim();
    final amountSats = int.tryParse(amountText);
    if (amountSats == null || amountSats <= 0) {
      AppSnackbar.error(context, l10n.enterValidAmount);
      return;
    }

    if (_lnMinSendable != null && amountSats < _lnMinSendable!) {
      AppSnackbar.error(
          context, '${l10n.amount}: min ${_formatSats(_lnMinSendable!)} sats');
      return;
    }
    if (_lnMaxSendable != null && amountSats > _lnMaxSendable!) {
      AppSnackbar.error(
          context, '${l10n.amount}: max ${_formatSats(_lnMaxSendable!)} sats');
      return;
    }

    setState(() => _isLoading = true);

    final invoice = await _fetchInvoiceFromCallback(amountSats);
    if (!mounted) return;

    if (invoice == null) {
      setState(() => _isLoading = false);
      AppSnackbar.error(context, l10n.resolveAddressFailed);
      return;
    }

    await _sendInvoice(invoice, l10n);
  }

  Future<void> _payBolt11(AppLocalizations l10n) async {
    final invoice = _inputController.text.trim();
    if (invoice.isEmpty) {
      AppSnackbar.error(context, l10n.pleaseEnterInvoice);
      return;
    }
    setState(() => _isLoading = true);
    await _sendInvoice(invoice, l10n);
  }

  Future<void> _sendInvoice(String invoice, AppLocalizations l10n) async {
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
        final sparkService = AppDI.get<SparkService>();
        final result = await sparkService.payLightningInvoice(invoice);
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

  bool get _canPay {
    if (_isLoading || _isResolvingAddress) return false;
    if (_inputType == _InputType.bolt11) return true;
    if (_inputType == _InputType.lightningAddress) {
      return _lnAddressCallback != null &&
          _lnAmountController.text.trim().isNotEmpty;
    }
    return false;
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
          _buildHeader(context, colors, l10n),
          const SizedBox(height: 16),
          _buildInputField(context, colors, l10n),
          _buildInputStatus(context, colors, l10n),
          if (_inputType == _InputType.lightningAddress &&
              _lnAddressCallback != null)
            _buildLnAmountField(context, colors, l10n),
          const SizedBox(height: 20),
          _buildPayButton(context, colors, l10n),
        ],
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, dynamic colors, AppLocalizations l10n) {
    return Row(
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
            child: Icon(Icons.close, size: 20, color: colors.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _buildInputField(
      BuildContext context, dynamic colors, AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: colors.overlayLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              enabled: !_isLoading,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: l10n.lightningAddressOrInvoice,
                hintStyle: TextStyle(
                  color: colors.textSecondary.withValues(alpha: 0.5),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildIconButton(
                  icon: Icons.qr_code_scanner,
                  colors: colors,
                  onTap: _scanQrCode,
                ),
                const SizedBox(width: 6),
                _buildIconButton(
                  icon: Icons.content_paste,
                  colors: colors,
                  onTap: _pasteFromClipboard,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required dynamic colors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: colors.background,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: colors.textPrimary, size: 18),
      ),
    );
  }

  Widget _buildInputStatus(
      BuildContext context, dynamic colors, AppLocalizations l10n) {
    if (_isResolvingAddress) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.resolvingAddress,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_resolveError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          _resolveError!,
          style: TextStyle(color: colors.error, fontSize: 13),
        ),
      );
    }

    if (_inputType == _InputType.bolt11 && _parsedSats != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Center(
          child: Text(
            '${_formatSats(_parsedSats!)} sats',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    if (_inputType == _InputType.lightningAddress &&
        _lnAddressCallback != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Icon(Icons.check_circle, size: 14, color: colors.success),
            const SizedBox(width: 6),
            Text(
              _inputController.text.trim(),
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
              ),
            ),
            if (_lnMinSendable != null) ...[
              const SizedBox(width: 6),
              Text(
                '(min ${_formatSats(_lnMinSendable!)} sats)',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ],
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildLnAmountField(
      BuildContext context, dynamic colors, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        decoration: BoxDecoration(
          color: colors.overlayLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _lnAmountController,
                keyboardType: TextInputType.number,
                enabled: !_isLoading,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: l10n.amountInSats,
                  hintStyle: TextStyle(
                    color: colors.textSecondary.withValues(alpha: 0.5),
                    fontSize: 16,
                  ),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Text(
                'sats',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPayButton(
      BuildContext context, dynamic colors, AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: _canPay ? _pay : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _canPay
                ? colors.textPrimary
                : colors.textPrimary.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(24),
          ),
          child: _isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.background,
                  ),
                )
              : Text(
                  l10n.payInvoice,
                  style: TextStyle(
                    color: colors.background,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}

enum _InputType { unknown, bolt11, lightningAddress }
