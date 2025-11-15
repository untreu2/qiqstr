import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';

Future<void> showAddRelayDialog({
  required BuildContext context,
  required TextEditingController controller,
  required bool isLoading,
  required VoidCallback onAdd,
}) async {
  controller.clear();
  final colors = context.colors;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.background,
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
              color: colors.textPrimary,
              fontSize: 15,
            ),
            decoration: InputDecoration(
              hintText: 'wss://relay.example.com',
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: isLoading ? null : onAdd,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(40),
              ),
              child: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(colors.background),
                      ),
                    )
                  : Text(
                      'Add Relay',
                      style: TextStyle(
                        color: colors.background,
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
