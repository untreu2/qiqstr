import 'dart:math';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/base/result.dart';

class SparkService {
  static const String _baseEntropyKey = 'spark_entropy';
  static const String _legacyMnemonicKey = 'spark_mnemonic';
  static const String _baseLnAddressKey = 'spark_ln_address';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String? _activeAccountId;
  BreezSdk? _sdk;
  bool _isConnecting = false;

  String _prefixedKey(String base) {
    if (_activeAccountId != null && _activeAccountId!.isNotEmpty) {
      return '${_activeAccountId}_$base';
    }
    return base;
  }

  String get _entropyKey => _prefixedKey(_baseEntropyKey);
  String get _lnAddressKey => _prefixedKey(_baseLnAddressKey);

  void setActiveAccount(String npub) {
    if (_activeAccountId == npub) return;
    _activeAccountId = npub;
    _sdk = null;
  }

  void clearActiveAccount() {
    _activeAccountId = null;
    _sdk = null;
  }

  Uint8List _generateEntropy() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
  }

  Future<Result<BreezSdk>> _getOrConnect() async {
    if (_sdk != null) return Result.success(_sdk!);

    if (_activeAccountId == null || _activeAccountId!.isEmpty) {
      return const Result.error('No active account set');
    }

    if (_isConnecting) {
      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 150));
        if (_sdk != null) return Result.success(_sdk!);
        if (!_isConnecting) break;
      }
      if (_sdk != null) return Result.success(_sdk!);
    }

    _isConnecting = true;
    try {
      final entropyResult = await _getOrCreateEntropy();
      if (entropyResult.isError) {
        return Result.error(entropyResult.error!);
      }

      final entropy = entropyResult.data!;
      final seed = Seed.entropy(entropy);

      final appDir = await getApplicationDocumentsDirectory();
      final accountSuffix = _activeAccountId != null
          ? '_${_activeAccountId!.substring(0, 8)}'
          : '';
      final storageDir = '${appDir.path}/spark$accountSuffix';

      final breezApiKey = await _getBreezApiKey();
      var config = defaultConfig(network: Network.mainnet);
      if (breezApiKey.isNotEmpty) {
        config = config.copyWith(apiKey: breezApiKey);
      }

      final connectRequest =
          ConnectRequest(config: config, seed: seed, storageDir: storageDir);

      _sdk = await connect(request: connectRequest);
      return Result.success(_sdk!);
    } catch (e) {
      debugPrint('[SparkService] Connect error: $e');
      return Result.error('Failed to connect to Spark: $e');
    } finally {
      _isConnecting = false;
    }
  }

  Future<String> _getBreezApiKey() async {
    try {
      final fromStorage = await _secureStorage.read(key: 'breez_api_key');
      if (fromStorage != null && fromStorage.isNotEmpty) return fromStorage;

      final fromEnv = dotenv.maybeGet('BREEZ_API_KEY');
      if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;

      return '';
    } catch (_) {
      return '';
    }
  }

  Future<Result<Uint8List>> _getOrCreateEntropy() async {
    try {
      final storedHex = await _secureStorage.read(key: _entropyKey);
      if (storedHex != null && storedHex.isNotEmpty) {
        return Result.success(Uint8List.fromList(hex.decode(storedHex)));
      }

      await _cleanupLegacyMnemonic();

      final entropy = _generateEntropy();
      final entropyHex = hex.encode(entropy);
      await _secureStorage.write(key: _entropyKey, value: entropyHex);
      return Result.success(entropy);
    } catch (e) {
      return Result.error('Failed to get or create entropy: $e');
    }
  }

  Future<void> _cleanupLegacyMnemonic() async {
    try {
      await _secureStorage.delete(key: _prefixedKey(_legacyMnemonicKey));
      await _secureStorage.delete(key: _legacyMnemonicKey);
    } catch (_) {}
  }

  Future<Result<String>> getOrCreateMnemonic() async {
    final result = await _getOrCreateEntropy();
    if (result.isError) return Result.error(result.error!);
    return Result.success(hex.encode(result.data!));
  }

  Future<Result<String?>> getLightningAddress() async {
    try {
      final sdkResult = await _getOrConnect();
      if (sdkResult.isError) {
        final cached = await _secureStorage.read(key: _lnAddressKey);
        return Result.success(cached);
      }

      final sdk = sdkResult.data!;
      final info = await sdk.getLightningAddress();
      final address = info?.lightningAddress;

      if (address != null && address.isNotEmpty) {
        await _secureStorage.write(key: _lnAddressKey, value: address);
      }

      return Result.success(address);
    } catch (e) {
      debugPrint('[SparkService] getLightningAddress error: $e');
      final cached = await _secureStorage.read(key: _lnAddressKey);
      return Result.success(cached);
    }
  }

  Future<Result<String>> registerLightningAddress(String username) async {
    try {
      final sdkResult = await _getOrConnect();
      if (sdkResult.isError) return Result.error(sdkResult.error!);

      final sdk = sdkResult.data!;
      final info = await sdk.registerLightningAddress(
        request: RegisterLightningAddressRequest(username: username),
      );
      await _secureStorage.write(
          key: _lnAddressKey, value: info.lightningAddress);
      return Result.success(info.lightningAddress);
    } catch (e) {
      debugPrint('[SparkService] registerLightningAddress error: $e');
      return Result.error('Failed to register lightning address: $e');
    }
  }

  Future<Result<bool>> checkLightningAddressAvailable(String username) async {
    try {
      final sdkResult = await _getOrConnect();
      if (sdkResult.isError) return Result.error(sdkResult.error!);

      final sdk = sdkResult.data!;
      final available = await sdk.checkLightningAddressAvailable(
        request: CheckLightningAddressRequest(username: username),
      );
      return Result.success(available);
    } catch (e) {
      debugPrint('[SparkService] checkLightningAddressAvailable error: $e');
      return Result.error('Failed to check availability: $e');
    }
  }

  Future<Result<bool>> isConnected() async {
    if (_sdk != null) return const Result.success(true);
    if (_activeAccountId == null || _activeAccountId!.isEmpty) {
      return const Result.success(false);
    }
    final stored = await _secureStorage.read(key: _entropyKey);
    return Result.success(stored != null && stored.isNotEmpty);
  }

  Future<Result<int>> getBalance() async {
    try {
      final sdkResult = await _getOrConnect();
      if (sdkResult.isError) return Result.error(sdkResult.error!);

      final sdk = sdkResult.data!;
      final info = await sdk.getInfo(
          request: const GetInfoRequest(ensureSynced: false));
      return Result.success(info.balanceSats.toInt());
    } catch (e) {
      debugPrint('[SparkService] getBalance error: $e');
      return Result.error('Failed to get balance: $e');
    }
  }

  Future<Result<String>> createLightningInvoice({
    required int amountSats,
    String? description,
  }) async {
    try {
      final sdkResult = await _getOrConnect();
      if (sdkResult.isError) return Result.error(sdkResult.error!);

      final sdk = sdkResult.data!;
      final response = await sdk.receivePayment(
        request: ReceivePaymentRequest(
          paymentMethod: ReceivePaymentMethod.bolt11Invoice(
            description: description ?? '',
            amountSats: BigInt.from(amountSats),
            expirySecs: null,
          ),
        ),
      );
      return Result.success(response.paymentRequest);
    } catch (e) {
      debugPrint('[SparkService] createLightningInvoice error: $e');
      return Result.error('Failed to create invoice: $e');
    }
  }

  Future<Result<void>> payLightningInvoice(String bolt11) async {
    try {
      final sdkResult = await _getOrConnect();
      if (sdkResult.isError) return Result.error(sdkResult.error!);

      final sdk = sdkResult.data!;

      final prepareRequest = PrepareSendPaymentRequest(
        paymentRequest: bolt11,
        amount: null,
        tokenIdentifier: null,
        conversionOptions: null,
        feePolicy: null,
      );
      final prepareResponse =
          await sdk.prepareSendPayment(request: prepareRequest);

      await sdk.sendPayment(
        request: SendPaymentRequest(prepareResponse: prepareResponse),
      );
      return const Result.success(null);
    } catch (e) {
      debugPrint('[SparkService] payLightningInvoice error: $e');
      return Result.error('Payment failed: $e');
    }
  }

  Future<Result<List<Map<String, dynamic>>>> listPayments(
      {int limit = 20}) async {
    try {
      final sdkResult = await _getOrConnect();
      if (sdkResult.isError) return Result.error(sdkResult.error!);

      final sdk = sdkResult.data!;
      final response = await sdk.listPayments(
        request: ListPaymentsRequest(
          limit: limit,
        ),
      );

      final payments = response.payments.map((p) {
        final isIncoming = p.paymentType == PaymentType.receive;
        final amountSats = p.amount.toInt();
        return <String, dynamic>{
          'id': p.id,
          'isIncoming': isIncoming,
          'amount': amountSats,
          'timestamp': p.timestamp.toInt(),
          'status': p.status.name,
        };
      }).toList();

      return Result.success(payments);
    } catch (e) {
      debugPrint('[SparkService] listPayments error: $e');
      return Result.error('Failed to list payments: $e');
    }
  }


  Future<void> disconnectSdk() async {
    if (_sdk != null) {
      try {
        await _sdk!.disconnect();
      } catch (_) {}
      _sdk = null;
    }
  }

  Future<Result<void>> clearWalletData() async {
    try {
      await disconnectSdk();
      await Future.wait([
        _secureStorage.delete(key: _entropyKey),
        _secureStorage.delete(key: _lnAddressKey),
        _cleanupLegacyMnemonic(),
      ]);
      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to clear wallet data: $e');
    }
  }
}
