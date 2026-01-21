import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:ndk/ndk.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../data/services/data_service.dart';
import '../../../data/services/nostr_service.dart';
import '../../../data/services/relay_service.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import '../../../constants/relays.dart';
import '../common/snackbar_widget.dart';
import '../common/common_buttons.dart';
import '../common/custom_input_field.dart';

Future<bool> _payZapWithWallet(
  BuildContext context,
  Map<String, dynamic> user,
  Map<String, dynamic> note,
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
      AppSnackbar.info(context, 'Processing payment...',
          duration: const Duration(seconds: 5));
    }

    final privateKey = await secureStorage.read(key: 'privateKey');
    if (privateKey == null || privateKey.isEmpty) {
      throw Exception('Private key not found.');
    }

    final lud16 = user['lud16'] as String? ?? '';
    if (!lud16.contains('@')) {
      throw Exception('Invalid lightning address format.');
    }

    final parts = lud16.split('@');
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

    final userPubkeyHex = user['pubkeyHex'] as String? ?? '';
    String recipientPubkeyHex = userPubkeyHex;
    if (userPubkeyHex.startsWith('npub1')) {
      try {
        final keyData = Nip19.decode(userPubkeyHex);
        recipientPubkeyHex = keyData;
      } catch (e) {
        if (kDebugMode) {
          print('[ZapDialog] Error converting npub to hex: $e');
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

    final noteId = note['id'] as String? ?? '';
    if (noteId.isNotEmpty) {
      tags.add(['e', noteId]);
      if (kDebugMode) {
        print('[ZapDialog] Added note reference to zap: $noteId');
      }
    }

    final zapRequest = NostrService.createZapRequestEvent(
      tags: tags,
      content: comment,
      privateKey: privateKey,
    );

    final encodedZap =
        Uri.encodeComponent(jsonEncode(NostrService.eventToJson(zapRequest)));
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

    debugPrint(
        '[ZapDialog] About to pay invoice: ${invoice.substring(0, 20)}...');
    final paymentResult = await walletRepository.payInvoice(invoice);

    debugPrint(
        '[ZapDialog] Payment result: ${paymentResult.isSuccess ? 'SUCCESS' : 'FAILED'}');
    if (paymentResult.isError) {
      debugPrint('[ZapDialog] Payment error: ${paymentResult.error}');
      throw Exception(paymentResult.error);
    }

    debugPrint('[ZapDialog] Payment successful, result: ${paymentResult.data}');

    // Payment successful! Show success immediately
    if (context.mounted) {
      final userName = user['name'] as String? ?? 'User';
      AppSnackbar.hide(context);
      AppSnackbar.success(context, 'Zapped $sats sats to $userName!',
          duration: const Duration(seconds: 2));
    }

    // Publish Nostr events in the background without affecting success status
    unawaited(_publishZapEventsAsync(zapRequest, invoice, recipientPubkeyHex,
        note, comment, privateKey, sats, paymentResult));

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
  Nip01Event zapRequest,
  String invoice,
  String recipientPubkeyHex,
  Map<String, dynamic> note,
  String comment,
  String privateKey,
  int sats,
  dynamic paymentResult,
) async {
  try {
    final webSocketManager = WebSocketManager.instance;
    final noteId = note['id'] as String? ?? '';

    final serializedZapRequest = NostrService.serializeEvent(zapRequest);
    await webSocketManager.priorityBroadcast(serializedZapRequest);

    if (kDebugMode) {
      print(
          '[ZapDialog] Zap request event (kind 9734) published for note: $noteId');
    }

    final publicKey = Bip340.getPublicKey(privateKey);
    final zapEvent = Nip01Event(
      pubKey: publicKey,
      kind: 9735,
      tags: [
        ['bolt11', invoice],
        ['description', jsonEncode(NostrService.eventToJson(zapRequest))],
        ['p', recipientPubkeyHex],
        ['e', noteId],
      ],
      content: comment,
    );
    zapEvent.sig = Bip340.sign(zapEvent.id, privateKey);

    final serializedZapEvent = NostrService.serializeEvent(zapEvent);
    await webSocketManager.priorityBroadcast(serializedZapEvent);

    if (kDebugMode) {
      print('[ZapDialog] Zap event (kind 9735) published for note: $noteId');
    }

    // Mark this zap event as user-published to prevent self-processing
    final nostrDataService = AppDI.get<DataService>();
    nostrDataService.markZapAsUserPublished(zapEvent.id);
    if (kDebugMode) {
      final paymentData = paymentResult.data as Map<String, dynamic>?;
      final preimage = paymentData?['preimage'] as String?;
      print('[ZapDialog] Zap amount: $sats sats, preimage: $preimage');
    }
  } catch (e) {
    if (kDebugMode) {
      print('[ZapDialog] Error creating/publishing zap event: $e');
    }
  }
}

Future<void> _processZapPayment(
  BuildContext context,
  Map<String, dynamic> note,
  int sats,
  String comment,
) async {
  try {
    final userRepository = AppDI.get<UserRepository>();
    final noteAuthor = note['author'] as String? ?? '';
    final userResult = await userRepository.getUserProfile(noteAuthor);

    await userResult.fold(
      (user) async {
        final lud16 = user['lud16'] as String? ?? '';
        if (lud16.isEmpty) {
          if (context.mounted) {
            AppSnackbar.error(
                context, 'User does not have a lightning address configured.',
                duration: const Duration(seconds: 1));
          }
          return;
        }

        await _payZapWithWallet(context, user, note, sats, comment);
      },
      (error) {
        if (context.mounted) {
          AppSnackbar.error(context, 'Error loading user profile: $error',
              duration: const Duration(seconds: 1));
        }
      },
    );
  } catch (e) {
    if (context.mounted) {
      AppSnackbar.error(context, 'Failed to process zap: $e',
          duration: const Duration(seconds: 1));
    }
  }
}

Future<void> processZapDirectly(
  BuildContext context,
  Map<String, dynamic> note,
  int sats,
) async {
  await _processZapPayment(context, note, sats, '');
}

Future<Map<String, dynamic>> showZapDialog({
  required BuildContext context,
  required Map<String, dynamic> note,
}) async {
  final amountController = TextEditingController(text: '21');
  final noteController = TextEditingController();
  final colors = context.colors;

  final result = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: colors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalContext) => StatefulBuilder(
      builder: (context, setState) {
        return Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(modalContext).viewInsets.bottom + 40,
              top: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomInputField(
                controller: amountController,
                keyboardType: TextInputType.number,
                labelText: 'Amount (sats)',
                fillColor: colors.inputFill,
              ),
              const SizedBox(height: 16),
              CustomInputField(
                controller: noteController,
                labelText: 'Comment (Optional)',
                fillColor: colors.inputFill,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: SecondaryButton(
                  label: 'Send',
                  onPressed: () {
                    final sats = int.tryParse(amountController.text.trim());
                    if (sats == null || sats <= 0) {
                      AppSnackbar.error(modalContext, 'Enter a valid amount',
                          duration: const Duration(seconds: 1));
                      return;
                    }

                    Navigator.pop(modalContext, {
                      'success': true,
                      'amount': sats,
                    });

                    unawaited(_processZapPayment(
                        context, note, sats, noteController.text.trim()));
                  },
                  size: ButtonSize.large,
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
