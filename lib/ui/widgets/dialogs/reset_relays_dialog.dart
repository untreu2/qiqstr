import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';

Future<void> showResetRelaysDialog({
  required BuildContext context,
  required VoidCallback onConfirm,
}) async {
  final colors = context.colors;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalContext) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'This will reset all relays to their default values. Are you sure?',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              Navigator.pop(modalContext);
              onConfirm();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accentBright,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, color: colors.background, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Reset to Defaults',
                    style: TextStyle(
                      color: colors.background,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => Navigator.pop(modalContext),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.overlayLight,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

