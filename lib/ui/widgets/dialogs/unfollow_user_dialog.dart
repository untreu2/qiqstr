import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';
import '../common/common_buttons.dart';
import '../../../l10n/app_localizations.dart';

Future<void> showUnfollowUserDialog({
  required BuildContext context,
  required String userName,
  required VoidCallback onConfirm,
}) async {
  final colors = context.colors;
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet(
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
            l10n.unfollowUser(userName),
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: l10n.cancel,
                  onPressed: () => Navigator.pop(modalContext),
                  size: ButtonSize.large,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SecondaryButton(
                  label: l10n.unfollow,
                  onPressed: () {
                    Navigator.pop(modalContext);
                    onConfirm();
                  },
                  backgroundColor: colors.error.withValues(alpha: 0.1),
                  foregroundColor: colors.error,
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
