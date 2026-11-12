import 'dart:async';
import 'dart:math';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/base/result.dart';

class SparkService {
  static const String _baseEntropyKey = 'spark_entropy';
  static const String _legacyMnemonicKey = 'spark_mnemonic';
  static const String _baseLnAddressKey = 'spark_ln_address';

  final FlutterSecureStorage _secureStorage;
  final Future<BreezSdk> Function(String account, Uint8List entropy)?
  _sdkFactory;

  SparkService({
    FlutterSecureStorage? secureStorage,
    this._sdkFactory,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  String? _activeAccountId;
  BreezSdk? _sdk;
  Future<Result<BreezSdk>>? _connectionFuture;
  final Map<String, Future<void>> _entropyOperations = {};
  int _accountGeneration = 0;

  StreamSubscription<SdkEvent>? _eventSubscription;
  final StreamController<SdkEvent> _eventController =
      StreamController<SdkEvent>.broadcast();

  Stream<SdkEvent> get eventStream => _eventController.stream;

  void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }

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
    unawaited(disconnectSdk());
    _activeAccountId = npub;
  }

  Future<void> clearActiveAccount() {
    _activeAccountId = null;
    return disconnectSdk();
  }

  void _cancelEventSubscription() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  void _subscribeToSdkEvents(BreezSdk sdk) {
    _cancelEventSubscription();
    _eventSubscription = sdk.addEventListener().listen(
      (event) {
        if (!_eventController.isClosed) {
          _eventController.add(event);
        }
      },
      onError: (e) {
        _log('[SparkService] SDK event stream error: $e');
      },
    );
  }

  Uint8List _generateEntropy() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
  }

  Future<Result<BreezSdk>> getOrConnectSdk() => _getOrConnect();

  Future<Result<BreezSdk>> _getOrConnectForGeneration(int generation) async {
    final result = await _getOrConnect();
    return generation == _accountGeneration
        ? result
        : Result.error('Active wallet changed');
  }

  Future<Result<BreezSdk>> _getOrConnect() async {
    if (_sdk != null) return Result.success(_sdk!);
    final account = _activeAccountId;
    if (account == null || account.isEmpty) {
      return Result.error('No active account set');
    }
    final pending = _connectionFuture;
    if (pending != null) return pending;

    final generation = _accountGeneration;
    final connection = _connectForAccount(account, generation);
    _connectionFuture = connection;
    try {
      return await connection;
    } finally {
      if (generation == _accountGeneration) _connectionFuture = null;
    }
  }

  Future<Result<BreezSdk>> _connectForAccount(
    String account,
    int generation,
  ) async {
    try {
      final entropyResult = await _getOrCreateEntropy();
      if (entropyResult.isError) return Result.error(entropyResult.error!);
      if (generation != _accountGeneration) {
        return Result.error('Active wallet changed');
      }

      final sdk = await (_sdkFactory ?? _connectNativeSdk)(
        account,
        entropyResult.data!,
      );
      if (generation != _accountGeneration) {
        await sdk.disconnect();
        return Result.error('Active wallet changed');
      }
      _sdk = sdk;
      _subscribeToSdkEvents(sdk);
      return Result.success(sdk);
    } catch (e) {
      _log('[SparkService] Connect error: $e');
      return Result.error('Failed to connect to Spark: $e');
    }
  }

  Future<BreezSdk> _connectNativeSdk(String account, Uint8List entropy) async {
    final appDir = await getApplicationDocumentsDirectory();
    final breezApiKey = await _getBreezApiKey();
    var config = defaultConfig(network: Network.mainnet);
    if (breezApiKey.isNotEmpty) config = config.copyWith(apiKey: breezApiKey);
    return connect(
      request: ConnectRequest(
        config: config,
        seed: Seed.entropy(entropy),
        storageDir: '${appDir.path}/spark_$account',
      ),
    );
  }

  Future<String> _getBreezApiKey() async {
    try {
      final fromStorage = await _secureStorage.read(key: 'breez_api_key');
      if (fromStorage != null && fromStorage.isNotEmpty) return fromStorage;

      const fromBuild = String.fromEnvironment('BREEZ_API_KEY');
      if (fromBuild.isNotEmpty) return fromBuild;

      return '';
    } catch (_) {
      return '';
    }
  }

  Future<Result<Uint8List>> _getOrCreateEntropy() async {
    final generation = _accountGeneration;
    final entropyKey = _entropyKey;
    return _withEntropyLock(entropyKey, () async {
      try {
        if (_activeAccountId == null || _activeAccountId!.isEmpty) {
          return Result.error('No active account set');
        }
        if (generation != _accountGeneration) {
          return Result.error('Active wallet changed');
        }
        final storedHex = await _secureStorage.read(key: entropyKey);
        if (generation != _accountGeneration) {
          return Result.error('Active wallet changed');
        }
        if (storedHex != null && storedHex.isNotEmpty) {
          if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(storedHex)) {
            return Result.error('Stored wallet recovery key is invalid');
          }
          return Result.success(Uint8List.fromList(hex.decode(storedHex)));
        }

        final entropy = _generateEntropy();
        final entropyHex = hex.encode(entropy);
        await _secureStorage.write(key: entropyKey, value: entropyHex);
        if (generation != _accountGeneration) {
          return Result.error('Active wallet changed');
        }
        return Result.success(entropy);
      } catch (e) {
        return Result.error('Failed to get or create entropy: $e');
      }
    });
  }

  Future<T> _withEntropyLock<T>(
    String key,
    Future<T> Function() operation,
  ) async {
    final previous = _entropyOperations[key];
    final completed = Completer<void>();
    _entropyOperations[key] = completed.future;
    try {
      if (previous != null) await previous;
      return await operation();
    } finally {
      completed.complete();
      if (identical(_entropyOperations[key], completed.future)) {
        _entropyOperations.remove(key);
      }
    }
  }

  Future<Result<String>> getOrCreateMnemonic() async {
    final result = await _getOrCreateEntropy();
    if (result.isError) return Result.error(result.error!);
    return Result.success(hex.encode(result.data!));
  }

  Future<Result<void>> restoreWallet(String entropyHex) async {
    try {
      if (_activeAccountId == null || _activeAccountId!.isEmpty) {
        return Result.error('No active account set');
      }

      final entropyKey = _entropyKey;
      final account = _activeAccountId;
      final cleaned = entropyHex
          .trim()
          .replaceAll(RegExp(r'\s+'), '')
          .toLowerCase();
      if (cleaned.length != 64) {
        return Result.error('Invalid recovery phrase length');
      }

      hex.decode(cleaned);

      await disconnectSdk();
      if (_activeAccountId != account) {
        return Result.error('Active wallet changed');
      }
      final generation = _accountGeneration;
      await _withEntropyLock(entropyKey, () async {
        if (generation == _accountGeneration) {
          await _secureStorage.write(key: entropyKey, value: cleaned);
        }
      });
      if (generation != _accountGeneration) {
        return Result.error('Active wallet changed');
      }

      final connectResult = await getOrConnectSdk();
      if (connectResult.isError) {
        return Result.error(connectResult.error!);
      }

      return Result.success(null);
    } catch (e) {
      _log('[SparkService] restoreWallet error: $e');
      return Result.error('Failed to restore wallet: $e');
    }
  }

  Future<Result<String?>> getLightningAddress() async {
    final generation = _accountGeneration;
    final addressKey = _lnAddressKey;
    try {
      final sdkResult = await _getOrConnect();
      if (generation != _accountGeneration) {
        return Result.error('Active wallet changed');
      }
      if (sdkResult.isError) {
        return _readCachedLightningAddress(addressKey, generation);
      }

      final sdk = sdkResult.data!;
      final info = await sdk.getLightningAddress();
      if (generation != _accountGeneration) {
        return Result.error('Active wallet changed');
      }
      final address = info?.lightningAddress;

      if (address != null && address.isNotEmpty) {
        await _secureStorage.write(key: addressKey, value: address);
      }
      if (generation != _accountGeneration) {
        return Result.error('Active wallet changed');
      }
      return Result.success(address);
    } catch (e) {
      _log('[SparkService] getLightningAddress error: $e');
      return _readCachedLightningAddress(addressKey, generation);
    }
  }

  Future<Result<String?>> _readCachedLightningAddress(
    String key,
    int generation,
  ) async {
    try {
      if (generation != _accountGeneration || _activeAccountId == null) {
        return Result.error('Active wallet changed');
      }
      final cached = await _secureStorage.read(key: key);
      if (generation != _accountGeneration) {
        return Result.error('Active wallet changed');
      }
      return Result.success(cached);
    } catch (e) {
      return Result.error('Failed to read lightning address: $e');
    }
  }

  Future<Result<String>> registerLightningAddress(String username) async {
    final generation = _accountGeneration;
    final addressKey = _lnAddressKey;
    try {
      final sdkResult = await _getOrConnectForGeneration(generation);
      if (sdkResult.isError) return Result.error(sdkResult.error!);

      final sdk = sdkResult.data!;
      final info = await sdk.registerLightningAddress(
        request: RegisterLightningAddressRequest(username: username),
      );
      if (generation != _accountGeneration) {
        return Result.error('Active wallet changed');
      }
      await _secureStorage.write(key: addressKey, value: info.lightningAddress);
      if (generation != _accountGeneration) {
        return Result.error('Active wallet changed');
      }
      return Result.success(info.lightningAddress);
    } catch (e) {
      _log('[SparkService] registerLightningAddress error: $e');
      return Result.error('Failed to register lightning address: $e');
    }
  }

  Future<Result<bool>> checkLightningAddressAvailable(String username) async {
    final generation = _accountGeneration;
    try {
      final sdkResult = await _getOrConnectForGeneration(generation);
      if (sdkResult.isError) return Result.error(sdkResult.error!);

      final sdk = sdkResult.data!;
      final available = await sdk.checkLightningAddressAvailable(
        request: CheckLightningAddressRequest(username: username),
      );
      if (generation != _accountGeneration) {
        return Result.error('Active wallet changed');
      }
      return Result.success(available);
    } catch (e) {
      _log('[SparkService] checkLightningAddressAvailable error: $e');
      return Result.error('Failed to check availability: $e');
    }
  }

  Future<Result<bool>> isConnected() async {
    try {
      if (_sdk != null) return Result.success(true);
      if (_activeAccountId == null || _activeAccountId!.isEmpty) {
        return Result.success(false);
      }
      final generation = _accountGeneration;
      final stored = await _secureStorage.read(key: _entropyKey);
      if (generation != _accountGeneration) {
        return Result.error('Active wallet changed');
      }
      if (stored == null || stored.isEmpty) return Result.success(false);
      if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(stored)) {
        return Result.error('Stored wallet recovery key is invalid');
      }
      return Result.success(true);
    } catch (e) {
      return Result.error('Failed to read wallet connection: $e');
    }
  }

  Future<Result<int>> getBalance() async {
    final generation = _accountGeneration;
    try {
      final sdkResult = await _getOrConnectForGeneration(generation);
      if (sdkResult.isError) return Result.error(sdkResult.error!);

      final sdk = sdkResult.data!;
      final info = await sdk.getInfo(
        request: const GetInfoRequest(ensureSynced: false),
      );
      if (generation != _accountGeneration) {
        return Result.error('Active wallet changed');
      }
      return Result.success(info.balanceSats.toInt());
    } catch (e) {
      _log('[SparkService] getBalance error: $e');
      return Result.error('Failed to get balance: $e');
    }
  }

  Future<Result<String>> createLightningInvoice({
    required int amountSats,
    String? description,
  }) async {
    if (amountSats <= 0) return Result.error('Amount must be positive');
    final generation = _accountGeneration;
    try {
      final sdkResult = await _getOrConnectForGeneration(generation);
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
      if (generation != _accountGeneration) {
        return Result.error('Active wallet changed');
      }
      return Result.success(response.paymentRequest);
    } catch (e) {
      _log('[SparkService] createLightningInvoice error: $e');
      return Result.error('Failed to create invoice: $e');
    }
  }

  Future<Result<void>> payLightningInvoice(String bolt11) async {
    if (bolt11.trim().isEmpty) return Result.error('Invoice cannot be empty');
    final generation = _accountGeneration;
    try {
      final sdkResult = await _getOrConnectForGeneration(generation);
      if (sdkResult.isError) return Result.error(sdkResult.error!);

      final sdk = sdkResult.data!;

      final prepareRequest = PrepareSendPaymentRequest(
        paymentRequest: PaymentRequest.input(input: bolt11.trim()),
        amount: null,
        tokenIdentifier: null,
        conversionOptions: null,
        feePolicy: null,
      );
      final prepareResponse = await sdk.prepareSendPayment(
        request: prepareRequest,
      );
      if (generation != _accountGeneration) {
        return Result.error('Active wallet changed');
      }

      await sdk.sendPayment(
        request: SendPaymentRequest(prepareResponse: prepareResponse),
      );
      return Result.success(null);
    } catch (e) {
      _log('[SparkService] payLightningInvoice error: $e');
      return Result.error('Payment failed: $e');
    }
  }

  Future<Result<List<Map<String, dynamic>>>> listPayments({
    int limit = 20,
  }) async {
    if (limit <= 0) return Result.error('Invalid payment limit');
    final generation = _accountGeneration;
    try {
      final sdkResult = await _getOrConnectForGeneration(generation);
      if (sdkResult.isError) return Result.error(sdkResult.error!);

      final sdk = sdkResult.data!;
      final response = await sdk.listPayments(
        request: ListPaymentsRequest(limit: limit),
      );
      if (generation != _accountGeneration) {
        return Result.error('Active wallet changed');
      }

      final payments = response.payments.map(_paymentToMap).toList();
      return Result.success(payments);
    } catch (e) {
      _log('[SparkService] listPayments error: $e');
      return Result.error('Failed to list payments: $e');
    }
  }

  Future<Result<Map<String, dynamic>>> getPaymentById(String paymentId) async {
    final generation = _accountGeneration;
    try {
      final sdkResult = await _getOrConnectForGeneration(generation);
      if (sdkResult.isError) return Result.error(sdkResult.error!);

      final sdk = sdkResult.data!;
      final response = await sdk.getPayment(
        request: GetPaymentRequest(paymentId: paymentId),
      );
      if (generation != _accountGeneration) {
        return Result.error('Active wallet changed');
      }
      return Result.success(_paymentToMap(response.payment));
    } catch (e) {
      _log('[SparkService] getPaymentById error: $e');
      return Result.error('Failed to get payment: $e');
    }
  }

  Map<String, dynamic> _paymentToMap(Payment p) {
    final isIncoming = p.paymentType == PaymentType.receive;

    String? description;
    String? invoice;
    String? preimage;
    String? paymentHash;

    final details = p.details;
    if (details is PaymentDetails_Lightning) {
      description = details.description;
      invoice = details.invoice;
      preimage = details.htlcDetails.preimage;
      paymentHash = details.htlcDetails.paymentHash;
    } else if (details is PaymentDetails_Spark) {
      description = details.invoiceDetails?.description;
      invoice = details.invoiceDetails?.invoice;
      preimage = details.htlcDetails?.preimage;
      paymentHash = details.htlcDetails?.paymentHash;
    }

    return <String, dynamic>{
      'id': p.id,
      'isIncoming': isIncoming,
      'amount': p.amount.toInt(),
      'fees': p.fees.toInt(),
      'timestamp': p.timestamp.toInt(),
      'status': p.status.name,
      'method': p.method.name,
      'description': ?description,
      'invoice': ?invoice,
      'preimage': ?preimage,
      'paymentHash': ?paymentHash,
    };
  }

  Future<Result<InputType>> parseInput(String input) async {
    final generation = _accountGeneration;
    try {
      final sdkResult = await _getOrConnectForGeneration(generation);
      if (sdkResult.isError) return Result.error(sdkResult.error!);

      final sdk = sdkResult.data!;
      final result = await sdk.parse(input: input);
      if (generation != _accountGeneration) {
        return Result.error('Active wallet changed');
      }
      return Result.success(result);
    } catch (e) {
      _log('[SparkService] parseInput error: $e');
      return Result.error('Failed to parse input: $e');
    }
  }

  Future<void> disconnectSdk() async {
    _accountGeneration++;
    _connectionFuture = null;
    _cancelEventSubscription();
    final sdk = _sdk;
    _sdk = null;
    if (sdk != null) {
      try {
        await sdk.disconnect();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await disconnectSdk();
    if (!_eventController.isClosed) {
      await _eventController.close();
    }
  }

  Future<Result<void>> clearWalletData() async {
    try {
      final account = _activeAccountId;
      if (account == null || account.isEmpty) {
        return Result.error('No active account set');
      }
      final entropyKey = _entropyKey;
      final addressKey = _lnAddressKey;
      final legacyKey = _prefixedKey(_legacyMnemonicKey);
      await disconnectSdk();
      if (_activeAccountId != account) {
        return Result.error('Active wallet changed');
      }
      await _withEntropyLock(
        entropyKey,
        () => Future.wait([
          _secureStorage.delete(key: entropyKey),
          _secureStorage.delete(key: addressKey),
          _secureStorage.delete(key: legacyKey),
        ]),
      );
      return Result.success(null);
    } catch (e) {
      return Result.error('Failed to clear wallet data: $e');
    }
  }
}
