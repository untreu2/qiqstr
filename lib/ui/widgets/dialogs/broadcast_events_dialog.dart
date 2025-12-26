import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';
import '../common/common_buttons.dart';

Future<bool> showBroadcastEventsDialog({
  required BuildContext context,
  String? relayUrl,
  List<String>? relayUrls,
  int? relayCount,
}) async {
  final colors = context.colors;
  final isMultiple = relayUrls != null && relayUrls.length > 1;
  final count = relayCount ?? (relayUrls?.length ?? (relayUrl != null ? 1 : 0));
  
  return await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: colors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalContext) => Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(modalContext).viewInsets.bottom + 40,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Broadcast all events?',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isMultiple
                ? 'Would you like to broadcast all your events to these $count new relays?'
                : 'Would you like to broadcast all your events to this new relay?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 15,
            ),
          ),
          if (relayUrl != null && !isMultiple) ...[
            const SizedBox(height: 8),
            Text(
              relayUrl,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 13,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'No',
                  onPressed: () => Navigator.pop(modalContext, false),
                  size: ButtonSize.large,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SecondaryButton(
                  label: 'Yes',
                  icon: Icons.send,
                  onPressed: () => Navigator.pop(modalContext, true),
                  size: ButtonSize.large,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  ) ?? false;
}

