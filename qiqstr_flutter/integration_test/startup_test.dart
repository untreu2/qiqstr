import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/main.dart' as app;
import '../lib/data/services/crash_reporting_service.dart';
import '../lib/src/rust/api/relay.dart' as relay;
import '../lib/ui/screens/auth/welcome_page.dart';

class _TestPaths extends PathProviderPlatform {
  final String path;

  _TestPaths(this.path);

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real startup initializes native libraries and opens welcome', (
    tester,
  ) async {
    final uncaughtErrors = <Object>[];
    crashReporting.setReporter((error, stack, {context, fatal = false}) {
      uncaughtErrors.add(error);
    });
    addTearDown(() => crashReporting.setReporter(null));
    final directory = await Directory.systemTemp.createTemp('qiqstr-startup-');
    final previousPaths = PathProviderPlatform.instance;
    addTearDown(() {
      PathProviderPlatform.instance = previousPaths;
    });
    PathProviderPlatform.instance = _TestPaths(directory.path);
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final oldDatabase = await Directory(
      '${directory.path}/nostr-lmdb',
    ).create();
    await File('${oldDatabase.path}/legacy-data').writeAsString('preserve me');
    app.main();
    for (var attempt = 0; attempt < 300; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(WelcomePage).evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(await relay.isClientInitialized(), isTrue);
    expect(tester.takeException(), isNull);
    final backups = await directory
        .list()
        .where((entry) => entry.path.contains('nostr-lmdb.backup-'))
        .toList();
    expect(backups, hasLength(1));
    expect(
      await File('${backups.single.path}/legacy-data').readAsString(),
      'preserve me',
    );
    expect(uncaughtErrors, isEmpty, reason: 'Uncaught startup errors');
    await tester.pumpWidget(const SizedBox.shrink());
    await GetIt.instance.reset();
    await relay.initClient(relayUrls: [], discoveryRelays: []);
    await directory.delete(recursive: true);
  });
}
