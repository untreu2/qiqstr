import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';
import '../common/common_buttons.dart';

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
          SecondaryButton(
            label: 'Reset to Defaults',
            icon: Icons.refresh,
            onPressed: () {
              Navigator.pop(modalContext);
              onConfirm();
            },
            size: ButtonSize.large,
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(modalContext),
            size: ButtonSize.large,
          ),
        ],
      ),
    ),
  );
}
