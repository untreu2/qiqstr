import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/core/base/result.dart';
import '../../../lib/data/services/spark_service.dart';

class _OfflineSpark extends SparkService {
  @override
  Future<Result<BreezSdk>> getOrConnectSdk() async => Result.error('Offline');
}

class _Sdk implements BreezSdk {
  bool disconnected = false;
  Future<LightningAddressInfo?> Function()? address;
  Future<PrepareSendPaymentResponse> Function()? prepare;
  bool sent = false;

  @override
  Future<LightningAddressInfo?> getLightningAddress() => address!();

  @override
  Future<PrepareSendPaymentResponse> prepareSendPayment({
    required PrepareSendPaymentRequest request,
  }) => prepare!();

  @override
  Future<SendPaymentResponse> sendPayment({
    required SendPaymentRequest request,
  }) {
    sent = true;
    throw StateError('No live payments in tests');
  }

  @override
  Stream<SdkEvent> addEventListener() => const Stream.empty();

  @override
  Future<void> disconnect() async => disconnected = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Address implements LightningAddressInfo {
  @override
  String get lightningAddress => 'alice@example.com';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreparedPayment implements PrepareSendPaymentResponse {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #read) {
      return Future<String?>.error(StateError('Locked'));
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('retains the imported recovery key when connecting fails', () async {
    final service = _OfflineSpark()..setActiveAccount('alice');
    addTearDown(service.dispose);
    final entropy = 'ab' * 32;
    final result = await service.restoreWallet(entropy);
    expect(result.isError, isTrue);
    expect(
      await const FlutterSecureStorage().read(key: 'alice_spark_entropy'),
      entropy,
    );
    expect((await service.getOrCreateMnemonic()).data, entropy);
  });

  test('does not create a wallet without an active identity', () async {
    final service = SparkService();
    addTearDown(service.dispose);
    expect((await service.getOrCreateMnemonic()).isError, isTrue);
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });

  test('preserves existing legacy recovery data', () async {
    FlutterSecureStorage.setMockInitialValues({'spark_mnemonic': 'backup'});
    final service = SparkService()..setActiveAccount('alice');
    addTearDown(service.dispose);
    await service.getOrCreateMnemonic();
    expect(
      await const FlutterSecureStorage().read(key: 'spark_mnemonic'),
      'backup',
    );
  });

  test('stores distinct recovery keys for different accounts', () async {
    final service = SparkService()..setActiveAccount('alice');
    addTearDown(service.dispose);
    final alice = (await service.getOrCreateMnemonic()).data;
    service.setActiveAccount('bob');
    final bob = (await service.getOrCreateMnemonic()).data;
    expect(alice, isNotNull);
    expect(bob, isNot(alice));
    service.setActiveAccount('alice');
    expect((await service.getOrCreateMnemonic()).data, alice);
  });

  test('concurrent recovery reads return one persisted wallet key', () async {
    final service = SparkService()..setActiveAccount('alice');
    addTearDown(service.dispose);
    final results = await Future.wait(
      List.generate(12, (_) => service.getOrCreateMnemonic()),
    );
    expect(results.every((r) => r.isSuccess), isTrue);
    expect(results.map((r) => r.data).toSet(), hasLength(1));
    expect(
      await const FlutterSecureStorage().read(key: 'alice_spark_entropy'),
      results.first.data,
    );
  });

  test(
    'corrupt recovery data is reported without generating a replacement',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'alice_spark_entropy': 'abcd',
      });
      final service = SparkService()..setActiveAccount('alice');
      addTearDown(service.dispose);
      expect((await service.getOrCreateMnemonic()).isError, isTrue);
      expect((await service.isConnected()).isError, isTrue);
      expect(
        await const FlutterSecureStorage().read(key: 'alice_spark_entropy'),
        'abcd',
      );
    },
  );

  test(
    'secure storage failures return errors for wallet status and address',
    () async {
      final service = SparkService(secureStorage: _FailingStorage())
        ..setActiveAccount('alice');
      addTearDown(service.dispose);
      expect((await service.isConnected()).isError, isTrue);
      expect((await service.getLightningAddress()).isError, isTrue);
    },
  );

  test(
    'late lightning address response cannot be cached for another account',
    () async {
      final address = Completer<LightningAddressInfo?>();
      final sdk = _Sdk()..address = () => address.future;
      final service = SparkService(sdkFactory: (_, _) async => sdk)
        ..setActiveAccount('alice');
      addTearDown(service.dispose);
      await service.getOrConnectSdk();
      final pending = service.getLightningAddress();
      await Future<void>.delayed(Duration.zero);
      service.setActiveAccount('bob');
      address.complete(_Address());
      expect((await pending).isError, isTrue);
      expect(
        await const FlutterSecureStorage().read(key: 'bob_spark_ln_address'),
        isNull,
      );
    },
  );

  test(
    'an account switch during payment preparation prevents sending',
    () async {
      final prepare = Completer<PrepareSendPaymentResponse>();
      final sdk = _Sdk()..prepare = () => prepare.future;
      final service = SparkService(sdkFactory: (_, _) async => sdk)
        ..setActiveAccount('alice');
      addTearDown(service.dispose);
      await service.getOrConnectSdk();
      final pending = service.payLightningInvoice('invoice');
      await Future<void>.delayed(Duration.zero);
      service.setActiveAccount('bob');
      prepare.complete(_PreparedPayment());
      expect((await pending).isError, isTrue);
      expect(sdk.sent, isFalse);
    },
  );

  test('invalid invoices and amounts do not initialize a wallet', () async {
    final service = SparkService()..setActiveAccount('alice');
    addTearDown(service.dispose);
    expect(
      (await service.createLightningInvoice(amountSats: 0)).isError,
      isTrue,
    );
    expect(
      (await service.createLightningInvoice(amountSats: -1)).isError,
      isTrue,
    );
    expect((await service.payLightningInvoice(' ')).isError, isTrue);
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });

  test(
    'clearing one wallet retains other accounts and legacy backups',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'alice_spark_entropy': 'alice-key',
        'bob_spark_entropy': 'bob-key',
        'spark_mnemonic': 'legacy-backup',
      });
      final service = SparkService()..setActiveAccount('alice');
      addTearDown(service.dispose);
      expect((await service.clearWalletData()).isSuccess, isTrue);
      expect(await const FlutterSecureStorage().readAll(), {
        'bob_spark_entropy': 'bob-key',
        'spark_mnemonic': 'legacy-backup',
      });
    },
  );

  test(
    'shares concurrent connections and discards a stale account SDK',
    () async {
      final pending = <String, Completer<BreezSdk>>{};
      var connectionCount = 0;
      final service = SparkService(
        sdkFactory: (account, entropy) {
          connectionCount++;
          expect(entropy, hasLength(32));
          return (pending[account] = Completer<BreezSdk>()).future;
        },
      )..setActiveAccount('alice');
      addTearDown(service.dispose);
      final first = service.getOrConnectSdk();
      final second = service.getOrConnectSdk();
      await Future<void>.delayed(Duration.zero);
      expect(connectionCount, 1);
      service.setActiveAccount('bob');
      final current = service.getOrConnectSdk();
      await Future<void>.delayed(Duration.zero);
      final bob = _Sdk();
      pending['bob']!.complete(bob);
      expect((await current).data, same(bob));
      final alice = _Sdk();
      pending['alice']!.complete(alice);
      expect((await first).isError, isTrue);
      expect((await second).isError, isTrue);
      expect(alice.disconnected, isTrue);
      expect((await service.getOrConnectSdk()).data, same(bob));
      expect(bob.disconnected, isFalse);
    },
  );
}
