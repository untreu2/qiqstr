import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/data_service.dart';
import '../../colors.dart';

Future<void> showZapDialog({
  required BuildContext context,
  required DataService dataService,
  required NoteModel note,
}) async {
  final amountController = TextEditingController(text: '21');
  final noteController = TextEditingController();

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true, 
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (modalContext) => Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          
          bottom: MediaQuery.of(modalContext).viewInsets.bottom + 40,
          top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Amount (sats)',
              labelStyle: TextStyle(color: AppColors.secondary),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.secondary)),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Comment... (Optional)',
              labelStyle: TextStyle(color: AppColors.secondary),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.secondary)),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary)),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.buttonPrimary,
                foregroundColor: AppColors.background,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            onPressed: () async {
              final sats = int.tryParse(amountController.text.trim());
              if (sats == null || sats <= 0) {
                
                ScaffoldMessenger.of(modalContext).showSnackBar(const SnackBar(
                    content: Text('Enter a valid amount'),
                    duration: Duration(seconds: 2)));
                return;
              }
              Navigator.pop(modalContext); 

              try {
                
                
                
                final profile = await dataService.getCachedUserProfile(note.author);
                
                
                final user = UserModel.fromCachedProfile(note.author, profile);

                if (user.lud16.isEmpty) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('User does not have a lightning address configured.'),
                      duration: Duration(seconds: 2)));
                  return;
                }

                final invoice = await dataService.sendZap(
                  recipientPubkey: user.npub,
                  lud16: user.lud16,
                  noteId: note.id,
                  amountSats: sats,
                  content: noteController.text.trim(),
                );
                await Clipboard.setData(ClipboardData(text: invoice));
                
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('⚡ Copied!'),
                    duration: Duration(seconds: 2)));
              } catch (e) {
                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Zap failed: $e'),
                    duration: const Duration(seconds: 2)));
              }
            },
            child: const Text('Copy to send'),
          ),
        ],
      ),
    ),
  );
}
