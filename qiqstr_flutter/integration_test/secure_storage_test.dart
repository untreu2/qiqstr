import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native secure storage preserves and deletes isolated keys', (
    tester,
  ) async {
    expect(Platform.isAndroid || Platform.isIOS, isTrue);
    final storage = const FlutterSecureStorage();
    final random = Random.secure();
    final suffix =
        '${DateTime.now().microsecondsSinceEpoch}_${random.nextInt(1 << 32)}';
    final seedKey = 'qiqstr_secure_storage_regression_${suffix}_seed';
    final sentinelKey = 'qiqstr_secure_storage_regression_${suffix}_sentinel';
    final keys = [seedKey, sentinelKey];
    addTearDown(() async {
      for (final key in keys) {
        await storage.delete(key: key);
      }
    });

    String recoveryFixture() => List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();

    final originalSeed = recoveryFixture();
    final updatedSeed = recoveryFixture();
    const sentinel = 'isolated-storage-fixture';
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final nativeOptions = Platform.isAndroid
        ? storage.aOptions.params
        : storage.iOptions.params;

    expect(await storage.containsKey(key: seedKey), isFalse);
    expect(await storage.read(key: seedKey), isNull);
    await storage.write(key: seedKey, value: originalSeed);
    await storage.write(key: sentinelKey, value: sentinel);
    expect(await storage.containsKey(key: seedKey), isTrue);
    expect(await storage.read(key: seedKey) == originalSeed, isTrue);
    final nativeSeed = await channel.invokeMethod<String>('read', {
      'key': seedKey,
      'options': nativeOptions,
    });
    expect(nativeSeed == originalSeed, isTrue, reason: 'Native read mismatch');

    await storage.write(key: seedKey, value: updatedSeed);
    final reopenedStorage = FlutterSecureStorage(
      aOptions: storage.aOptions,
      iOptions: storage.iOptions,
    );
    expect(identical(storage, reopenedStorage), isFalse);
    expect(await reopenedStorage.containsKey(key: seedKey), isTrue);
    expect(await reopenedStorage.read(key: seedKey) == updatedSeed, isTrue);

    await reopenedStorage.delete(key: seedKey);
    expect(await storage.containsKey(key: seedKey), isFalse);
    expect(await storage.read(key: seedKey), isNull);
    expect(
      await channel.invokeMethod<String>('read', {
        'key': seedKey,
        'options': nativeOptions,
      }),
      isNull,
    );
    expect(await storage.read(key: sentinelKey), sentinel);
  });
}
