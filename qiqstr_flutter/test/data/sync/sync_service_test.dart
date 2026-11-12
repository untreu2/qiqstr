import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../lib/core/base/result.dart';
import '../../../lib/data/services/auth_service.dart';
import '../../../lib/data/services/follow_set_service.dart';
import '../../../lib/data/services/pinned_notes_service.dart';
import '../../../lib/domain/entities/follow_set.dart';
import '../../../lib/data/services/rust_database_service.dart';
import '../../../lib/data/sync/publishers/event_publisher.dart';
import '../../../lib/data/sync/sync_service.dart';
import '../../../lib/src/rust/frb_generated.dart';

class _Api implements RustLibApi {
  final savedEvents = <Map<String, dynamic>>[];
  final sentEvents = <Map<String, dynamic>>[];
  bool rejectPublish = false;
  Completer<String>? relayResponse;
  Completer<void>? relayStarted;
  int followSetReads = 0;
  int pinReads = 0;
  StreamController<String>? profileEvents;
  Completer<void>? profileStreamStarted;

  @override
  Stream<String> crateApiRelayFetchProfileEvents({
    required String authorHex,
    required String kindsStr,
    required int sinceTimestamp,
  }) {
    profileStreamStarted?.complete();
    return profileEvents!.stream;
  }

  @override
  Future<int> crateApiDatabaseDbProcessDeletionEvents() async => 0;

  @override
  Future<String> crateApiDatabaseDbQueryEvents({
    required String filterJson,
    required int limit,
  }) async {
    pinReads++;
    return '[]';
  }

  List<Map<String, dynamic>> followSetRows = [];

  @override
  Future<List<String>> crateApiDatabaseDbGetFollowingList({
    required String pubkeyHex,
  }) async => [];

  @override
  Future<String> crateApiDatabaseDbGetFollowSets({
    required List<String> authorsHex,
    required int limit,
    required List<String> hiddenDTags,
  }) async {
    followSetReads++;
    return jsonEncode(followSetRows);
  }

  @override
  Future<String> crateApiRelayFetchEvents({
    required String filterJson,
    required int timeoutSecs,
  }) async {
    relayStarted?.complete();
    return relayResponse?.future ?? Future.value('[]');
  }

  @override
  Future<String> crateApiRelaySendEvent({required String eventJson}) async {
    sentEvents.add(jsonDecode(eventJson) as Map<String, dynamic>);
    return jsonEncode({
      'success': rejectPublish ? [] : ['wss://relay.example'],
    });
  }

  @override
  Future<int> crateApiDatabaseDbSaveEvents({required String eventsJson}) async {
    final events = (jsonDecode(eventsJson) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    savedEvents.addAll(events);
    return events.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Publisher implements EventPublisher {
  Map<String, dynamic> event = {};
  List<String>? following;
  Completer<void>? creationGate;

  @override
  Future<Map<String, dynamic>> createFollow({
    required List<String> followingPubkeys,
  }) async {
    following = followingPubkeys;
    if (creationGate != null) await creationGate!.future;
    return event;
  }

  @override
  Future<Map<String, dynamic>> createProfileUpdate({
    required Map<String, dynamic> profileContent,
  }) async => event;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements AuthService {
  @override
  String? currentUserPubkeyHex = 'author';
  int privateKeyReads = 0;
  Completer<Result<String?>>? publicKeyRead;
  Completer<void>? publicKeyReadStarted;

  @override
  Future<Result<String?>> getCurrentUserPrivateKey() async {
    privateKeyReads++;
    return const Success('key');
  }

  @override
  Future<Result<String?>> getCurrentUserPublicKeyHex() async {
    publicKeyReadStarted?.complete();
    return publicKeyRead?.future ?? Future.value(Success(currentUserPubkeyHex));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Api api;
  late _Publisher publisher;
  late SyncService service;
  late _Auth auth;

  setUpAll(() {
    api = _Api();
    RustLib.initMock(api: api);
  });

  tearDownAll(RustLib.dispose);

  setUp(() {
    api.savedEvents.clear();
    api.sentEvents.clear();
    api.rejectPublish = false;
    api.relayResponse = null;
    api.relayStarted = null;
    api.followSetReads = 0;
    api.pinReads = 0;
    api.profileEvents = null;
    api.profileStreamStarted = null;
    PinnedNotesService.instance.clear();
    api.followSetRows = [];
    FollowSetService.instance.clear();
    auth = _Auth();
    publisher = _Publisher();
    service = SyncService(
      db: RustDatabaseService.instance,
      publisher: publisher,
      authService: auth,
    );
  });

  tearDown(() {
    service.dispose();
    FollowSetService.instance.clear();
  });

  for (final kind in [0, 3]) {
    test(
      'publishing kind $kind preserves only the exact signed event in cache',
      () async {
        publisher.event = {
          'id': 'signed-id',
          'pubkey': 'author',
          'kind': kind,
          'created_at': 123,
          'content': '{}',
          'tags': [
            ['p', 'followed'],
          ],
          'sig': 'signature',
        };
        final result = kind == 3
            ? await service.publishFollow(
                followingPubkeys: ['followed', 'followed', ''],
              )
            : await service.publishProfileUpdate(
                profileContent: {'name': 'Alice'},
              );
        expect(result, publisher.event);
        expect(api.savedEvents, [publisher.event]);
        expect(api.sentEvents, [publisher.event]);
        if (kind == 3) expect(publisher.following, ['followed']);
      },
    );
  }

  test('rejected publications never alter the signed event cache', () async {
    api.rejectPublish = true;
    publisher.event = {'id': 'rejected', 'pubkey': 'author', 'kind': 3};
    await expectLater(
      service.publishFollow(followingPubkeys: ['target']),
      throwsStateError,
    );
    expect(api.savedEvents, isEmpty);
  });

  for (final boundary in ['account change', 'cache clear', 'dispose']) {
    test('follow-set sync stops after $boundary during relay fetch', () async {
      api.relayResponse = Completer<String>();
      api.relayStarted = Completer<void>();
      final pending = service.syncFollowSets('author');
      await api.relayStarted!.future;
      if (boundary == 'account change') auth.currentUserPubkeyHex = 'next';
      if (boundary == 'cache clear') FollowSetService.instance.clear();
      if (boundary == 'dispose') service.dispose();
      const nextSet = FollowSet(
        id: 'next-id',
        pubkey: 'next',
        dTag: 'list',
        createdAt: 1,
      );
      FollowSetService.instance.addSet(nextSet);
      api.relayResponse!.complete('[]');
      await pending;
      expect(FollowSetService.instance.followSets, [nextSet]);
      expect(api.followSetReads, 0);
    });

    test('event creation followed by $boundary cannot publish', () async {
      publisher.creationGate = Completer<void>();
      publisher.event = {'id': 'event', 'pubkey': 'author', 'kind': 3};
      final pending = service.publishFollow(followingPubkeys: ['target']);
      final expectation = expectLater(pending, throwsStateError);
      if (boundary == 'account change') auth.currentUserPubkeyHex = 'next';
      if (boundary == 'cache clear') FollowSetService.instance.clear();
      if (boundary == 'dispose') service.dispose();
      publisher.creationGate!.complete();
      await expectation;
      expect(api.sentEvents, isEmpty);
      expect(api.savedEvents, isEmpty);
    });
  }

  for (final list in ['bookmark', 'mute']) {
    test(
      '$list sync cannot restart a cache load after an account switch',
      () async {
        api.relayResponse = Completer<String>();
        api.relayStarted = Completer<void>();
        final pending = list == 'bookmark'
            ? service.syncBookmarkList('author')
            : service.syncMuteList('author');
        await api.relayStarted!.future;
        auth.currentUserPubkeyHex = 'next';
        FollowSetService.instance.clear();
        api.relayResponse!.complete('[]');
        await pending;
        expect(auth.privateKeyReads, 0);
      },
    );
  }

  test(
    'sync clears followed-user sets after unfollowing the last user',
    () async {
      const oldSet = FollowSet(
        id: 'old',
        pubkey: 'friend',
        dTag: 'list',
        createdAt: 1,
      );
      api.followSetRows = [oldSet.toMap()];
      await FollowSetService.instance.loadFollowedUsersSets(
        followedPubkeys: ['friend'],
      );
      expect(FollowSetService.instance.followedUsersSets, [oldSet]);
      api.followSetRows = [];
      await service.syncFollowSets('author');
      expect(FollowSetService.instance.followedUsersSets, isEmpty);
    },
  );

  test(
    'a signing-key mismatch cannot publish under another identity',
    () async {
      publisher.event = {'id': 'other', 'pubkey': 'next', 'kind': 3};
      await expectLater(
        service.publishFollow(followingPubkeys: ['target']),
        throwsStateError,
      );
      expect(api.sentEvents, isEmpty);
      expect(api.savedEvents, isEmpty);
    },
  );
  test(
    'pinned-note sync stops after cache clear even when account returns to A',
    () async {
      api.relayStarted = Completer<void>();
      api.relayResponse = Completer<String>();
      final pending = service.syncPinnedNotes('author');
      await api.relayStarted!.future;
      FollowSetService.instance.clear();
      PinnedNotesService.instance.clear();
      PinnedNotesService.instance.pinNote('new-session-pin');
      api.relayResponse!.complete('[]');
      await pending;
      expect(api.pinReads, 0);
      expect(PinnedNotesService.instance.pinnedNoteIds, ['new-session-pin']);
    },
  );

  test(
    'pinned-note sync rejects an identity read completed after switching',
    () async {
      auth.publicKeyRead = Completer<Result<String?>>();
      auth.publicKeyReadStarted = Completer<void>();
      final pending = service.syncPinnedNotes('author');
      await auth.publicKeyReadStarted!.future;
      auth.currentUserPubkeyHex = 'next';
      PinnedNotesService.instance.pinNote('next-pin');
      auth.publicKeyRead!.complete(const Success('author'));
      await pending;
      expect(api.pinReads, 0);
      expect(PinnedNotesService.instance.pinnedNoteIds, ['next-pin']);
    },
  );

  test('pinned-note sync still loads the current account', () async {
    PinnedNotesService.instance.pinNote('old-pin');
    await service.syncPinnedNotes('author');
    expect(api.pinReads, 1);
    expect(PinnedNotesService.instance.pinnedNoteIds, isEmpty);
  });
  for (final fail in [false, true]) {
    test(
      'profile progress ${fail ? 'error' : 'completion'} after disposal does not emit to closed status stream',
      () async {
        api.profileEvents = StreamController<String>();
        api.profileStreamStarted = Completer<void>();
        final statuses = service.syncStatus.toList();
        final progress = service.streamProfileNotesProgress('author').toList();
        await api.profileStreamStarted!.future;
        service.dispose();
        if (fail) api.profileEvents!.addError(StateError('relay disconnected'));
        await api.profileEvents!.close();
        expect(await progress, [0]);
        expect((await statuses).map((status) => status.state), [
          SyncOperationState.syncing,
        ]);
      },
    );
  }
}
