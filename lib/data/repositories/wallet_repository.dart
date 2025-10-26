import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/base/result.dart';
import '../../models/wallet_model.dart';
import '../services/auth_service.dart';
import '../services/coinos_service.dart';
import '../services/validation_service.dart';

class WalletRepository {
  final CoinosService _coinosService;

  final StreamController<CoinosBalance> _balanceController = StreamController<CoinosBalance>.broadcast();
  final StreamController<List<CoinosPayment>> _transactionsController = StreamController<List<CoinosPayment>>.broadcast();

  WalletRepository({
    required CoinosService coinosService,
    required AuthService authService,
    required ValidationService validationService,
  }) : _coinosService = coinosService;

  Stream<CoinosBalance> get balanceStream => _balanceController.stream;
  Stream<List<CoinosPayment>> get transactionsStream => _transactionsController.stream;

  Future<Result<CoinosUser>> authenticateWithCoinos() async {
    try {
      debugPrint('[WalletRepository] Starting Coinos authentication');

      final authResult = await _coinosService.autoLogin();
      if (authResult.isError) {
        return Result.error(authResult.error!);
      }

      final user = authResult.data!.user;
      debugPrint('[WalletRepository] Authentication successful for user: ${user.username}');

      return Result.success(user);
    } catch (e) {
      debugPrint('[WalletRepository] Authentication error: $e');
      return Result.error('Authentication failed: $e');
    }
  }

  Future<Result<CoinosUser>> authenticateWithNostr() async {
    try {
      debugPrint('[WalletRepository] Authenticating with Nostr');

      final authResult = await _coinosService.authenticateWithNostr();

      if (authResult.isError) {
        return Result.error(authResult.error!);
      }

      final user = authResult.data!.user;
      debugPrint('[WalletRepository] Nostr authentication successful for user: ${user.username}');

      return Result.success(user);
    } catch (e) {
      debugPrint('[WalletRepository] Nostr authentication error: $e');
      return Result.error('Nostr authentication failed: $e');
    }
  }

  Future<Result<CoinosUser?>> autoConnect() async {
    try {
      debugPrint('[WalletRepository] Attempting auto-connect');

      final isAuthenticatedResult = await _coinosService.isAuthenticated();
      if (isAuthenticatedResult.isSuccess && isAuthenticatedResult.data == true) {
        final userResult = await _coinosService.getStoredUser();
        if (userResult.isSuccess && userResult.data != null) {
          debugPrint('[WalletRepository] Auto-connect successful');
          return Result.success(userResult.data);
        }
      }

      debugPrint('[WalletRepository] Auto-connect failed, attempting re-authentication');
      final authResult = await authenticateWithCoinos();
      return authResult.fold(
        (user) => Result.success(user),
        (error) {
          debugPrint('[WalletRepository] Re-authentication failed: $error');
          return Result.success(null);
        },
      );
    } catch (e) {
      debugPrint('[WalletRepository] Auto-connect error: $e');
      return Result.success(null);
    }
  }

  Future<Result<CoinosBalance>> getBalance() async {
    try {
      final result = await _coinosService.getBalance();

      return result.fold(
        (balance) {
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

      final result = await _coinosService.createInvoice(
        amount: amount,
        type: 'lightning',
      );

      return result.fold(
        (invoice) {
          debugPrint('[WalletRepository] Invoice created: ${invoice.toString()}');

          String? invoiceString;

          if (invoice.bolt11 != null && invoice.bolt11!.isNotEmpty) {
            invoiceString = invoice.bolt11;
          } else if (invoice.text != null && invoice.text!.isNotEmpty) {
            invoiceString = invoice.text;
          } else if (invoice.hash != null && invoice.hash!.isNotEmpty) {
            invoiceString = invoice.hash;
          }

          if (invoiceString != null && invoiceString.isNotEmpty) {
            return Result.success(invoiceString);
          } else {
            debugPrint('[WalletRepository] Invoice response fields: bolt11=${invoice.bolt11}, text=${invoice.text}, hash=${invoice.hash}');
            return const Result.error('Invalid invoice response - no invoice string found');
          }
        },
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Failed to create invoice: $e');
    }
  }

  Future<Result<CoinosPaymentResult>> payInvoice(String invoice) async {
    try {
      debugPrint('[WalletRepository] Attempting to pay invoice: ${invoice.substring(0, 20)}...');

      if (invoice.trim().isEmpty) {
        return const Result.error('Invoice cannot be empty');
      }

      final result = await _coinosService.payInvoice(invoice);

      return result.fold(
        (paymentResult) {
          debugPrint('[WalletRepository] Payment result received: $paymentResult');
          debugPrint('[WalletRepository] Payment isSuccess: ${paymentResult.isSuccess}');

          if (paymentResult.isSuccess) {
            debugPrint('[WalletRepository] Payment successful');
            return Result.success(paymentResult);
          } else {
            final errorMsg = paymentResult.error ?? 'Payment failed - no specific error';
            debugPrint('[WalletRepository] Payment failed: $errorMsg');
            return Result.error(errorMsg);
          }
        },
        (error) {
          debugPrint('[WalletRepository] Payment service error: $error');
          return Result.error(error);
        },
      );
    } catch (e) {
      debugPrint('[WalletRepository] Payment exception: $e');
      return Result.error('Failed to pay invoice: $e');
    }
  }

  Future<Result<CoinosPaymentResult>> payKeysend(String pubkey, int amount) async {
    try {
      if (pubkey.trim().isEmpty) {
        return const Result.error('Pubkey cannot be empty');
      }

      if (amount <= 0) {
        return const Result.error('Amount must be greater than 0');
      }

      return const Result.error('Keysend not supported by Coinos API');
    } catch (e) {
      return Result.error('Failed to send keysend payment: $e');
    }
  }

  Future<Result<CoinosInvoice>> lookupInvoice(String invoice) async {
    try {
      if (invoice.trim().isEmpty) {
        return const Result.error('Invoice cannot be empty');
      }

      return const Result.error('Invoice lookup not yet implemented');
    } catch (e) {
      return Result.error('Failed to lookup invoice: $e');
    }
  }

  Future<Result<List<CoinosPayment>>> listTransactions() async {
    try {
      final result = await _coinosService.getPaymentHistory(limit: 50);

      return result.fold(
        (transactions) {
          _transactionsController.add(transactions);
          return Result.success(transactions);
        },
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Failed to list transactions: $e');
    }
  }

  Future<Result<CoinosUser>> getInfo() async {
    try {
      final result = await _coinosService.getAccountInfo();

      return result.fold(
        (user) => Result.success(user),
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Failed to get wallet info: $e');
    }
  }

  Future<Result<CoinosPaymentResult>> sendInternalPayment({
    required String username,
    required int amount,
  }) async {
    try {
      if (username.trim().isEmpty) {
        return const Result.error('Username cannot be empty');
      }

      if (amount <= 0) {
        return const Result.error('Amount must be greater than 0');
      }

      final result = await _coinosService.sendInternalPayment(
        username: username,
        amount: amount,
      );

      return result.fold(
        (paymentResult) {
          if (paymentResult.isSuccess) {
            return Result.success(paymentResult);
          } else {
            return Result.error(paymentResult.error ?? 'Internal payment failed');
          }
        },
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Failed to send internal payment: $e');
    }
  }

  Future<Result<CoinosPaymentResult>> sendBitcoinPayment({
    required String address,
    required int amount,
  }) async {
    try {
      if (address.trim().isEmpty) {
        return const Result.error('Address cannot be empty');
      }

      if (amount <= 0) {
        return const Result.error('Amount must be greater than 0');
      }

      final result = await _coinosService.sendBitcoinPayment(
        address: address,
        amount: amount,
      );

      return result.fold(
        (paymentResult) {
          if (paymentResult.isSuccess) {
            return Result.success(paymentResult);
          } else {
            return Result.error(paymentResult.error ?? 'Bitcoin payment failed');
          }
        },
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Failed to send bitcoin payment: $e');
    }
  }

  Future<Result<CoinosPaymentResult>> sendToLightningAddress({
    required String lightningAddress,
    required int amount,
  }) async {
    try {
      if (lightningAddress.trim().isEmpty) {
        return const Result.error('Lightning address cannot be empty');
      }

      if (amount <= 0) {
        return const Result.error('Amount must be greater than 0');
      }

      final result = await _coinosService.payInvoice(lightningAddress);

      return result.fold(
        (paymentResult) {
          if (paymentResult.isSuccess) {
            return Result.success(paymentResult);
          } else {
            return Result.error(paymentResult.error ?? 'Lightning address payment failed');
          }
        },
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Failed to send to lightning address: $e');
    }
  }

  bool get isConnected => true;

  CoinosUser? get currentConnection => null;

  Future<bool> get hasSavedConnection async {
    try {
      final tokenResult = await _coinosService.getStoredToken();
      return tokenResult.isSuccess && tokenResult.data != null;
    } catch (e) {
      return false;
    }
  }

  Future<Result<void>> disconnect() async {
    try {
      await _coinosService.clearAuthData();
      debugPrint('[WalletRepository] Wallet disconnected');
      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to disconnect: $e');
    }
  }

  void dispose() {
    _balanceController.close();
    _transactionsController.close();
    _coinosService.dispose();
  }
}
