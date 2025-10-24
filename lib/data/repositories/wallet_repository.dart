import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:nostr/nostr.dart';

// ignore: implementation_imports
import 'package:nostr/src/crypto/nip_004.dart';

import '../../core/base/result.dart';
import '../../models/wallet_model.dart';
import '../services/auth_service.dart';
import '../services/validation_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class WalletRepository {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  WalletConnection? _connection;
  Keychain? _clientKeychain;

  final StreamController<WalletBalance> _balanceController = StreamController<WalletBalance>.broadcast();
  final StreamController<List<TransactionDetails>> _transactionsController = StreamController<List<TransactionDetails>>.broadcast();

  WalletRepository({
    required AuthService authService,
    required ValidationService validationService,
  });

  Stream<WalletBalance> get balanceStream => _balanceController.stream;
  Stream<List<TransactionDetails>> get transactionsStream => _transactionsController.stream;

  Future<Result<WalletConnection>> connectWallet(String nwcUri) async {
    try {
      debugPrint('[WalletRepository] Connecting to wallet with URI: ${nwcUri.substring(0, 50)}...');

      if (!nwcUri.startsWith('nostr+walletconnect://')) {
        return const Result.error('Invalid NWC URI format. Must start with "nostr+walletconnect://"');
      }

      final connection = WalletConnection.fromUri(nwcUri);

      final clientKeychain = Keychain(connection.clientSecret);

      final updatedConnection = WalletConnection(
        relayUrl: connection.relayUrl,
        walletPubKey: connection.walletPubKey,
        clientSecret: connection.clientSecret,
        clientPubKey: clientKeychain.public,
      );

      _connection = updatedConnection;
      _clientKeychain = clientKeychain;

      await _secureStorage.write(key: 'nwc_uri', value: nwcUri);

      debugPrint('[WalletRepository] Successfully connected to wallet');
      debugPrint('[WalletRepository] Relay: ${connection.relayUrl}');
      debugPrint('[WalletRepository] Wallet PubKey: ${connection.walletPubKey}');
      debugPrint('[WalletRepository] Client PubKey: ${clientKeychain.public}');
      debugPrint('[WalletRepository] NWC URI saved to secure storage');

      return Result.success(updatedConnection);
    } catch (e) {
      debugPrint('[WalletRepository] Connection error: $e');
      return Result.error('Failed to connect to wallet: $e');
    }
  }

  Future<Result<String>> _sendRequest(String method, Map<String, dynamic> params) async {
    WebSocket? ws;
    try {
      if (_connection == null || _clientKeychain == null) {
        return const Result.error('Wallet not connected');
      }

      debugPrint('[WalletRepository] Sending $method request with params: $params');

      final request = NWCRequest(method: method, params: params);
      final payloadJson = request.toJsonString();

      debugPrint('[WalletRepository] Request payload: $payloadJson');

      final encryptedContent = nip4cipher(
        _clientKeychain!.private,
        '02${_connection!.walletPubKey}',
        payloadJson,
        true, //
      );

      debugPrint('[WalletRepository] Encrypted content: ${encryptedContent.substring(0, 50)}...');

      final event = Event.from(
        kind: 23194,
        tags: [
          ['p', _connection!.walletPubKey]
        ],
        content: encryptedContent,
        privkey: _clientKeychain!.private,
      );

      debugPrint('[WalletRepository] Created event: ${event.id}');

      ws = await WebSocket.connect(_connection!.relayUrl);
      debugPrint('[WalletRepository] Connected to wallet relay: ${_connection!.relayUrl}');

      final subscriptionId = _generateSubscriptionId();
      final responseCompleter = Completer<String>();

      late StreamSubscription wsSubscription;

      wsSubscription = ws.listen(
        (message) {
          try {
            if (responseCompleter.isCompleted) return;

            debugPrint('[WalletRepository] Received WebSocket message: $message');
            final data = jsonDecode(message);

            if (data is List && data.length >= 3) {
              if (data[0] == 'EVENT' && data[1] == subscriptionId) {
                final eventData = data[2] as Map<String, dynamic>;
                final responseEvent = Event.fromJson(eventData);

                debugPrint('[WalletRepository] Received response event: ${responseEvent.id}');

                final eTags = responseEvent.tags.where((tag) => tag.length >= 2 && tag[0] == 'e').toList();
                if (eTags.any((tag) => tag[1] == event.id)) {
                  try {
                    final decryptedContent = nip4cipher(
                      _clientKeychain!.private,
                      '02${_connection!.walletPubKey}',
                      responseEvent.content.split('?iv=')[0],
                      false, // cipher = false for decryption
                      nonce: _extractNonce(responseEvent.content),
                    );

                    debugPrint('[WalletRepository] Decrypted response: $decryptedContent');
                    responseCompleter.complete(decryptedContent);
                  } catch (e) {
                    debugPrint('[WalletRepository] Decryption error: $e');
                    responseCompleter.completeError('Failed to decrypt response: $e');
                  }
                }
              } else if (data[0] == 'EOSE' && data[1] == subscriptionId) {
                debugPrint('[WalletRepository] End of stored events for subscription: $subscriptionId');
              }
            }
          } catch (e) {
            debugPrint('[WalletRepository] Message parsing error: $e');
          }
        },
        onError: (error) {
          debugPrint('[WalletRepository] WebSocket error: $error');
          if (!responseCompleter.isCompleted) {
            responseCompleter.completeError('WebSocket error: $error');
          }
        },
        onDone: () {
          debugPrint('[WalletRepository] WebSocket connection closed');
          if (!responseCompleter.isCompleted) {
            responseCompleter.completeError('WebSocket connection closed');
          }
        },
      );

      final subscribeMessage = jsonEncode([
        'REQ',
        subscriptionId,
        {
          'kinds': [23195], // NWC response
          'authors': [_connection!.walletPubKey],
          '#e': [event.id],
          'limit': 1,
        }
      ]);

      debugPrint('[WalletRepository] Sending subscription: $subscribeMessage');
      ws.add(subscribeMessage);

      await Future.delayed(const Duration(milliseconds: 100));

      final eventMessage = jsonEncode(['EVENT', event.toJson()]);
      debugPrint('[WalletRepository] Sending event: ${eventMessage.substring(0, 100)}...');
      ws.add(eventMessage);

      debugPrint('[WalletRepository] Request event published: ${event.id}');

      final timeoutTimer = Timer(const Duration(seconds: 30), () {
        if (!responseCompleter.isCompleted) {
          responseCompleter.completeError('Request timeout');
        }
      });

      try {
        final response = await responseCompleter.future;
        timeoutTimer.cancel();

        debugPrint('[WalletRepository] Successfully received response for $method');
        return Result.success(response);
      } catch (e) {
        timeoutTimer.cancel();
        rethrow;
      } finally {
        try {
          await wsSubscription.cancel();
          await ws.close();
        } catch (e) {
          debugPrint('[WalletRepository] Error closing WebSocket: $e');
        }
      }
    } catch (e) {
      debugPrint('[WalletRepository] Request error: $e');
      try {
        await ws?.close();
      } catch (e2) {
        debugPrint('[WalletRepository] Error closing WebSocket on error: $e2');
      }
      return Result.error('Request failed: $e');
    }
  }

  String _extractNonce(String encryptedContent) {
    final parts = encryptedContent.split('?iv=');
    if (parts.length != 2) {
      throw Exception('Invalid encrypted content format');
    }
    return parts[1];
  }

  String _generateSubscriptionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (i) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<Result<WalletBalance>> getBalance() async {
    try {
      final response = await _sendRequest('get_balance', {});

      return response.fold(
        (responseJson) {
          final responseData = jsonDecode(responseJson) as Map<String, dynamic>;
          final nwcResponse = NWCResponse<WalletBalance>.fromJson(
            responseData,
            (json) => WalletBalance.fromJson(json),
          );

          if (nwcResponse.isError) {
            return Result.error(nwcResponse.error ?? 'Unknown error');
          }

          final balance = nwcResponse.result!;
          _balanceController.add(balance);

          return Result.success(balance);
        },
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Failed to get balance: $e');
    }
  }

  Future<Result<String>> makeInvoice(int amount, String memo) async {
    try {
      if (amount <= 0) {
        return const Result.error('Amount must be greater than 0');
      }

      final response = await _sendRequest('make_invoice', {
        'amount': amount,
        'description': memo,
      });

      return response.fold(
        (responseJson) {
          final responseData = jsonDecode(responseJson) as Map<String, dynamic>;
          final nwcResponse = NWCResponse<InvoiceDetails>.fromJson(
            responseData,
            (json) => InvoiceDetails.fromJson(json),
          );

          if (nwcResponse.isError) {
            return Result.error(nwcResponse.error ?? 'Unknown error');
          }

          return Result.success(nwcResponse.result!.invoice);
        },
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Failed to create invoice: $e');
    }
  }

  Future<Result<PaymentResult>> payInvoice(String invoice) async {
    try {
      if (invoice.trim().isEmpty) {
        return const Result.error('Invoice cannot be empty');
      }

      final response = await _sendRequest('pay_invoice', {
        'invoice': invoice,
      });

      return response.fold(
        (responseJson) {
          final responseData = jsonDecode(responseJson) as Map<String, dynamic>;
          final nwcResponse = NWCResponse<PaymentResult>.fromJson(
            responseData,
            (json) => PaymentResult.fromJson(json),
          );

          if (nwcResponse.isError) {
            return Result.error(nwcResponse.error ?? 'Unknown error');
          }

          return Result.success(nwcResponse.result!);
        },
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Failed to pay invoice: $e');
    }
  }

  Future<Result<KeysendResult>> payKeysend(String pubkey, int amount) async {
    try {
      if (pubkey.trim().isEmpty) {
        return const Result.error('Pubkey cannot be empty');
      }

      if (amount <= 0) {
        return const Result.error('Amount must be greater than 0');
      }

      final response = await _sendRequest('pay_keysend', {
        'amount': amount,
        'pubkey': pubkey,
      });

      return response.fold(
        (responseJson) {
          final responseData = jsonDecode(responseJson) as Map<String, dynamic>;
          final nwcResponse = NWCResponse<KeysendResult>.fromJson(
            responseData,
            (json) => KeysendResult.fromJson(json),
          );

          if (nwcResponse.isError) {
            return Result.error(nwcResponse.error ?? 'Unknown error');
          }

          return Result.success(nwcResponse.result!);
        },
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Failed to send keysend payment: $e');
    }
  }

  Future<Result<InvoiceDetails>> lookupInvoice(String invoice) async {
    try {
      if (invoice.trim().isEmpty) {
        return const Result.error('Invoice cannot be empty');
      }

      final response = await _sendRequest('lookup_invoice', {
        'invoice': invoice,
      });

      return response.fold(
        (responseJson) {
          final responseData = jsonDecode(responseJson) as Map<String, dynamic>;
          final nwcResponse = NWCResponse<InvoiceDetails>.fromJson(
            responseData,
            (json) => InvoiceDetails.fromJson(json),
          );

          if (nwcResponse.isError) {
            return Result.error(nwcResponse.error ?? 'Unknown error');
          }

          return Result.success(nwcResponse.result!);
        },
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Failed to lookup invoice: $e');
    }
  }

  Future<Result<List<TransactionDetails>>> listTransactions() async {
    try {
      final response = await _sendRequest('list_transactions', {});

      return response.fold(
        (responseJson) {
          final responseData = jsonDecode(responseJson) as Map<String, dynamic>;

          if (responseData.containsKey('error')) {
            return Result.error(responseData['error'] as String);
          }

          final result = responseData['result'] as Map<String, dynamic>?;
          if (result == null) {
            return const Result.error('Invalid response format');
          }

          final transactionsJson = result['transactions'] as List<dynamic>? ?? [];
          final transactions = transactionsJson.map((json) => InvoiceDetails.fromJson(json as Map<String, dynamic>)).toList();

          _transactionsController.add(transactions);

          return Result.success(transactions);
        },
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Failed to list transactions: $e');
    }
  }

  Future<Result<WalletInfo>> getInfo() async {
    try {
      final response = await _sendRequest('get_info', {});

      return response.fold(
        (responseJson) {
          final responseData = jsonDecode(responseJson) as Map<String, dynamic>;
          final nwcResponse = NWCResponse<WalletInfo>.fromJson(
            responseData,
            (json) => WalletInfo.fromJson(json),
          );

          if (nwcResponse.isError) {
            return Result.error(nwcResponse.error ?? 'Unknown error');
          }

          return Result.success(nwcResponse.result!);
        },
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Failed to get wallet info: $e');
    }
  }

  Future<Result<WalletConnection?>> autoConnect() async {
    try {
      final savedNwcUri = await _secureStorage.read(key: 'nwc_uri');
      if (savedNwcUri != null && savedNwcUri.isNotEmpty) {
        debugPrint('[WalletRepository] Found saved NWC URI, attempting auto-connect');
        final result = await connectWallet(savedNwcUri);
        return result.fold(
          (connection) => Result.success(connection),
          (error) {
            debugPrint('[WalletRepository] Auto-connect failed: $error');
            return Result.success(null);
          },
        );
      }
      return Result.success(null);
    } catch (e) {
      debugPrint('[WalletRepository] Auto-connect error: $e');
      return Result.success(null);
    }
  }

  bool get isConnected => _connection != null && _clientKeychain != null;

  WalletConnection? get currentConnection => _connection;

  Future<bool> get hasSavedConnection async {
    try {
      final savedNwcUri = await _secureStorage.read(key: 'nwc_uri');
      return savedNwcUri != null && savedNwcUri.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<Result<void>> disconnect() async {
    try {
      await _secureStorage.delete(key: 'nwc_uri');

      _connection = null;
      _clientKeychain = null;

      debugPrint('[WalletRepository] Wallet disconnected and NWC URI removed');
      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to disconnect: $e');
    }
  }

  void dispose() {
    _balanceController.close();
    _transactionsController.close();
    _connection = null;
    _clientKeychain = null;
  }
}
