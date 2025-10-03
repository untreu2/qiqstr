import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:nostr/nostr.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../models/note_model.dart';
import '../../models/user_model.dart';
import '../../theme/theme_manager.dart';
import '../../core/di/app_di.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../services/nostr_service.dart';
import '../../services/relay_service.dart';
import '../../constants/relays.dart';

Future<void> _payZapWithWallet(
  BuildContext context,
  UserModel user,
  NoteModel note,
  int sats,
  String comment,
) async {
  final walletRepository = AppDI.get<WalletRepository>();
  const secureStorage = FlutterSecureStorage();

  try {
    // Check if wallet is connected
    if (!walletRepository.isConnected) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please connect your wallet first'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Show loading
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('Creating zap...'),
            ],
          ),
          duration: Duration(seconds: 30),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // Get private key for zap request event
    final privateKey = await secureStorage.read(key: 'privateKey');
    if (privateKey == null || privateKey.isEmpty) {
      throw Exception('Private key not found.');
    }

    // Validate lud16
    if (!user.lud16.contains('@')) {
      throw Exception('Invalid lightning address format.');
    }

    final parts = user.lud16.split('@');
    if (parts.length != 2 || parts.any((p) => p.isEmpty)) {
      throw Exception('Invalid lightning address format.');
    }

    final displayName = parts[0];
    final domain = parts[1];

    // Fetch LNURL-pay endpoint
    final uri = Uri.parse('https://$domain/.well-known/lnurlp/$displayName');
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('LNURL fetch failed with status: ${response.statusCode}');
    }

    final lnurlJson = jsonDecode(response.body);
    if (lnurlJson['allowsNostr'] != true || lnurlJson['nostrPubkey'] == null) {
      throw Exception('Recipient does not support zaps.');
    }

    final callback = lnurlJson['callback'];
    if (callback == null || callback.isEmpty) {
      throw Exception('Zap callback is missing.');
    }

    final lnurlBech32 = lnurlJson['lnurl'] ?? '';
    final amountMillisats = (sats * 1000).toString();
    final relays = relaySetMainSockets;

    if (relays.isEmpty) {
      throw Exception('No relays available for zap.');
    }

    // Convert user npub to hex format for zap (DataService pattern)
    String recipientPubkeyHex = user.pubkeyHex;
    if (user.pubkeyHex.startsWith('npub1')) {
      try {
        final keyData = Nip19.decodePubkey(user.pubkeyHex);
        recipientPubkeyHex = keyData;
      } catch (e) {
        if (kDebugMode) {
          if (kDebugMode) {
            print('[ZapDialog] Error converting npub to hex: $e');
          }
        }
        // Keep original if conversion fails
      }
    }

    // Create zap request event following DataService.sendZap pattern
    final List<List<String>> tags = [
      ['relays', ...relays.map((e) => e.toString())],
      ['amount', amountMillisats],
      ['p', recipientPubkeyHex], // Recipient's pubkey in hex format
    ];

    // Add LNURL if available
    if (lnurlBech32.isNotEmpty) {
      tags.add(['lnurl', lnurlBech32]);
    }

    // CRITICAL: Add note reference for proper zap attribution
    // This ensures the zap is tied to the specific note
    if (note.id.isNotEmpty) {
      tags.add(['e', note.id]);
      if (kDebugMode) {
        print('[ZapDialog] Added note reference to zap: ${note.id}');
      }
    }

    final zapRequest = NostrService.createZapRequestEvent(
      tags: tags,
      content: comment,
      privateKey: privateKey,
    );

    // Get invoice from LNURL-pay callback
    final encodedZap = Uri.encodeComponent(jsonEncode(NostrService.eventToJson(zapRequest)));
    final zapUrl = Uri.parse(
      '$callback?amount=$amountMillisats&nostr=$encodedZap${lnurlBech32.isNotEmpty ? '&lnurl=$lnurlBech32' : ''}',
    );

    final invoiceResponse = await http.get(zapUrl);
    if (invoiceResponse.statusCode != 200) {
      throw Exception('Zap callback failed: ${invoiceResponse.body}');
    }

    final invoiceJson = jsonDecode(invoiceResponse.body);
    final invoice = invoiceJson['pr'];
    if (invoice == null || invoice.toString().isEmpty) {
      throw Exception('Invoice not returned by zap server.');
    }

    // Pay the invoice using wallet
    final paymentResult = await walletRepository.payInvoice(invoice);

    if (paymentResult.isError) {
      throw Exception(paymentResult.error);
    }

    // CRITICAL: Since we pay with our wallet (not LNURL callback),
    // we need to manually create and publish the zap event (kind 9735)
    try {
      final webSocketManager = WebSocketManager.instance;

      // 1. Publish zap request event (kind 9734) to relays
      final serializedZapRequest = NostrService.serializeEvent(zapRequest);
      await webSocketManager.priorityBroadcast(serializedZapRequest);

      if (kDebugMode) {
        print('[ZapDialog] Zap request event (kind 9734) published for note: ${note.id}');
      }

      // 2. Since LNURL callback won't create zap event (we paid directly),
      // we manually create the zap event (kind 9735) like LNURL would
      final zapEvent = Event.from(
        kind: 9735, // Zap event
        tags: [
          ['bolt11', invoice],
          ['description', jsonEncode(NostrService.eventToJson(zapRequest))],
          ['p', recipientPubkeyHex],
          ['e', note.id], // Note reference
        ],
        content: comment, // Zap comment
        privkey: privateKey,
      );

      // 3. Publish the zap event to relays
      final serializedZapEvent = NostrService.serializeEvent(zapEvent);
      await webSocketManager.priorityBroadcast(serializedZapEvent);

      if (kDebugMode) {
        print('[ZapDialog] Zap event (kind 9735) published for note: ${note.id}');
      }
      if (kDebugMode) {
        print('[ZapDialog] Zap amount: $sats sats, preimage: ${paymentResult.data!.preimage}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[ZapDialog] Error creating/publishing zap event: $e');
      }
      // Continue anyway, payment was successful
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.flash_on, color: Colors.yellow, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Zapped $sats sats to ${user.name} on their note!'),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to zap: $e'),
          duration: const Duration(seconds: 3),
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.buttonPrimary,
                  foregroundColor: context.colors.background,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
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

                    _payZapWithWallet(context, user, note, sats, noteController.text.trim());
                  },
                  (error) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('Error loading user profile: $error'), duration: const Duration(seconds: 1)));
                  },
                );
              },
              child: const Text('Send'),
            ),
          ),
        ],
      ),
    ),
  );
}
