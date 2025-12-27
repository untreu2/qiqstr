import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';
import '../common/common_buttons.dart';

Future<bool> showCopyKeyWarningDialog({
  required BuildContext context,
  required String keyType,
}) async {
  final colors = context.colors;
  final result = await showModalBottomSheet<bool>(
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
            'Warning!',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'You can use this to import your account into qiqstr or other apps that use the Nostr protocol. Never share it with anyone.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.pop(modalContext, false),
                  size: ButtonSize.large,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SecondaryButton(
                  label: 'Copy',
                  onPressed: () => Navigator.pop(modalContext, true),
                  size: ButtonSize.large,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

