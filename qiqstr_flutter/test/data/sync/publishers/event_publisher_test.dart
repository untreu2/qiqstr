import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/core/base/result.dart';
import '../../../../lib/data/services/auth_service.dart';
import '../../../../lib/data/services/encrypted_bookmark_service.dart';
import '../../../../lib/data/services/encrypted_mute_service.dart';
import '../../../../lib/data/services/follow_set_service.dart';
import '../../../../lib/data/services/pinned_notes_service.dart';
import '../../../../lib/data/sync/publishers/event_publisher.dart';
import '../../../../lib/domain/entities/follow_set.dart';
import '../../../../lib/src/rust/frb_generated.dart';

class _Auth implements AuthService {
  @override
  String? currentUserPubkeyHex = 'author';
  Completer<Result<String?>>? keyRead;
  String privateKey = 'key-author';
  int publicKeyReads = 0;

  @override
  Future<Result<String?>> getCurrentUserPrivateKey() =>
      keyRead?.future ?? Future.value(Success(privateKey));

  @override
  Future<Result<String?>> getCurrentUserPublicKeyHex() async {
    publicKeyReads++;
    return const Success('different-account');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements RustLibApi {
  final signedEvents = <Map<String, dynamic>>[];
  final encryptionKeys = <(String, String)>[];

  @override
  String crateApiCryptoGetPublicKey({required String privateKeyHex}) =>
      privateKeyHex.substring(4);

  @override
  String crateApiNip17Nip44Encrypt({
    required String content,
    required String senderSkHex,
    required String receiverPkHex,
  }) {
    encryptionKeys.add((senderSkHex, receiverPkHex));
    return 'encrypted';
  }

  @override
  String crateApiEventsCreateSignedEvent({
    required int kind,
    required String content,
    required List<List<String>> tags,
    required String privateKeyHex,
  }) {
    final event = <String, dynamic>{
      'id': 'signed',
      'pubkey': crateApiCryptoGetPublicKey(privateKeyHex: privateKeyHex),
      'kind': kind,
      'created_at': 1,
      'content': content,
      'tags': tags,
    };
    signedEvents.add(event);
    return jsonEncode(event);
  }

  @override
  Future<void> crateApiDatabaseSetActiveMuteList({
    required List<String> mutedPubkeys,
    required List<String> mutedWords,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _clearCaches() {
  EncryptedBookmarkService.instance.clear();
  EncryptedMuteService.instance.clear();
  FollowSetService.instance.clear();
  PinnedNotesService.instance.clear();
}

void _seedNextAccount() {
  EncryptedBookmarkService.instance.updateCache(eventIds: ['next-bookmark']);
  EncryptedMuteService.instance.updateCache(
    pubkeys: ['next-mute'],
    words: ['next-word'],
  );
  FollowSetService.instance.addSet(
    const FollowSet(id: 'next-set', pubkey: 'next', dTag: 'list', createdAt: 1),
  );
  PinnedNotesService.instance.pinNote('next-pin');
}

void _expectNextAccountIntact() {
  expect(EncryptedBookmarkService.instance.bookmarkedEventIds, [
    'next-bookmark',
  ]);
  expect(EncryptedMuteService.instance.mutedPubkeys, ['next-mute']);
  expect(EncryptedMuteService.instance.mutedWords, ['next-word']);
  expect(FollowSetService.instance.followSets.single.id, 'next-set');
  expect(PinnedNotesService.instance.pinnedNoteIds, ['next-pin']);
}

Future<Map<String, dynamic>> _create(EventPublisher publisher, String kind) =>
    switch (kind) {
      'bookmark' => publisher.createBookmark(
        bookmarkedEventIds: ['old-bookmark'],
      ),
      'mute' => publisher.createMute(
        mutedPubkeys: ['old-mute'],
        mutedWords: ['old-word'],
      ),
      'follow set' => publisher.createFollowSet(
        dTag: 'list',
        title: 'Old list',
        description: '',
        image: '',
        pubkeys: ['old-follow'],
      ),
      'pinned notes' => publisher.createPinnedNotes(pinnedNoteIds: ['old-pin']),
      _ => throw ArgumentError.value(kind),
    };

void main() {
  late _Api api;
  late _Auth auth;
  late EventPublisher publisher;

  setUpAll(() {
    api = _Api();
    RustLib.initMock(api: api);
  });
  tearDownAll(RustLib.dispose);

  setUp(() {
    _clearCaches();
    api.signedEvents.clear();
    api.encryptionKeys.clear();
    auth = _Auth();
    publisher = EventPublisher(authService: auth);
  });
  tearDown(_clearCaches);

  for (final kind in ['bookmark', 'mute', 'follow set', 'pinned notes']) {
    for (final boundary in ['account change', 'cache reset', 'logout']) {
      test(
        '$kind creation cannot change caches after $boundary during key read',
        () async {
          auth.keyRead = Completer<Result<String?>>();
          final pending = _create(publisher, kind);
          final expectation = expectLater(pending, throwsStateError);
          if (boundary == 'account change') auth.currentUserPubkeyHex = 'next';
          if (boundary == 'cache reset') _clearCaches();
          if (boundary == 'logout') auth.currentUserPubkeyHex = null;
          _seedNextAccount();
          auth.keyRead!.complete(const Success('key-author'));
          await expectation;
          _expectNextAccountIntact();
          expect(api.signedEvents, isEmpty);
          expect(api.encryptionKeys, isEmpty);
        },
      );
    }

    test('$kind rejects a key read from a different identity', () async {
      auth.privateKey = 'key-next';
      _seedNextAccount();
      await expectLater(_create(publisher, kind), throwsStateError);
      _expectNextAccountIntact();
      expect(api.signedEvents, isEmpty);
      expect(api.encryptionKeys, isEmpty);
    });

    test(
      '$kind signs with a consistent identity and updates its cache',
      () async {
        final event = await _create(publisher, kind);
        expect(event['pubkey'], 'author');
        expect(api.signedEvents, hasLength(1));
        expect(auth.publicKeyReads, 0);
        switch (kind) {
          case 'bookmark':
            expect(EncryptedBookmarkService.instance.bookmarkedEventIds, [
              'old-bookmark',
            ]);
            expect(api.encryptionKeys, [('key-author', 'author')]);
          case 'mute':
            expect(EncryptedMuteService.instance.mutedPubkeys, ['old-mute']);
            expect(api.encryptionKeys, [('key-author', 'author')]);
          case 'follow set':
            expect(
              FollowSetService.instance.followSets.single.pubkey,
              'author',
            );
          case 'pinned notes':
            expect(PinnedNotesService.instance.pinnedNoteIds, ['old-pin']);
        }
      },
    );
  }
}
