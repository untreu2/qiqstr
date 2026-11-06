import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/theme_manager.dart';
import '../common/snackbar_widget.dart';

class PaymentDetailSheet extends StatefulWidget {
  final Map<String, dynamic> payment;

  const PaymentDetailSheet({super.key, required this.payment});

  static Future<void> show(
      BuildContext context, Map<String, dynamic> payment) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaymentDetailSheet(payment: payment),
    );
  }

  @override
  State<PaymentDetailSheet> createState() => _PaymentDetailSheetState();
}

class _PaymentDetailSheetState extends State<PaymentDetailSheet> {
  bool _detailsExpanded = false;

  Map<String, dynamic> get _tx => widget.payment;

  bool get _isIncoming => _tx['isIncoming'] as bool? ?? false;

  int get _amountSats => (_tx['amount'] as num? ?? 0).toInt();

  int get _feeSats => (_tx['fees'] as num? ?? 0).toInt();

  int? get _timestamp => _tx['timestamp'] as int?;

  String get _status => _tx['status'] as String? ?? 'completed';

  String? get _method => _tx['method'] as String?;

  String? get _description => _tx['description'] as String?;

  String? get _invoice => _tx['invoice'] as String?;

  String? get _preimage => _tx['preimage'] as String?;

  String? get _paymentHash => _tx['paymentHash'] as String?;

  String _formatSats(int sats) {
    final str = sats.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  String _formatTimestamp(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${pad(dt.month)}-${pad(dt.day)}  ${pad(dt.hour)}:${pad(dt.minute)}';
  }

  String _methodLabel(String? method) {
    switch (method) {
      case 'lightning':
        return 'Lightning';
      case 'spark':
        return 'Spark';
      case 'deposit':
        return 'On-chain deposit';
      case 'withdraw':
        return 'On-chain withdrawal';
      default:
        return method ?? '—';
    }
  }

  void _copy(BuildContext context, String value) {
    Clipboard.setData(ClipboardData(text: value));
    AppSnackbar.success(
        context, AppLocalizations.of(context)!.copiedToClipboard);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHandle(colors),
          const SizedBox(height: 20),
          _buildAmountRow(context, colors, l10n),
          const SizedBox(height: 20),
          _buildInfoRows(context, colors, l10n),
          if (_invoice != null || _preimage != null || _paymentHash != null) ...[
            const SizedBox(height: 4),
            _buildDetailsToggle(context, colors, l10n),
            if (_detailsExpanded) ...[
              const SizedBox(height: 8),
              _buildTechnicalDetails(context, colors, l10n),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildHandle(dynamic colors) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: colors.textSecondary.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildAmountRow(
      BuildContext context, dynamic colors, AppLocalizations l10n) {
    final isPending = _status == 'pending';
    final isFailed = _status == 'failed';

    Color statusColor;
    IconData statusIcon;
    if (isFailed) {
      statusColor = colors.error;
      statusIcon = PhosphorIcons.xCircle(PhosphorIconsStyle.fill);
    } else if (isPending) {
      statusColor = colors.accent;
      statusIcon = PhosphorIcons.clock(PhosphorIconsStyle.fill);
    } else if (_isIncoming) {
      statusColor = colors.success;
      statusIcon = PhosphorIcons.arrowDownLeft(PhosphorIconsStyle.fill);
    } else {
      statusColor = colors.textPrimary;
      statusIcon = PhosphorIcons.arrowUpRight(PhosphorIconsStyle.fill);
    }

    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(statusIcon, color: statusColor, size: 26),
        ),
        const SizedBox(height: 12),
        Text(
          '${_isIncoming ? '+' : '-'}${_formatSats(_amountSats)} sats',
          style: TextStyle(
            color: _isIncoming ? colors.success : colors.textPrimary,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        if (isPending || isFailed) ...[
          const SizedBox(height: 4),
          Text(
            isPending ? l10n.pendingTransaction : l10n.failed,
            style: TextStyle(color: statusColor, fontSize: 13),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoRows(
      BuildContext context, dynamic colors, AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: colors.overlayLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          if (_timestamp != null)
            _buildRow(
              colors: colors,
              label: l10n.date,
              value: _formatTimestamp(_timestamp!),
              isFirst: true,
            ),
          if (_feeSats > 0)
            _buildRow(
              colors: colors,
              label: l10n.fee,
              value: '${_formatSats(_feeSats)} sats',
            ),
          if (_method != null)
            _buildRow(
              colors: colors,
              label: l10n.method,
              value: _methodLabel(_method),
            ),
          if (_description != null && _description!.isNotEmpty)
            _buildRow(
              colors: colors,
              label: l10n.description,
              value: _description!,
              isLast: _invoice == null &&
                  _preimage == null &&
                  _paymentHash == null,
            ),
        ],
      ),
    );
  }

  Widget _buildRow({
    required dynamic colors,
    required String label,
    required String value,
    bool isFirst = false,
    bool isLast = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    color: colors.textSecondary.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(PhosphorIcons.copy(), size: 16, color: colors.textSecondary),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsToggle(
      BuildContext context, dynamic colors, AppLocalizations l10n) {
    return GestureDetector(
      onTap: () => setState(() => _detailsExpanded = !_detailsExpanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l10n.details,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _detailsExpanded
                  ? PhosphorIcons.caretUp()
                  : PhosphorIcons.caretDown(),
              size: 14,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicalDetails(
      BuildContext context, dynamic colors, AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: colors.overlayLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          if (_paymentHash != null)
            _buildCopyableRow(
              context: context,
              colors: colors,
              label: l10n.paymentHash,
              value: _paymentHash!,
              isFirst: true,
              isLast: _preimage == null && _invoice == null,
            ),
          if (_preimage != null)
            _buildCopyableRow(
              context: context,
              colors: colors,
              label: l10n.preimage,
              value: _preimage!,
              isLast: _invoice == null,
            ),
          if (_invoice != null)
            _buildCopyableRow(
              context: context,
              colors: colors,
              label: l10n.invoice,
              value: _invoice!,
              isLast: true,
            ),
        ],
      ),
    );
  }

  Widget _buildCopyableRow({
    required BuildContext context,
    required dynamic colors,
    required String label,
    required String value,
    bool isFirst = false,
    bool isLast = false,
  }) {
    final truncated = value.length > 20
        ? '${value.substring(0, 10)}…${value.substring(value.length - 8)}'
        : value;

    return GestureDetector(
      onTap: () => _copy(context, value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    color: colors.textSecondary.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                truncated,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.end,
              ),
            ),
            const SizedBox(width: 8),
            Icon(PhosphorIcons.copy(), size: 16, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}
