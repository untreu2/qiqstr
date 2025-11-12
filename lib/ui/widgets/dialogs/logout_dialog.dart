import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';
import '../common_buttons.dart';

Future<void> showLogoutDialog({
  required BuildContext context,
  required VoidCallback onConfirm,
}) async {
  final themeManager = context.themeManager;
  final oppositeColors = themeManager?.isDarkMode == true 
      ? AppThemeColors.light() 
      : AppThemeColors.dark();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: oppositeColors.background,
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
            'Are you sure you want to logout?',
            style: TextStyle(
              color: oppositeColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'IF YOU HAVEN\'T SAVED YOUR SEED PHRASE, YOU WILL LOSE YOUR ACCOUNT FOREVER.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oppositeColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w400,
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
                  label: 'Logout',
                  onPressed: () {
                    Navigator.pop(modalContext);
                    onConfirm();
                  },
                  backgroundColor: oppositeColors.error.withValues(alpha: 0.1),
                  foregroundColor: oppositeColors.error,
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

