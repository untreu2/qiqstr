import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';
import '../common_buttons.dart';

Future<void> showUnfollowUserDialog({
  required BuildContext context,
  required String userName,
  required VoidCallback onConfirm,
}) async {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
            'Unfollow $userName?',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.pop(modalContext),
                  size: ButtonSize.large,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SecondaryButton(
                  label: 'Unfollow',
                  onPressed: () {
                    Navigator.pop(modalContext);
                    onConfirm();
                  },
                  backgroundColor: context.colors.error.withValues(alpha: 0.1),
                  foregroundColor: context.colors.error,
                  size: ButtonSize.large,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

