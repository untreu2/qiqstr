import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';
import '../common/common_buttons.dart';
import '../../../l10n/app_localizations.dart';

Future<void> showResetRelaysDialog({
  required BuildContext context,
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.resetRelaysConfirm,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: SecondaryButton(
              label: l10n.resetToDefaults,
              icon: Icons.refresh,
              onPressed: () {
                Navigator.pop(modalContext);
                onConfirm();
              },
              size: ButtonSize.large,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SecondaryButton(
              label: l10n.cancel,
              onPressed: () => Navigator.pop(modalContext),
              size: ButtonSize.large,
            ),
          ),
        ],
      ),
    ),
  );
}
