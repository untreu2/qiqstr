import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';
import '../common/common_buttons.dart';
import '../../../l10n/app_localizations.dart';

Future<void> showReportUserDialog({
  required BuildContext context,
  required String userName,
  required void Function(String reportType) onConfirm,
}) async {
  final colors = context.colors;
  final l10n = AppLocalizations.of(context)!;

  String? selectedReason;

  final reasons = <String, String>{
    'spam': l10n.reportReasonSpam,
    'nudity': l10n.reportReasonNudity,
    'profanity': l10n.reportReasonProfanity,
    'illegal': l10n.reportReasonIllegal,
    'impersonation': l10n.reportReasonImpersonation,
    'other': l10n.reportReasonOther,
  };

  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: colors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalContext) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
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
              l10n.reportUser(userName),
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.reportUserDescription,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ...reasons.entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () {
                      setSheetState(() {
                        selectedReason = entry.key;
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: selectedReason == entry.key
                            ? colors.error.withValues(alpha: 0.1)
                            : colors.overlayLight,
                        borderRadius: BorderRadius.circular(12),
                        border: selectedReason == entry.key
                            ? Border.all(
                                color: colors.error.withValues(alpha: 0.4))
                            : null,
                      ),
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          color: selectedReason == entry.key
                              ? colors.error
                              : colors.textPrimary,
                          fontSize: 15,
                          fontWeight: selectedReason == entry.key
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                )),
            const SizedBox(height: 8),
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
                    label: l10n.report,
                    onPressed: selectedReason != null
                        ? () {
                            Navigator.pop(modalContext);
                            onConfirm(selectedReason!);
                          }
                        : null,
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
    ),
  );
}
