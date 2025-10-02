import 'package:flutter/material.dart';
import '../../models/note_model.dart';
import '../../models/user_model.dart';
import '../../theme/theme_manager.dart';
import '../../core/di/app_di.dart';
import '../../data/repositories/user_repository.dart';

Future<void> _generateAndCopyZapInvoice(
  BuildContext context,
  UserModel user,
  NoteModel note,
  int sats,
  String comment,
) async {
  try {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(' Zap invoice copied to clipboard!'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate zap invoice: $e'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }
}

Future<void> showZapDialog({
  required BuildContext context,
  required NoteModel note,
}) async {
  final amountController = TextEditingController(text: '21');
  final noteController = TextEditingController();

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (modalContext) => Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(modalContext).viewInsets.bottom + 40, top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Amount (sats)',
              labelStyle: TextStyle(color: context.colors.secondary),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: context.colors.secondary)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: context.colors.textPrimary)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteController,
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Comment... (Optional)',
              labelStyle: TextStyle(color: context.colors.secondary),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: context.colors.secondary)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: context.colors.textPrimary)),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.buttonPrimary,
                foregroundColor: context.colors.background,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            onPressed: () async {
              final sats = int.tryParse(amountController.text.trim());
              if (sats == null || sats <= 0) {
                ScaffoldMessenger.of(modalContext)
                    .showSnackBar(const SnackBar(content: Text('Enter a valid amount'), duration: Duration(seconds: 1)));
                return;
              }

              Navigator.pop(modalContext);

              // Get user profile for the note author
              final userRepository = AppDI.get<UserRepository>();
              final userResult = await userRepository.getUserProfile(note.author);

              userResult.fold(
                (user) {
                  if (user.lud16.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('User does not have a lightning address configured.'), duration: Duration(seconds: 1)));
                    return;
                  }

                  _generateAndCopyZapInvoice(context, user, note, sats, noteController.text.trim());
                },
                (error) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Error loading user profile: $error'), duration: const Duration(seconds: 1)));
                },
              );
            },
            child: const Text(' Generate Zap Invoice'),
          ),
        ],
      ),
    ),
  );
}
