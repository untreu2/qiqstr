import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';
import '../common/common_buttons.dart';
import '../../../l10n/app_localizations.dart';

Future<void> showAddRelayDialog({
  required BuildContext context,
  required TextEditingController controller,
  required bool isLoading,
  required VoidCallback onAdd,
}) async {
  controller.clear();
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
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(modalContext).viewInsets.bottom + 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
            ),
            decoration: InputDecoration(
              hintText: l10n.relayUrlHint,
              hintStyle: TextStyle(
                color: colors.textSecondary,
                fontSize: 15,
              ),
              filled: true,
              fillColor: colors.overlayLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: SecondaryButton(
              label: l10n.addRelay,
              onPressed: isLoading ? null : onAdd,
              isLoading: isLoading,
              size: ButtonSize.large,
            ),
          ),
        ],
      ),
    ),
  );
}
