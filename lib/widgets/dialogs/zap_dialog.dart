import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:nostr/nostr.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../models/note_model.dart';
import '../../models/user_model.dart';
import '../../theme/theme_manager.dart';
import '../../core/di/app_di.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../data/services/nostr_data_service.dart';
import '../../services/nostr_service.dart';
import '../../services/relay_service.dart';
import '../../constants/relays.dart';
import '../snackbar_widget.dart';

Future<bool> _payZapWithWallet(
  BuildContext context,
  UserModel user,
  NoteModel note,
  int sats,
  String comment,
) async {
  final walletRepository = AppDI.get<WalletRepository>();
  const secureStorage = FlutterSecureStorage();

  try {
    if (!walletRepository.isConnected) {
      if (context.mounted) {
        AppSnackbar.warning(context, 'Please connect your wallet first');
      }
      return false;
    }

    if (context.mounted) {
      AppSnackbar.info(context, 'Processing payment...', duration: const Duration(seconds: 5));
    }

    final privateKey = await secureStorage.read(key: 'privateKey');
    if (privateKey == null || privateKey.isEmpty) {
      throw Exception('Private key not found.');
    }

    if (!user.lud16.contains('@')) {
      throw Exception('Invalid lightning address format.');
    }

    final parts = user.lud16.split('@');
    if (parts.length != 2 || parts.any((p) => p.isEmpty)) {
      throw Exception('Invalid lightning address format.');
    }

    final displayName = parts[0];
    final domain = parts[1];

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
      }
    }

    final List<List<String>> tags = [
      ['relays', ...relays.map((e) => e.toString())],
      ['amount', amountMillisats],
      ['p', recipientPubkeyHex],
    ];

    if (lnurlBech32.isNotEmpty) {
      tags.add(['lnurl', lnurlBech32]);
    }

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

    debugPrint('[ZapDialog] About to pay invoice: ${invoice.substring(0, 20)}...');
    final paymentResult = await walletRepository.payInvoice(invoice);

    debugPrint('[ZapDialog] Payment result: ${paymentResult.isSuccess ? 'SUCCESS' : 'FAILED'}');
    if (paymentResult.isError) {
      debugPrint('[ZapDialog] Payment error: ${paymentResult.error}');
      throw Exception(paymentResult.error);
    }

    debugPrint('[ZapDialog] Payment successful, result: ${paymentResult.data}');

    // Payment successful! Show success immediately
    if (context.mounted) {
      AppSnackbar.hide(context);
      AppSnackbar.success(context, 'Zapped $sats sats to ${user.name}!', duration: const Duration(seconds: 2));
    }

    // Publish Nostr events in the background without affecting success status
    unawaited(_publishZapEventsAsync(zapRequest, invoice, recipientPubkeyHex, note, comment, privateKey, sats, paymentResult));

    return true;
  } catch (e) {
    if (context.mounted) {
      AppSnackbar.hide(context);
      AppSnackbar.error(context, 'Failed to zap: $e');
    }
    return false;
  }
}

Future<void> _publishZapEventsAsync(
  Event zapRequest,
  String invoice,
  String recipientPubkeyHex,
  NoteModel note,
  String comment,
  String privateKey,
  int sats,
  dynamic paymentResult,
) async {
  try {
    final webSocketManager = WebSocketManager.instance;

    final serializedZapRequest = NostrService.serializeEvent(zapRequest);
    await webSocketManager.priorityBroadcast(serializedZapRequest);

    if (kDebugMode) {
      print('[ZapDialog] Zap request event (kind 9734) published for note: ${note.id}');
    }

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

    final serializedZapEvent = NostrService.serializeEvent(zapEvent);
    await webSocketManager.priorityBroadcast(serializedZapEvent);

    if (kDebugMode) {
      print('[ZapDialog] Zap event (kind 9735) published for note: ${note.id}');
    }

    // Mark this zap event as user-published to prevent self-processing
    final nostrDataService = AppDI.get<NostrDataService>();
    nostrDataService.markZapAsUserPublished(zapEvent.id);
    if (kDebugMode) {
      print('[ZapDialog] Zap amount: $sats sats, preimage: ${paymentResult.data?.preimage}');
    }
  } catch (e) {
    if (kDebugMode) {
      print('[ZapDialog] Error creating/publishing zap event: $e');
    }
  }
}

Future<void> _processZapPayment(
  BuildContext context,
  NoteModel note,
  int sats,
  String comment,
) async {
  try {
    final userRepository = AppDI.get<UserRepository>();
    final userResult = await userRepository.getUserProfile(note.author);

    await userResult.fold(
      (user) async {
        if (user.lud16.isEmpty) {
          AppSnackbar.error(context, 'User does not have a lightning address configured.', duration: const Duration(seconds: 1));
          return;
        }

        await _payZapWithWallet(context, user, note, sats, comment);
      },
      (error) {
        AppSnackbar.error(context, 'Error loading user profile: $error', duration: const Duration(seconds: 1));
      },
    );
  } catch (e) {
    AppSnackbar.error(context, 'Failed to process zap: $e', duration: const Duration(seconds: 1));
  }
}

Future<Map<String, dynamic>> showZapDialog({
  required BuildContext context,
  required NoteModel note,
}) async {
  final amountController = TextEditingController(text: '21');
  final noteController = TextEditingController();

  final result = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    builder: (modalContext) => StatefulBuilder(
      builder: (context, setState) {
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(modalContext).viewInsets.bottom + 40, top: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Amount (sats)',
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                  ),
                  filled: true,
                  fillColor: context.colors.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: noteController,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Comment (Optional)',
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                  ),
                  filled: true,
                  fillColor: context.colors.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  final sats = int.tryParse(amountController.text.trim());
                  if (sats == null || sats <= 0) {
                    AppSnackbar.error(modalContext, 'Enter a valid amount', duration: const Duration(seconds: 1));
                    return;
                  }

                  Navigator.pop(modalContext, {
                    'success': true,
                    'amount': sats,
                  });

                  unawaited(_processZapPayment(context, note, sats, noteController.text.trim()));
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.colors.buttonPrimary,
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Text(
                    'Send',
                    style: TextStyle(
                      color: context.colors.buttonText,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  return result ?? {'success': false, 'amount': 0};
}
