import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';
import '../common_buttons.dart';

Future<void> showAddRelayDialog({
  required BuildContext context,
  required TextEditingController controller,
  required bool isLoading,
  required VoidCallback onAdd,
}) async {
  controller.clear();
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
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(modalContext).viewInsets.bottom + 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(
              color: oppositeColors.textPrimary,
              fontSize: 15,
            ),
            decoration: InputDecoration(
              hintText: 'wss://relay.example.com',
              hintStyle: TextStyle(
                color: oppositeColors.textSecondary,
                fontSize: 15,
              ),
              filled: true,
              fillColor: oppositeColors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Add Relay',
              icon: Icons.add,
              onPressed: isLoading ? null : onAdd,
              isLoading: isLoading,
              size: ButtonSize.large,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SecondaryButton(
              label: 'Cancel',
              onPressed: () => Navigator.pop(modalContext),
              backgroundColor: oppositeColors.overlayLight,
              foregroundColor: oppositeColors.textPrimary,
              size: ButtonSize.large,
            ),
          ),
        ],
      ),
    ),
  );
}

