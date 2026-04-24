import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/nwc_service.dart';
import '../../../data/services/spark_service.dart';
import '../../../data/sync/sync_service.dart';
import '../../../src/rust/api/events.dart' as rust_events;
import '../../../data/services/auth_service.dart';
import '../common/snackbar_widget.dart';
import '../common/common_buttons.dart';
import '../common/custom_input_field.dart';
import '../../../l10n/app_localizations.dart';

Future<bool> _payZapWithWallet(
  BuildContext context,
  Map<String, dynamic> user,
  Map<String, dynamic> note,
  int sats,
  String comment,
) async {
  final nwcService = AppDI.get<NwcService>();

  if (nwcService.isActive) {
    return _payZapWithNwc(context, user, note, sats, comment);
  }

  return _payZapWithSpark(context, user, note, sats, comment);
}

Future<bool> _payZapWithNwc(
  BuildContext context,
  Map<String, dynamic> user,
  Map<String, dynamic> note,
  int sats,
  String comment,
) async {
  final nwcService = AppDI.get<NwcService>();
  const secureStorage = FlutterSecureStorage();

  try {
    final l10n = AppLocalizations.of(context);

    final hasConnection = await nwcService.hasConnection();
    if (!hasConnection) {
      if (context.mounted) {
        AppSnackbar.warning(
            context,
            l10n?.pleaseConnectWalletFirst ??
                'Please connect your wallet first');
      }
      return false;
    }

    if (context.mounted) {
      AppSnackbar.info(
          context, l10n?.processingPayment ?? 'Processing payment...',
          duration: const Duration(seconds: 5));
    }

    final privateKey = await secureStorage.read(key: 'privateKey');
    if (privateKey == null || privateKey.isEmpty) {
      throw Exception('Private key not found.');
    }

    final invoice = await _buildZapInvoice(user, note, sats, comment);
    if (invoice == null) return false;

    debugPrint(
        '[ZapDialog] Paying invoice via NWC: ${invoice.substring(0, 20)}...');
    final paymentResult = await nwcService.payInvoice(invoice);

    if (paymentResult.isError) {
      throw Exception(paymentResult.error);
    }

    if (context.mounted) {
      final userName = user['name'] as String? ?? (l10n?.user ?? 'User');
      AppSnackbar.hide(context);
      AppSnackbar.success(
          context,
          l10n?.zappedSatsToUser(sats, userName) ??
              'Zapped $sats sats to $userName!',
          duration: const Duration(seconds: 2));
    }

    unawaited(_publishZapEventsAsync(
        await _buildZapRequest(user, note, sats, comment),
        invoice,
        _toHex(user['pubkey'] as String? ?? ''),
        note,
        comment,
        await secureStorage.read(key: 'privateKey') ?? '',
        sats,
        paymentResult));

    return true;
  } catch (e) {
    if (context.mounted) {
      final l10n = AppLocalizations.of(context);
      AppSnackbar.hide(context);
      AppSnackbar.error(context, l10n?.failedToZap ?? 'Failed to zap');
    }
    return false;
  }
}

Future<bool> _payZapWithSpark(
  BuildContext context,
  Map<String, dynamic> user,
  Map<String, dynamic> note,
  int sats,
  String comment,
) async {
  final sparkService = AppDI.get<SparkService>();
  const secureStorage = FlutterSecureStorage();

  try {
    final l10n = AppLocalizations.of(context);

    final isConnectedResult = await sparkService.isConnected();
    if (!isConnectedResult.isSuccess || isConnectedResult.data != true) {
      if (context.mounted) {
        AppSnackbar.warning(
            context,
            l10n?.pleaseConnectWalletFirst ??
                'Please connect your wallet first');
      }
      return false;
    }

    if (context.mounted) {
      AppSnackbar.info(
          context, l10n?.processingPayment ?? 'Processing payment...',
          duration: const Duration(seconds: 5));
    }

    final privateKey = await secureStorage.read(key: 'privateKey');
    if (privateKey == null || privateKey.isEmpty) {
      throw Exception('Private key not found.');
    }

    final invoice = await _buildZapInvoice(user, note, sats, comment);
    if (invoice == null) return false;

    debugPrint(
        '[ZapDialog] Paying invoice via Spark: ${invoice.substring(0, 20)}...');
    final paymentResult = await sparkService.payLightningInvoice(invoice);

    if (paymentResult.isError) {
      throw Exception(paymentResult.error);
    }

    if (context.mounted) {
      final userName = user['name'] as String? ?? (l10n?.user ?? 'User');
      AppSnackbar.hide(context);
      AppSnackbar.success(
          context,
          l10n?.zappedSatsToUser(sats, userName) ??
              'Zapped $sats sats to $userName!',
          duration: const Duration(seconds: 2));
    }

    unawaited(_publishZapEventsAsync(
        await _buildZapRequest(user, note, sats, comment),
        invoice,
        _toHex(user['pubkey'] as String? ?? ''),
        note,
        comment,
        privateKey,
        sats,
        paymentResult));

    return true;
  } catch (e) {
    if (context.mounted) {
      final l10n = AppLocalizations.of(context);
      AppSnackbar.hide(context);
      AppSnackbar.error(context, l10n?.failedToZap ?? 'Failed to zap');
    }
    return false;
  }
}

String _toHex(String pubkey) {
  if (pubkey.startsWith('npub1')) {
    return AuthService.instance.npubToHex(pubkey) ?? pubkey;
  }
  return pubkey;
}

Future<Map<String, dynamic>?> _buildZapRequest(
  Map<String, dynamic> user,
  Map<String, dynamic> note,
  int sats,
  String comment,
) async {
  const secureStorage = FlutterSecureStorage();
  final privateKey = await secureStorage.read(key: 'privateKey');
  if (privateKey == null || privateKey.isEmpty) return null;

  final lud16 = user['lud16'] as String? ?? '';
  if (!lud16.contains('@')) return null;

  final parts = lud16.split('@');
  final displayName = parts[0];
  final domain = parts[1];

  final uri = Uri.parse('https://$domain/.well-known/lnurlp/$displayName');
  final response = await http.get(uri);
  if (response.statusCode != 200) return null;

  final lnurlJson = jsonDecode(response.body) as Map<String, dynamic>;
  final lnurlBech32 = lnurlJson['lnurl'] as String? ?? '';
  final amountMillisats = (sats * 1000).toString();
  final relays = AppDI.get<SyncService>().relayUrls;

  final recipientPubkeyHex = _toHex(user['pubkey'] as String? ?? '');

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
  }

  final zapRequestJson = rust_events.createZapRequestEvent(
    tags: tags,
    content: comment,
    privateKeyHex: privateKey,
  );
  return jsonDecode(zapRequestJson) as Map<String, dynamic>;
}

Future<String?> _buildZapInvoice(
  Map<String, dynamic> user,
  Map<String, dynamic> note,
  int sats,
  String comment,
) async {
  final lud16 = user['lud16'] as String? ?? '';
  if (!lud16.contains('@')) return null;

  final parts = lud16.split('@');
  if (parts.length != 2 || parts.any((p) => p.isEmpty)) return null;

  final displayName = parts[0];
  final domain = parts[1];

  final uri = Uri.parse('https://$domain/.well-known/lnurlp/$displayName');
  final response = await http.get(uri);
  if (response.statusCode != 200) return null;

  final lnurlJson = jsonDecode(response.body) as Map<String, dynamic>;
  if (lnurlJson['allowsNostr'] != true || lnurlJson['nostrPubkey'] == null) {
    return null;
  }

  final callback = lnurlJson['callback'] as String?;
  if (callback == null || callback.isEmpty) return null;

  final lnurlBech32 = lnurlJson['lnurl'] as String? ?? '';
  final amountMillisats = (sats * 1000).toString();
  final relays = AppDI.get<SyncService>().relayUrls;
  if (relays.isEmpty) return null;

  const secureStorage = FlutterSecureStorage();
  final privateKey = await secureStorage.read(key: 'privateKey');
  if (privateKey == null || privateKey.isEmpty) return null;

  final recipientPubkeyHex = _toHex(user['pubkey'] as String? ?? '');

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
  }

  final zapRequestJson = rust_events.createZapRequestEvent(
    tags: tags,
    content: comment,
    privateKeyHex: privateKey,
  );
  final zapRequest = jsonDecode(zapRequestJson) as Map<String, dynamic>;

  final encodedZap = Uri.encodeComponent(jsonEncode(zapRequest));
  final zapUrl = Uri.parse(
    '$callback?amount=$amountMillisats&nostr=$encodedZap${lnurlBech32.isNotEmpty ? '&lnurl=$lnurlBech32' : ''}',
  );

  final invoiceResponse = await http.get(zapUrl);
  if (invoiceResponse.statusCode != 200) return null;

  final invoiceJson = jsonDecode(invoiceResponse.body) as Map<String, dynamic>;
  return invoiceJson['pr'] as String?;
}

Future<void> _publishZapEventsAsync(
  Map<String, dynamic>? zapRequest,
  String invoice,
  String recipientPubkeyHex,
  Map<String, dynamic> note,
  String comment,
  String privateKey,
  int sats,
  dynamic paymentResult,
) async {
  if (zapRequest == null) return;
  try {
    final noteId = note['id'] as String? ?? '';
    await AppDI.get<SyncService>().broadcastEvent(zapRequest);

    if (kDebugMode) {
      print(
          '[ZapDialog] Zap request event (kind 9734) published for note: $noteId');
    }
  } catch (e) {
    if (kDebugMode) {
      print('[ZapDialog] Error publishing zap request: $e');
    }
  }
}

Future<bool> _processZapPayment(
  BuildContext context,
  Map<String, dynamic> note,
  int sats,
  String comment,
) async {
  try {
    final noteAuthor = note['pubkey'] as String? ?? '';
    final profileRepo = AppDI.get<ProfileRepository>();
    final profile = await profileRepo.getProfile(noteAuthor);

    if (profile == null) {
      if (context.mounted) {
        final l10n = AppLocalizations.of(context);
        AppSnackbar.error(context,
            l10n?.errorLoadingUserProfile ?? 'Error loading user profile',
            duration: const Duration(seconds: 1));
      }
      return false;
    }

    final lud16 = profile.lud16 ?? '';
    if (lud16.isEmpty) {
      if (context.mounted) {
        final l10n = AppLocalizations.of(context);
        AppSnackbar.error(
            context,
            l10n?.userNoLightningAddress ??
                'User does not have a lightning address configured.',
            duration: const Duration(seconds: 1));
      }
      return false;
    }

    final user = {
      'pubkey': profile.pubkey,
      'name': profile.name ?? '',
      'lud16': profile.lud16 ?? '',
    };

    if (context.mounted) {
      return await _payZapWithWallet(context, user, note, sats, comment);
    }
    return false;
  } catch (e) {
    if (context.mounted) {
      final l10n = AppLocalizations.of(context);
      AppSnackbar.error(context, l10n?.failedToZap ?? 'Failed to zap',
          duration: const Duration(seconds: 1));
    }
    return false;
  }
}

Future<bool> processZapDirectly(
  BuildContext context,
  Map<String, dynamic> note,
  int sats,
) async {
  return _processZapPayment(context, note, sats, '');
}

Future<bool> processZapWithComment(
  BuildContext context,
  Map<String, dynamic> note,
  int sats,
  String comment,
) async {
  return _processZapPayment(context, note, sats, comment);
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
        final l10n = AppLocalizations.of(modalContext);
        return Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(modalContext).viewInsets.bottom + 40,
              top: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n?.zap ?? 'Zap',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(modalContext),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.overlayLight,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        size: 20,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CustomInputField(
                controller: amountController,
                keyboardType: TextInputType.number,
                labelText: l10n?.amountSats ?? 'Amount (sats)',
                fillColor: colors.inputFill,
              ),
              const SizedBox(height: 16),
              CustomInputField(
                controller: noteController,
                labelText: l10n?.commentOptional ?? 'Comment (Optional)',
                fillColor: colors.inputFill,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: SecondaryButton(
                  label: l10n?.send ?? 'Send',
                  onPressed: () {
                    final sats = int.tryParse(amountController.text.trim());
                    if (sats == null || sats <= 0) {
                      AppSnackbar.error(modalContext,
                          l10n?.enterValidAmount ?? 'Enter a valid amount',
                          duration: const Duration(seconds: 1));
                      return;
                    }

                    Navigator.pop(modalContext, {
                      'confirmed': true,
                      'amount': sats,
                      'comment': noteController.text.trim(),
                    });
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

  return result ?? {'confirmed': false, 'amount': 0, 'comment': ''};
}
