import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/core/di/modules/services_module.dart';
import '../lib/core/router/app_router.dart';
import '../lib/data/services/auth_service.dart';
import '../lib/data/services/crash_reporting_service.dart';
import '../lib/main.dart' as app;
import '../lib/src/rust/api/crypto.dart' as crypto;
import '../lib/src/rust/api/database.dart' as database;
import '../lib/src/rust/api/events.dart' as events;
import '../lib/src/rust/api/relay.dart' as relay;
import '../lib/ui/screens/auth/welcome_page.dart';
import '../lib/ui/screens/note/share_note.dart';

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

Future<void> _pumpFrames(WidgetTester tester, {int count = 15}) async {
  for (var frame = 0; frame < count; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('authenticated routes, local content, settings and navigation', (
    tester,
  ) async {
    final uncaughtErrors = <Object>[];
    crashReporting.setReporter((error, stack, {context, fatal = false}) {
      uncaughtErrors.add(error);
    });
    addTearDown(() => crashReporting.setReporter(null));
    final directory = await Directory.systemTemp.createTemp('qiqstr-flows-');
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await GetIt.instance.reset();
      await relay.initClient(relayUrls: [], discoveryRelays: []);
      if (await directory.exists()) await directory.delete(recursive: true);
      PathProviderPlatform.instance = previousPaths;
    });
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'custom_main_relays': <String>[],
      'bottom_nav_order': ['2', '3', '1', '0'],
    });
    final errorHandler = FlutterError.onError;
    app.main();
    for (var attempt = 0; attempt < 300; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(WelcomePage).evaluate().isNotEmpty) break;
    }
    FlutterError.onError = errorHandler;
    expect(find.byType(WelcomePage), findsOneWidget);

    final (privateKey, publicKey) = crypto.generateKeypair();
    final (_, peer) = crypto.generateKeypair();
    final auth = AuthService.instance;
    final login = await auth.loginWithPrivateKey(privateKey);
    expect(login.isSuccess, isTrue);
    await ServicesModule.reinitializeForAccountSwitch();
    await relay.initClient(
      relayUrls: [],
      discoveryRelays: [],
      privateKeyHex: privateKey,
      dbPath: '${directory.path}/nostr-lmdb',
    );
    final note = events.createNoteEvent(
      content: 'Local integration note',
      tags: [],
      privateKeyHex: privateKey,
    );
    final noteId = jsonDecode(note)['id'] as String;
    final article = events.createSignedEvent(
      kind: 30023,
      content: 'Local integration article body',
      tags: [
        ['d', 'integration-article'],
        ['title', 'Local integration article'],
      ],
      privateKeyHex: privateKey,
    );
    final articleId = jsonDecode(article)['id'] as String;
    await database.dbSaveEvents(
      eventsJson: jsonEncode([
        jsonDecode(note),
        jsonDecode(article),
        jsonDecode(
          events.createProfileEvent(
            profileJson: jsonEncode({'name': 'Integration account'}),
            privateKeyHex: privateKey,
          ),
        ),
      ]),
    );
    final npub = auth.currentUserNpub!;
    final router = AppRouter.router;
    router.go('/home/feed?npub=$npub');
    await _pumpFrames(tester);
    expect(
      find.text('Local integration note', findRichText: true),
      findsWidgets,
    );

    for (final (index, route) in [
      (1, '/home/dm'),
      (3, '/home/notifications'),
      (2, '/home/wallet'),
      (0, '/home/feed'),
    ]) {
      await tester.tap(find.byKey(ValueKey('navigation-$index')));
      await _pumpFrames(tester);
      expect(router.routeInformationProvider.value.uri.path, route);
      expect(tester.takeException(), isNull, reason: route);
    }

    await tester.tap(find.byKey(const ValueKey('compose-note')));
    await _pumpFrames(tester);
    expect(find.byType(ShareNotePage), findsOneWidget);
    await tester.enterText(
      find
          .descendant(
            of: find.byType(ShareNotePage),
            matching: find.byType(TextField),
          )
          .first,
      'Local draft without publishing',
    );
    await _pumpFrames(tester);
    expect(find.text('Local draft without publishing'), findsOneWidget);
    Navigator.of(tester.element(find.byType(ShareNotePage))).pop();
    await _pumpFrames(tester);
    expect(find.byType(ShareNotePage), findsNothing);
    expect(tester.takeException(), isNull);

    final routes = <String, String>{
      '/profile?pubkey=$publicKey': 'ProfilePage',
      '/following?pubkey=$publicKey': 'FollowingPage',
      '/thread/$noteId': 'ThreadPage',
      '/quotes?noteId=$noteId': 'QuotesPage',
      '/note-statistics?noteId=$noteId': 'NoteStatisticsPage',
      '/article?articleId=$articleId': 'ArticleDetailPage',
      '/edit-profile': 'EditOwnProfilePage',
      '/settings': 'SettingsPage',
      '/display': 'DisplayPage',
      '/keys': 'KeysPage',
      '/relays': 'RelayPage',
      '/database': 'DatabasePage',
      '/payments': 'PaymentsPage',
      '/muted': 'MutedPage',
      '/bookmarks': 'BookmarkPage',
      '/follow-sets': 'FollowSetsPage',
      '/event-manager': 'EventManagerPage',
      '/onboarding-spark?npub=$npub': 'OnboardingSparkPage',
      '/home/dm/chat?pubkey=$peer&npub=$npub': 'DmChatPage',
      '/home/wallet/receive?npub=$npub': 'ReceivePage',
      '/home/feed/explore?npub=$npub': 'ExplorePage',
    };
    for (final entry in routes.entries) {
      router.push(entry.key);
      await _pumpFrames(tester);
      expect(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == entry.value,
        ),
        findsOneWidget,
        reason: entry.key,
      );
      expect(tester.takeException(), isNull, reason: entry.key);
      router.pop();
      await _pumpFrames(tester, count: 5);
      expect(tester.takeException(), isNull, reason: 'Leaving ${entry.key}');
    }
    expect(uncaughtErrors, isEmpty, reason: 'Uncaught application errors');
  });
}
