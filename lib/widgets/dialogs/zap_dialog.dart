import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/providers/wallet_provider.dart';
import 'package:qiqstr/providers/interactions_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../theme/theme_manager.dart';

Future<String> _getCurrentUserNpub() async {
  try {
    const secureStorage = FlutterSecureStorage();
    final npub = await secureStorage.read(key: 'npub');
    return npub ?? '';
  } catch (e) {
    return '';
  }
}

Future<void> _processZapPayment(
  BuildContext context,
  DataService dataService,
  WalletProvider walletProvider,
  UserModel user,
  NoteModel note,
  int sats,
  String currentUserNpub,
  String comment,
) async {
  try {
    // Step 1: Generate the zap invoice using DataService (this creates and publishes the zap request to relays)
    final invoice = await dataService.sendZap(
      recipientPubkey: user.npub,
      lud16: user.lud16,
      noteId: note.id,
      amountSats: sats,
      content: comment,
    );

    // Step 2: Pay the invoice using WalletProvider
    await walletProvider.payInvoice(invoice);

    // Step 3: Check payment status
    if (walletProvider.status?.toLowerCase().contains('success') == true) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('⚡ Zap sent successfully!'), duration: Duration(seconds: 2)));
      }

      // Refresh wallet balance after successful payment
      await walletProvider.fetchBalance();
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Payment failed: ${walletProvider.status}'), duration: const Duration(seconds: 2)));
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Zap failed: $e'), duration: const Duration(seconds: 2)));
    }
  }
}

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
          Consumer<WalletProvider>(
            builder: (context, walletProvider, child) {
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.buttonPrimary,
                    foregroundColor: context.colors.background,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                onPressed: () async {
                  final sats = int.tryParse(amountController.text.trim());
                  if (sats == null || sats <= 0) {
                    ScaffoldMessenger.of(modalContext)
                        .showSnackBar(const SnackBar(content: Text('Enter a valid amount'), duration: Duration(seconds: 2)));
                    return;
                  }

                  // Check if wallet is connected
                  final isLoggedIn = await walletProvider.isLoggedIn();
                  if (!isLoggedIn) {
                    ScaffoldMessenger.of(modalContext)
                        .showSnackBar(const SnackBar(content: Text('Please connect your wallet first'), duration: Duration(seconds: 2)));
                    return;
                  }

                  Navigator.pop(modalContext);

                  // Get user profile for validation
                  final profile = await dataService.getCachedUserProfile(note.author);
                  final user = UserModel.fromCachedProfile(note.author, profile);

                  if (user.lud16.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('User does not have a lightning address configured.'), duration: Duration(seconds: 2)));
                    return;
                  }

                  // Get current user npub for optimistic update
                  final currentUserNpub = await _getCurrentUserNpub();
                  if (currentUserNpub.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not get current user information'), duration: Duration(seconds: 2)));
                    return;
                  }

                  // Show processing message
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('⚡ Processing zap...'), duration: Duration(seconds: 1)));

                  // Process payment in background
                  _processZapPayment(context, dataService, walletProvider, user, note, sats, currentUserNpub, noteController.text.trim());
                },
                child: const Text('⚡ Zap'),
              );
            },
          ),
        ],
      ),
    ),
  );
}
