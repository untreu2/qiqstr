import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/base/result.dart';
import '../../src/rust/api/nwc.dart' as rust_nwc;

class NwcService {
  static const String _baseNwcUriKey = 'nwc_connection_uri';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String? _activeAccountId;
  String? _cachedNwcUri;

  String get _nwcUriKey => _prefixedKey(_baseNwcUriKey);

  String _prefixedKey(String base) {
    if (_activeAccountId != null && _activeAccountId!.isNotEmpty) {
      return '${_activeAccountId}_$base';
    }
    return base;
  }

  bool get isActive => _cachedNwcUri != null && _cachedNwcUri!.isNotEmpty;

  void setActiveAccount(String npub) {
    if (_activeAccountId == npub) return;
    _activeAccountId = npub;
    _cachedNwcUri = null;
  }

  Future<void> warmCache() async {
    await hasConnection();
  }

  void clearActiveAccount() {
    _activeAccountId = null;
    _cachedNwcUri = null;
  }

  bool validateUri(String uri) {
    return rust_nwc.validateNwcUri(uri: uri);
  }

  Future<Result<void>> saveConnectionUri(String uri) async {
    try {
      if (!validateUri(uri)) {
        return const Result.error('Invalid NWC connection string');
      }
      await _secureStorage.write(key: _nwcUriKey, value: uri);
      _cachedNwcUri = uri;
      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to save NWC connection: $e');
    }
  }

  Future<Result<String?>> getConnectionUri() async {
    try {
      if (_cachedNwcUri != null) {
        return Result.success(_cachedNwcUri);
      }
      final uri = await _secureStorage.read(key: _nwcUriKey);
      _cachedNwcUri = uri;
      return Result.success(uri);
    } catch (e) {
      return Result.error('Failed to read NWC connection: $e');
    }
  }

  Future<bool> hasConnection() async {
    final result = await getConnectionUri();
    return result.isSuccess && result.data != null && result.data!.isNotEmpty;
  }

  Future<Result<void>> clearConnection() async {
    try {
      await _secureStorage.delete(key: _nwcUriKey);
      _cachedNwcUri = null;
      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to clear NWC connection: $e');
    }
  }

  Future<Result<Map<String, dynamic>>> payInvoice(String invoice) async {
    try {
      final uriResult = await getConnectionUri();
      if (uriResult.isError || uriResult.data == null) {
        return const Result.error('No NWC connection configured');
      }

      debugPrint('[NwcService] Paying invoice via NWC...');
      final responseJson = await rust_nwc.nwcPayInvoice(
        nwcUri: uriResult.data!,
        invoice: invoice,
      );

      final response = jsonDecode(responseJson) as Map<String, dynamic>;
      debugPrint('[NwcService] NWC payment successful');
      return Result.success(response);
    } catch (e) {
      debugPrint('[NwcService] NWC payment error: $e');
      return Result.error('NWC payment failed: $e');
    }
  }

  Future<Result<int>> getBalance() async {
    try {
      final uriResult = await getConnectionUri();
      if (uriResult.isError || uriResult.data == null) {
        return const Result.error('No NWC connection configured');
      }

      debugPrint('[NwcService] Getting balance via NWC...');
      final responseJson = await rust_nwc.nwcGetBalance(
        nwcUri: uriResult.data!,
      );

      final response = jsonDecode(responseJson) as Map<String, dynamic>;
      final balanceMsat = response['balance'] as int? ?? 0;
      debugPrint('[NwcService] NWC balance: $balanceMsat msat');
      return Result.success(balanceMsat);
    } catch (e) {
      debugPrint('[NwcService] NWC balance error: $e');
      return Result.error('Failed to get NWC balance: $e');
    }
  }

  Future<Result<String>> makeInvoice({
    required int amountSats,
    String? description,
  }) async {
    try {
      final uriResult = await getConnectionUri();
      if (uriResult.isError || uriResult.data == null) {
        return const Result.error('No NWC connection configured');
      }

      final amountMsats = BigInt.from(amountSats) * BigInt.from(1000);
      debugPrint('[NwcService] Creating invoice via NWC for $amountSats sats...');
      final responseJson = await rust_nwc.nwcMakeInvoice(
        nwcUri: uriResult.data!,
        amountMsats: amountMsats,
        description: description,
      );

      final response = jsonDecode(responseJson) as Map<String, dynamic>;
      final invoice = response['invoice'] as String?;
      if (invoice == null || invoice.isEmpty) {
        return const Result.error('NWC returned empty invoice');
      }
      debugPrint('[NwcService] NWC invoice created');
      return Result.success(invoice);
    } catch (e) {
      debugPrint('[NwcService] NWC make invoice error: $e');
      return Result.error('Failed to create NWC invoice: $e');
    }
  }

  Future<Result<List<Map<String, dynamic>>>> listTransactions({
    int? limit,
    int? offset,
  }) async {
    try {
      final uriResult = await getConnectionUri();
      if (uriResult.isError || uriResult.data == null) {
        return const Result.error('No NWC connection configured');
      }

      debugPrint('[NwcService] Listing transactions via NWC...');
      final responseJson = await rust_nwc.nwcListTransactions(
        nwcUri: uriResult.data!,
        limit: limit != null ? BigInt.from(limit) : null,
        offset: offset != null ? BigInt.from(offset) : null,
      );

      final response = jsonDecode(responseJson) as Map<String, dynamic>;
      final rawTxs = response['transactions'] as List<dynamic>? ?? [];
      final transactions = rawTxs
          .map((tx) => tx as Map<String, dynamic>)
          .toList();
      debugPrint('[NwcService] NWC transactions fetched: ${transactions.length}');
      return Result.success(transactions);
    } catch (e) {
      debugPrint('[NwcService] NWC list transactions error: $e');
      return Result.error('Failed to list NWC transactions: $e');
    }
  }

  void dispose() {}
}
