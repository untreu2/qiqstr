import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';

Future<void> showResetRelaysDialog({
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'This will reset all relays to their default values. Are you sure?',
            style: TextStyle(
              color: oppositeColors.textSecondary,
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
                color: oppositeColors.buttonPrimary,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, color: oppositeColors.buttonText, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Reset to Defaults',
                    style: TextStyle(
                      color: oppositeColors.buttonText,
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
                color: oppositeColors.overlayLight,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: oppositeColors.textPrimary,
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

