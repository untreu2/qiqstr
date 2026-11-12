import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/core/di/modules/services_module.dart';
import '../../lib/data/services/encrypted_bookmark_service.dart';
import '../../lib/data/services/encrypted_mute_service.dart';
import '../../lib/data/services/follow_set_service.dart';
import '../../lib/src/rust/api/crypto.dart' as crypto;
import '../../lib/src/rust/api/database.dart' as db;
import '../../lib/src/rust/api/events.dart' as events;
import '../../lib/src/rust/api/nip17.dart' as dm;
import '../../lib/src/rust/api/relay.dart' as relay;
import '../support/native_rust.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String aliceKey;
  late String alice;
  late String bobKey;
  late String bob;

  setUpAll(() async {
    await initializeNativeRust();
    directory = await Directory.systemTemp.createTemp('qiqstr-native-test-');
    (aliceKey, alice) = crypto.generateKeypair();
    (bobKey, bob) = crypto.generateKeypair();
    await relay.initClient(
      relayUrls: [],
      discoveryRelays: [],
      privateKeyHex: aliceKey,
      dbPath: directory.path,
    );
  });
  setUp(() async {
    await db.dbWipe();
    await db.setActiveMuteList(mutedPubkeys: [], mutedWords: []);
  });
  tearDownAll(() async {
    await relay.initClient(relayUrls: [], discoveryRelays: []);
    await directory.delete(recursive: true);
  });

  test('signed profile, follow list, note, reply and reaction reach the feed',
      () async {
    final note = events.createNoteEvent(
      content: 'Hello #nostr',
      tags: [
        ['t', 'nostr']
      ],
      privateKeyHex: bobKey,
    );
    final id = jsonDecode(note)['id'] as String;
    final batch = [
      events.createProfileEvent(
          profileJson: jsonEncode({'name': 'Bob'}), privateKeyHex: bobKey),
      events
          .createFollowEvent(followingPubkeys: [bob], privateKeyHex: aliceKey),
      note,
      events.createReplyEvent(
        content: 'Reply',
        tags: [
          ['e', id, '', 'root'],
          ['p', bob]
        ],
        privateKeyHex: aliceKey,
      ),
      events.createReactionEvent(
        targetEventId: id,
        targetAuthor: bob,
        content: '+',
        privateKeyHex: aliceKey,
        relayUrl: '',
        targetKind: 1,
      ),
    ];
    expect(await db.dbSaveEvents(eventsJson: '[${batch.join(',')}]'), 5);
    expect(await db.dbGetFollowingList(pubkeyHex: alice), [bob]);
    expect(jsonDecode((await db.dbGetProfile(pubkeyHex: bob))!)['name'], 'Bob');
    final feed = jsonDecode(await db.dbGetHydratedFeedNotes(
      userPubkeyHex: alice,
      limit: 10,
      mutedPubkeys: [],
      mutedWords: [],
      filterReplies: true,
      currentUserPubkeyHex: alice,
    )) as List;
    expect(feed, hasLength(1));
    expect(feed.single['id'], id);
    final counts = jsonDecode(await db.dbGetInteractionCounts(noteId: id));
    expect(counts['reactions'], 1);
    final muted = jsonDecode(await db.dbGetHydratedFeedNotes(
      userPubkeyHex: alice,
      limit: 10,
      mutedPubkeys: [bob],
      mutedWords: [],
      filterReplies: true,
    ));
    expect(muted, isEmpty);
  });

  test('a tampered event cannot enter the database', () async {
    final note = jsonDecode(events.createNoteEvent(
      content: 'Authentic',
      tags: [],
      privateKeyHex: aliceKey,
    )) as Map<String, dynamic>;
    note['content'] = 'Forged content';
    expect(crypto.verifyEvent(eventJson: jsonEncode(note)), isFalse);
    await expectLater(
        db.dbSaveEvent(eventJson: jsonEncode(note)), throwsA(anything));
    expect(await db.dbEventExists(eventId: note['id']), isFalse);
  });

  test('signed notes persist when the native client reopens LMDB', () async {
    final note = events.createNoteEvent(
        content: 'Persistent note', tags: [], privateKeyHex: aliceKey);
    final id = jsonDecode(note)['id'] as String;
    await db.dbSaveEvent(eventJson: note);
    await relay.initClient(relayUrls: [], discoveryRelays: []);
    await relay
        .initClient(relayUrls: [], discoveryRelays: [], dbPath: directory.path);
    expect(await db.dbEventExists(eventId: id), isTrue);
    expect(jsonDecode((await db.dbGetEvent(eventId: id))!)['content'],
        'Persistent note');
  });

  test('only the author can delete a stored note', () async {
    final note = events.createNoteEvent(
        content: 'Bob owns this note', tags: [], privateKeyHex: bobKey);
    final id = jsonDecode(note)['id'] as String;
    await db.dbSaveEvent(eventJson: note);
    await db.dbSaveEvent(
        eventJson: events.createDeletionEvent(
            eventIds: [id], reason: '', privateKeyHex: aliceKey));
    expect(await db.dbEventExists(eventId: id), isTrue);
    await db.dbSaveEvent(
        eventJson: events.createDeletionEvent(
            eventIds: [id], reason: '', privateKeyHex: bobKey));
    expect(await db.dbEventExists(eventId: id), isFalse);
  });

  test('database cleanup leaves storage usable across client reinitialization',
      () async {
    final oldNote = events.createNoteEvent(
        content: 'Old note', tags: [], privateKeyHex: aliceKey);
    await db.dbSaveEvent(eventJson: oldNote);
    await db.dbWipeDirectory();
    expect(await db.dbEventExists(eventId: jsonDecode(oldNote)['id']), isFalse);
    final newNote = events.createNoteEvent(
        content: 'New note', tags: [], privateKeyHex: aliceKey);
    await db.dbSaveEvent(eventJson: newNote);
    await relay
        .initClient(relayUrls: [], discoveryRelays: [], dbPath: directory.path);
    expect(await db.dbEventExists(eventId: jsonDecode(newNote)['id']), isTrue);
  });

  test('batch imports skip forged events while retaining valid events',
      () async {
    final valid = jsonDecode(events.createNoteEvent(
      content: 'Valid',
      tags: [],
      privateKeyHex: aliceKey,
    ));
    final invalid = jsonDecode(events.createNoteEvent(
      content: 'Invalid',
      tags: [],
      privateKeyHex: bobKey,
    ));
    invalid['sig'] = '0' * 128;
    expect(await db.dbSaveEvents(eventsJson: jsonEncode([invalid, valid])), 1);
    expect(await db.dbEventExists(eventId: invalid['id']), isFalse);
    expect(await db.dbEventExists(eventId: valid['id']), isTrue);
  });

  test('encrypted DMs unwrap only for the recipient and sender copy', () {
    final wrapped = dm.createGiftWrapDm(
      senderPrivateKeyHex: aliceKey,
      receiverPubkeyHex: bob,
      message: 'Private hello',
    );
    final received = jsonDecode(dm.unwrapGiftWrapDm(
      receiverPrivateKeyHex: bobKey,
      giftWrapJson: wrapped,
      currentUserPubkeyHex: bob,
    ));
    expect(received['content'], 'Private hello');
    expect(received['senderPubkeyHex'], alice);
    expect(received['isFromCurrentUser'], isFalse);
    expect(
        () => dm.unwrapGiftWrap(
            receiverPrivateKeyHex: aliceKey, giftWrapJson: wrapped),
        throwsA(anything));
    final self = dm.createGiftWrapDmForSender(
      senderPrivateKeyHex: aliceKey,
      receiverPubkeyHex: bob,
      message: 'Private hello',
    );
    final sent = jsonDecode(dm.unwrapGiftWrapDm(
      receiverPrivateKeyHex: aliceKey,
      giftWrapJson: self,
      currentUserPubkeyHex: alice,
    ));
    expect(sent['isFromCurrentUser'], isTrue);
    expect(sent['recipientPubkeyHex'], bob);
  });

  test('rejects a gift wrap with a forged outer signature', () {
    final wrapped = jsonDecode(dm.createGiftWrapDm(
      senderPrivateKeyHex: aliceKey,
      receiverPubkeyHex: bob,
      message: 'Private hello',
    ));
    wrapped['sig'] = '0' * 128;
    expect(
        () => dm.unwrapGiftWrap(
            receiverPrivateKeyHex: bobKey, giftWrapJson: jsonEncode(wrapped)),
        throwsA(anything));
  });

  test('encrypted attachment round-trips and rejects a wrong key', () {
    final key = crypto.generateAesKey();
    final nonce = crypto.generateAesNonce();
    final plaintext = utf8.encode('An encrypted attachment');
    final ciphertext =
        crypto.aesGcmEncrypt(data: plaintext, keyHex: key, nonceHex: nonce);
    expect(
        crypto.aesGcmDecrypt(
            encryptedBase64: ciphertext, keyHex: key, nonceHex: nonce),
        plaintext);
    expect(
        () => crypto.aesGcmDecrypt(
            encryptedBase64: ciphertext,
            keyHex: crypto.generateAesKey(),
            nonceHex: nonce),
        throwsA(anything));
  });

  test('session reset clears private lists and pending cache loads', () async {
    final bookmarks = EncryptedBookmarkService.instance;
    final mute = EncryptedMuteService.instance;
    final sets = FollowSetService.instance;
    bookmarks.updateCache(eventIds: ['private-bookmark']);
    mute.updateCache(pubkeys: [bob], words: ['blocked']);
    expect(mute.containsMutedWord('BLOCKED text'), isTrue);
    final pending = bookmarks.loadFromDatabase(
        userPubkeyHex: alice, privateKeyHex: aliceKey);
    await ServicesModule.clearAccountCaches();
    await pending;
    expect(bookmarks.bookmarkedEventIds, isEmpty);
    expect(bookmarks.isInitialized, isFalse);
    expect(mute.mutedPubkeys, isEmpty);
    expect(mute.containsMutedWord('blocked'), isFalse);
    expect(sets.isInitialized, isFalse);
  });

  test('muted word edits immediately update matching', () {
    final mute = EncryptedMuteService.instance..clear();
    mute.addMutedWord(' Spam ');
    expect(mute.containsMutedWord('SPAM here'), isTrue);
    mute.removeMutedWord('spam');
    mute.addMutedWord('ads');
    expect(mute.containsMutedWord('spam here'), isFalse);
    expect(mute.containsMutedWord('ads here'), isTrue);
    mute.clear();
  });
}
