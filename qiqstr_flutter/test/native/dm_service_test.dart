import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/data/services/auth_service.dart';
import '../../lib/data/services/dm_service.dart';
import '../../lib/data/services/rust_nostr_bridge.dart';
import '../../lib/src/rust/api/nip17.dart' as nip17;
import '../support/native_rust.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = AuthService.instance;
  final aliceKey = '01'.padLeft(64, '0');
  final bobKey = '02'.padLeft(64, '0');
  late String bobPubkey;

  setUpAll(() async {
    await initializeNativeRust();
    bobPubkey = Bip340.getPublicKey(bobKey);
  });
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await auth.refreshCache();
    expect((await auth.loginWithPrivateKey(aliceKey)).isSuccess, isTrue);
  });

  test('rejected recipient broadcasts are not reported as sent', () async {
    var broadcasts = 0;
    final service = DmService(
      authService: auth,
      broadcastEvent: (_) async => ++broadcasts == 2,
    );
    addTearDown(service.dispose);
    expect((await service.sendMessage(bobPubkey, 'hello')).isError, isTrue);
    expect(broadcasts, 2);
    expect(service.cachedConversations, isNull);
  });

  test(
    'sender and recipient copies share one message and update conversations',
    () async {
      final published = <Map<String, dynamic>>[];
      final service = DmService(
        authService: auth,
        broadcastEvent: (event) async {
          published.add(event);
          return true;
        },
      );
      addTearDown(service.dispose);
      final conversation = service.conversationsStream.first;
      expect((await service.sendMessage(bobPubkey, 'hello')).isSuccess, isTrue);
      final received =
          jsonDecode(
                nip17.unwrapGiftWrapDm(
                  receiverPrivateKeyHex: bobKey,
                  giftWrapJson: jsonEncode(published.first),
                  currentUserPubkeyHex: bobPubkey,
                ),
              )
              as Map<String, dynamic>;
      final sent =
          jsonDecode(
                nip17.unwrapGiftWrapDm(
                  receiverPrivateKeyHex: aliceKey,
                  giftWrapJson: jsonEncode(published.last),
                  currentUserPubkeyHex: auth.currentUserPubkeyHex!,
                ),
              )
              as Map<String, dynamic>;
      expect(received['id'], sent['id']);
      expect((await conversation).single['lastMessage']['id'], sent['id']);
      expect(
        service.cachedConversations!.single['lastMessage']['content'],
        'hello',
      );
    },
  );

  test('reset during publishing cannot repopulate the account cache', () async {
    final started = Completer<void>();
    final published = Completer<bool>();
    final service = DmService(
      authService: auth,
      broadcastEvent: (_) {
        if (!started.isCompleted) started.complete();
        return published.future;
      },
    );
    addTearDown(service.dispose);
    final pending = service.sendMessage(bobPubkey, 'hello');
    await started.future;
    service.reset();
    published.complete(true);
    expect((await pending).isError, isTrue);
    expect(service.cachedConversations, isNull);
  });

  test('reset discards a delayed conversation relay response', () async {
    final started = Completer<void>();
    final relay = Completer<List<Map<String, dynamic>>>();
    final event =
        jsonDecode(
              nip17.createGiftWrapDm(
                senderPrivateKeyHex: bobKey,
                receiverPubkeyHex: auth.currentUserPubkeyHex!,
                message: 'old account message',
              ),
            )
            as Map<String, dynamic>;
    final service = DmService(
      authService: auth,
      queryStoredEvents: (_, _) async => [],
      fetchRelayEvents: (_, _) {
        started.complete();
        return relay.future;
      },
    );
    addTearDown(service.dispose);
    final pending = service.getConversations();
    await started.future;
    service.reset();
    relay.complete([event]);
    expect((await pending).isError, isTrue);
    expect(service.cachedConversations, isNull);
  });

  test(
    'changing identity invalidates conversations before using the cache',
    () async {
      final service = DmService(
        authService: auth,
        broadcastEvent: (_) async => true,
        queryStoredEvents: (_, _) async => [],
        fetchRelayEvents: (_, _) async => [],
      );
      addTearDown(service.dispose);
      expect(
        (await service.sendMessage(bobPubkey, 'private')).isSuccess,
        isTrue,
      );
      expect(service.cachedConversations, hasLength(1));
      await auth.loginWithPrivateKey(bobKey);
      expect((await service.getConversations()).data, isEmpty);
    },
  );

  test('empty messages never invoke the relay', () async {
    final service = DmService(
      authService: auth,
      broadcastEvent: (_) => throw StateError('Unexpected broadcast'),
    );
    addTearDown(service.dispose);
    expect((await service.sendMessage(bobPubkey, ' ')).isError, isTrue);
  });
}
