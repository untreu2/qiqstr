import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/core/base/result.dart';
import '../../../lib/data/services/nwc_service.dart';

class _DelayedConnection extends NwcService {
  final connection = Completer<Result<String?>>();

  @override
  Future<Result<String?>> getConnectionUri() => connection.future;
}

class _ValidatedNwc extends NwcService {
  _ValidatedNwc({required super.secureStorage});

  @override
  bool validateUri(String uri) => true;
}

class _DelayedWrites implements FlutterSecureStorage {
  final writes = <Completer<void>>[];
  final values = <String, String?>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final key = invocation.namedArguments[#key] as String;
    if (invocation.memberName == #write) {
      final completed = Completer<void>();
      writes.add(completed);
      return completed.future.then((_) {
        values[key] = invocation.namedArguments[#value] as String?;
      });
    }
    if (invocation.memberName == #read) return Future.value(values[key]);
    return super.noSuchMethod(invocation);
  }
}

class _DelayedStorage implements FlutterSecureStorage {
  final reads = <String, Completer<String?>>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #read) {
      final key = invocation.namedArguments[#key] as String;
      return (reads[key] = Completer<String?>()).future;
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'overlapping connection changes persist only the latest wallet',
    () async {
      final storage = _DelayedWrites();
      final service = _ValidatedNwc(secureStorage: storage)
        ..setActiveAccount('alice');
      final first = service.saveConnectionUri('old-wallet');
      final second = service.saveConnectionUri('new-wallet');
      expect(storage.writes, hasLength(1));
      storage.writes.first.complete();
      await Future<void>.delayed(Duration.zero);
      expect(storage.writes, hasLength(2));
      final read = service.getConnectionUri();
      storage.writes.last.complete();
      expect((await first).isError, isTrue);
      expect((await second).isSuccess, isTrue);
      expect((await read).data, 'new-wallet');
      expect(storage.values['alice_nwc_connection_uri'], 'new-wallet');
    },
  );

  test(
    'account changes prevent a pending payment from reaching the bridge',
    () async {
      final service = _DelayedConnection()..setActiveAccount('alice');
      final pending = service.payInvoice('invoice');
      service.setActiveAccount('bob');
      service.connection.complete(Result.success('alice-connection'));
      expect((await pending).error, 'Wallet connection changed');
    },
  );

  test(
    'signed-out users cannot access an unscoped wallet connection',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'nwc_connection_uri': 'legacy-wallet',
      });
      final service = NwcService();
      expect((await service.getConnectionUri()).isError, isTrue);
      expect((await service.saveConnectionUri('wallet')).isError, isTrue);
      expect((await service.clearConnection()).isError, isTrue);
      expect(
        await const FlutterSecureStorage().read(key: 'nwc_connection_uri'),
        'legacy-wallet',
      );
    },
  );

  test('invalid payment inputs fail before invoking native code', () async {
    final service = NwcService()..setActiveAccount('alice');
    expect(
      (await service.makeInvoice(amountSats: 0)).error,
      'Amount must be positive',
    );
    expect(
      (await service.makeInvoice(amountSats: -1)).error,
      'Amount must be positive',
    );
    expect((await service.payInvoice(' ')).error, 'Invoice cannot be empty');
    expect((await service.listTransactions(limit: -1)).isError, isTrue);
    expect((await service.listTransactions(offset: -1)).isError, isTrue);
  });
  test('an old account read cannot populate the new wallet cache', () async {
    final storage = _DelayedStorage();
    final service = NwcService(secureStorage: storage);
    service.setActiveAccount('alice');
    final oldRead = service.getConnectionUri();
    service.setActiveAccount('bob');
    final newRead = service.getConnectionUri();
    storage.reads['bob_nwc_connection_uri']!.complete('bob-wallet');
    expect((await newRead).data, 'bob-wallet');
    storage.reads['alice_nwc_connection_uri']!.complete('alice-wallet');
    expect((await oldRead).isError, isTrue);
    expect((await service.getConnectionUri()).data, 'bob-wallet');
  });

  test(
    'clearing the active account invalidates pending wallet reads',
    () async {
      final storage = _DelayedStorage();
      final service = NwcService(secureStorage: storage);
      service.setActiveAccount('alice');
      final pending = service.getConnectionUri();
      service.clearActiveAccount();
      storage.reads['alice_nwc_connection_uri']!.complete('alice-wallet');
      expect((await pending).isError, isTrue);
      expect(service.isActive, isFalse);
    },
  );
}
