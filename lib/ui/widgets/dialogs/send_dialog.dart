import 'dart:async';
import 'dart:convert';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
  final TextEditingController _amountController = TextEditingController();

  bool _isLoading = false;
  bool _isParsing = false;
  String? _parseError;

  InputType? _parsedInput;
  Timer? _parseDebounce;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _parseDebounce?.cancel();
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final text = _inputController.text.trim();

    if (text.isEmpty) {
      _parseDebounce?.cancel();
      setState(() {
        _parsedInput = null;
        _parseError = null;
        _isParsing = false;
      });
      return;
    }

    setState(() {
      _parsedInput = null;
      _parseError = null;
      _isParsing = true;
    });

    _parseDebounce?.cancel();
    _parseDebounce =
        Timer(const Duration(milliseconds: 400), () => _parse(text));
  }

  Future<void> _parse(String text) async {
    if (!_isNwcMode) {
      final result = await AppDI.get<SparkService>().parseInput(text);
      if (!mounted) return;
      result.fold(
        (parsed) => setState(() {
          _parsedInput = parsed;
          _isParsing = false;
          _parseError = null;
        }),
        (_) => setState(() {
          _parsedInput = null;
          _isParsing = false;
          _parseError =
              AppLocalizations.of(context)!.unrecognizedPaymentFormat;
        }),
      );
    } else {
      // NWC mode: local detection for bolt11 / lightning address only
      final lower = text.toLowerCase();
      final isBolt11 = lower.startsWith('lnbc') ||
          lower.startsWith('lntb') ||
          lower.startsWith('lnbcrt');
      final isLnAddress = _looksLikeLightningAddress(text);
      if (!mounted) return;
      if (isBolt11) {
        setState(() {
          _isParsing = false;
          _parseError = null;
          _parsedInput = InputType.bolt11Invoice(Bolt11InvoiceDetails(
            amountMsat: _parseBolt11Msats(text),
            description: null,
            descriptionHash: null,
            expiry: BigInt.zero,
            invoice: Bolt11Invoice(
              bolt11: text,
              source: const PaymentRequestSource(),
            ),
            minFinalCltvExpiryDelta: BigInt.zero,
            network: BitcoinNetwork.bitcoin,
            payeePubkey: '',
            paymentHash: '',
            paymentSecret: '',
            routingHints: [],
            timestamp: BigInt.zero,
          ));
        });
      } else if (isLnAddress) {
        setState(() {
          _isParsing = false;
          _parseError = null;
          _parsedInput = InputType.lightningAddress(LightningAddressDetails(
            address: text,
            payRequest: LnurlPayRequestDetails(
              callback: '',
              minSendable: BigInt.zero,
              maxSendable: BigInt.zero,
              metadataStr: '',
              commentAllowed: 0,
              domain: text.split('@').last,
              url: '',
            ),
          ));
        });
      } else {
        setState(() {
          _isParsing = false;
          _parseError =
              AppLocalizations.of(context)!.unrecognizedPaymentFormat;
          _parsedInput = null;
        });
      }
    }
  }

  BigInt? _parseBolt11Msats(String bolt11) {
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
    return BigInt.from(msats);
  }

  bool _looksLikeLightningAddress(String text) {
    final parts = text.split('@');
    if (parts.length != 2) return false;
    final domain = parts[1];
    return parts[0].isNotEmpty &&
        domain.contains('.') &&
        !domain.startsWith('.') &&
        !domain.endsWith('.');
  }

  bool get _isNwcMode => AppDI.get<NwcService>().isActive;

  bool get _needsAmountField {
    final p = _parsedInput;
    if (p == null) return false;
    if (p is InputType_LightningAddress) return true;
    if (p is InputType_SparkAddress) return true;
    if (p is InputType_LnurlPay) return true;
    if (p is InputType_Bolt11Invoice) {
      final msats = p.field0.amountMsat;
      return msats == null || msats == BigInt.zero;
    }
    return false;
  }

  int? get _fixedAmountSats {
    final p = _parsedInput;
    if (p is InputType_Bolt11Invoice) {
      final msats = p.field0.amountMsat;
      if (msats != null && msats > BigInt.zero) {
        return (msats ~/ BigInt.from(1000)).toInt();
      }
    }
    if (p is InputType_SparkInvoice) {
      final sats = p.field0.amount;
      if (sats != null && sats > BigInt.zero) return sats.toInt();
    }
    return null;
  }

  String? get _description {
    final p = _parsedInput;
    if (p is InputType_Bolt11Invoice) return p.field0.description;
    if (p is InputType_SparkInvoice) return p.field0.description;
    if (p is InputType_LightningAddress) return p.field0.address;
    return null;
  }

  String? get _inputTypeLabel {
    final p = _parsedInput;
    if (p is InputType_Bolt11Invoice) return 'Lightning';
    if (p is InputType_LightningAddress) return 'Lightning Address';
    if (p is InputType_SparkAddress) return 'Spark';
    if (p is InputType_SparkInvoice) return 'Spark Invoice';
    if (p is InputType_LnurlPay) return 'LNURL-Pay';
    return null;
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

  Future<void> _pay() async {
    final l10n = AppLocalizations.of(context)!;
    final parsed = _parsedInput;
    if (parsed == null) return;

    setState(() => _isLoading = true);

    try {
      if (_isNwcMode) {
        await _payViaNwc(parsed, l10n);
      } else {
        await _payViaSpark(parsed, l10n);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppSnackbar.error(context, '${l10n.error}: $e');
      }
    }
  }

  Future<void> _payViaNwc(InputType parsed, AppLocalizations l10n) async {
    final nwcService = AppDI.get<NwcService>();
    String? bolt11;

    if (parsed is InputType_Bolt11Invoice) {
      bolt11 = parsed.field0.invoice.bolt11;
    } else if (parsed is InputType_LightningAddress) {
      bolt11 = await _lnAddressToBolt11(parsed.field0.address, l10n);
    }

    if (bolt11 == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final result = await nwcService.payInvoice(bolt11);
    if (!mounted) return;
    setState(() => _isLoading = false);
    result.fold(
      (_) {
        AppSnackbar.success(context, l10n.paymentSent);
        widget.onPaymentSuccess();
        Navigator.pop(context);
      },
      (error) => AppSnackbar.error(context, '${l10n.paymentFailed}: $error'),
    );
  }

  Future<String?> _lnAddressToBolt11(
      String address, AppLocalizations l10n) async {
    final amountSats = int.tryParse(_amountController.text.trim());
    if (amountSats == null || amountSats <= 0) {
      if (mounted) AppSnackbar.error(context, l10n.enterValidAmount);
      return null;
    }

    final parts = address.split('@');
    if (parts.length != 2) return null;
    try {
      final wellKnownUrl =
          Uri.parse('https://${parts[1]}/.well-known/lnurlp/${parts[0]}');
      final metaResp =
          await http.get(wellKnownUrl).timeout(const Duration(seconds: 10));
      if (metaResp.statusCode != 200) return null;

      final meta = jsonDecode(metaResp.body) as Map<String, dynamic>;
      final callback = meta['callback'] as String?;
      if (callback == null) return null;

      final invoiceUri = Uri.parse(callback).replace(
          queryParameters: {'amount': '${amountSats * 1000}'});
      final invoiceResp =
          await http.get(invoiceUri).timeout(const Duration(seconds: 10));
      if (invoiceResp.statusCode != 200) return null;

      final invoiceData =
          jsonDecode(invoiceResp.body) as Map<String, dynamic>;
      return invoiceData['pr'] as String?;
    } catch (_) {
      if (mounted) AppSnackbar.error(context, l10n.resolveAddressFailed);
      return null;
    }
  }

  Future<void> _payViaSpark(InputType parsed, AppLocalizations l10n) async {
    final sparkService = AppDI.get<SparkService>();
    String paymentRequest;

    if (parsed is InputType_Bolt11Invoice) {
      paymentRequest = parsed.field0.invoice.bolt11;
    } else if (parsed is InputType_LightningAddress) {
      paymentRequest = _inputController.text.trim();
    } else if (parsed is InputType_SparkAddress) {
      paymentRequest = parsed.field0.address;
    } else if (parsed is InputType_SparkInvoice) {
      paymentRequest = parsed.field0.invoice;
    } else if (parsed is InputType_LnurlPay) {
      paymentRequest = _inputController.text.trim();
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
        AppSnackbar.error(context, l10n.unrecognizedPaymentFormat);
      }
      return;
    }

    BigInt? amountOverride;
    if (_needsAmountField) {
      final sats = int.tryParse(_amountController.text.trim());
      if (sats == null || sats <= 0) {
        if (mounted) {
          setState(() => _isLoading = false);
          AppSnackbar.error(context, l10n.enterValidAmount);
        }
        return;
      }
      amountOverride = BigInt.from(sats);
    }

    final sdkResult = await sparkService.getOrConnectSdk();
    if (sdkResult.isError) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppSnackbar.error(context, '${l10n.error}: ${sdkResult.error}');
      }
      return;
    }
    final sdk = sdkResult.data!;

    try {
      final prepareResp = await sdk.prepareSendPayment(
        request: PrepareSendPaymentRequest(
          paymentRequest: PaymentRequest.input(input: paymentRequest),
          amount: amountOverride,
          tokenIdentifier: null,
          conversionOptions: null,
          feePolicy: null,
        ),
      );

      await sdk.sendPayment(
        request: SendPaymentRequest(prepareResponse: prepareResp),
      );

      if (mounted) {
        setState(() => _isLoading = false);
        AppSnackbar.success(context, l10n.paymentSent);
        widget.onPaymentSuccess();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppSnackbar.error(context, '${l10n.paymentFailed}: $e');
      }
    }
  }

  bool get _canPay {
    if (_isLoading || _isParsing || _parsedInput == null) return false;
    if (_needsAmountField) {
      final sats = int.tryParse(_amountController.text.trim());
      return sats != null && sats > 0;
    }
    return true;
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
          _buildParseStatus(context, colors, l10n),
          if (_needsAmountField) _buildAmountField(context, colors, l10n),
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
            child: PhosphorIcon(PhosphorIcons.x(),
                size: 20, color: colors.textPrimary),
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
                  icon: PhosphorIcons.qrCode(),
                  colors: colors,
                  onTap: _scanQrCode,
                ),
                const SizedBox(width: 6),
                _buildIconButton(
                  icon: PhosphorIcons.clipboardText(),
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

  Widget _buildParseStatus(
      BuildContext context, dynamic colors, AppLocalizations l10n) {
    if (_isParsing) {
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

    if (_parseError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          _parseError!,
          style: TextStyle(color: colors.error, fontSize: 13),
        ),
      );
    }

    if (_parsedInput == null) return const SizedBox.shrink();

    final fixedSats = _fixedAmountSats;
    final typeLabel = _inputTypeLabel;
    final desc = _description;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (typeLabel != null)
            Row(
              children: [
                PhosphorIcon(PhosphorIcons.checkCircle(),
                    size: 14, color: colors.success),
                const SizedBox(width: 6),
                Text(
                  typeLabel,
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          if (fixedSats != null) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${_formatSats(fixedSats)} sats',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (desc != null &&
              desc.isNotEmpty &&
              fixedSats == null &&
              _parsedInput is! InputType_LightningAddress) ...[
            const SizedBox(height: 4),
            Text(
              desc,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAmountField(
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
                controller: _amountController,
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
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
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
