import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/data/repositories/profile_repository.dart';
import '../../../../lib/data/services/auth_service.dart';
import '../../../../lib/data/sync/sync_service.dart';
import '../../../../lib/domain/entities/user_profile.dart';
import '../../../../lib/presentation/blocs/note/note_bloc.dart';
import '../../../../lib/presentation/blocs/note/note_event.dart';
import '../../../../lib/presentation/blocs/note/note_state.dart';

class _Auth implements AuthService {
  @override
  String? currentUserPubkeyHex = 'user';

  @override
  String encodeNoteId(String eventId) => 'note1$eventId';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profiles implements ProfileRepository {
  final search = Completer<List<UserProfile>>();

  @override
  Future<List<UserProfile>> searchProfiles(String query, {int limit = 50}) =>
      search.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync implements SyncService {
  final upload = Completer<String?>();
  final publication = Completer<Map<String, dynamic>>();
  final published = <Map<String, dynamic>>[];

  @override
  Future<String?> uploadMedia(
    String filePath, {
    String blossomUrl = 'https://blossom.primal.net',
  }) => upload.future;

  @override
  Future<Map<String, dynamic>> publishNote({
    required String content,
    List<List<String>>? tags,
  }) {
    published.add({'content': content, 'tags': tags});
    return publication.future;
  }

  @override
  Future<Map<String, dynamic>> publishReply({
    required String content,
    required String rootId,
    String? replyToId,
    required String parentAuthor,
    String? replyAuthor,
    List<List<String>>? tags,
  }) {
    published.add({
      'content': content,
      'rootId': rootId,
      'replyToId': replyToId,
    });
    return publication.future;
  }

  @override
  Future<Map<String, dynamic>> publishQuote({
    required String content,
    required String quotedNoteId,
    String? quotedAuthor,
    List<List<String>>? tags,
  }) {
    published.add({'content': content, 'quotedNoteId': quotedNoteId});
    return publication.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late NoteBloc bloc;
  late _Sync sync;
  late _Profiles profiles;

  setUp(() {
    sync = _Sync();
    profiles = _Profiles();
    bloc = NoteBloc(
      profileRepository: profiles,
      syncService: sync,
      authService: _Auth(),
    );
  });

  tearDown(() async {
    await bloc.close();
  });

  test('clearing a draft discards an in-flight upload', () async {
    bloc.add(const NoteMediaUploaded(['/video.mp4']));
    await bloc.stream.firstWhere(
      (state) => state is NoteComposeState && state.isUploadingMedia,
    );
    bloc.add(const NoteContentCleared());
    await bloc.stream.firstWhere(
      (state) => state is NoteComposeState && !state.isUploadingMedia,
    );
    sync.upload.complete('https://example.com/private.mp4');
    await _flush();
    expect((bloc.state as NoteComposeState).mediaUrls, isEmpty);
    expect((bloc.state as NoteComposeState).canPost, isFalse);
  });

  test('clearing a draft discards delayed mention suggestions', () async {
    bloc.add(const NoteUserSearchRequested('alice'));
    await _flush();
    bloc.add(const NoteContentCleared());
    await _flush();
    profiles.search.complete([
      const UserProfile(pubkey: 'alice', name: 'Alice'),
    ]);
    await _flush();
    expect((bloc.state as NoteComposeState).userSuggestions, isEmpty);
    expect((bloc.state as NoteComposeState).isSearchingUsers, isFalse);
  });

  test('failed publication preserves edits made while publishing', () async {
    bloc.add(const NoteContentChanged('original'));
    await _flush();
    bloc.add(const NoteComposed(content: 'original'));
    await bloc.stream.firstWhere(
      (state) => state is NoteComposeState && state.isPublishing,
    );
    bloc.add(const NoteContentChanged('edited while publishing'));
    await _flush();
    final failure = bloc.stream.firstWhere((state) => state is NoteError);
    sync.publication.completeError(StateError('offline'));
    await failure;
    await _flush();
    expect((bloc.state as NoteComposeState).content, 'edited while publishing');
    expect((bloc.state as NoteComposeState).isPublishing, isFalse);
  });

  test('repeated submit events publish only once', () async {
    bloc.add(const NoteContentChanged('hello'));
    await _flush();
    bloc.add(const NoteComposed(content: 'hello'));
    bloc.add(const NoteComposed(content: 'hello'));
    await _flush();
    expect(sync.published.length, 1);
    sync.publication.complete({'id': 'published'});
    await bloc.stream.firstWhere((state) => state is NoteComposedSuccess);
  });

  test('reply setup clears a previous nested reply target', () async {
    bloc.add(
      const NoteReplySetup(
        rootId: 'old-root',
        replyId: 'old-child',
        parentAuthor: 'author',
      ),
    );
    await _flush();
    bloc.add(const NoteReplySetup(rootId: 'new-root', parentAuthor: 'author'));
    bloc.add(const NoteContentChanged('reply'));
    await _flush();
    bloc.add(const NoteComposed(content: 'reply'));
    await _flush();
    expect(sync.published.single['rootId'], 'new-root');
    expect(sync.published.single['replyToId'], isNull);
    sync.publication.complete({'id': 'reply'});
    await bloc.stream.firstWhere((state) => state is NoteComposedSuccess);
  });

  test(
    'quotes append an encoded reference and allow empty commentary',
    () async {
      bloc.add(const NoteQuoteSetup('target'));
      await _flush();
      bloc.add(const NoteComposed(content: ''));
      await _flush();
      expect(sync.published.single['content'], 'nostr:note1target');
      expect(sync.published.single['quotedNoteId'], 'target');
      sync.publication.complete({'id': 'quote'});
      await bloc.stream.firstWhere((state) => state is NoteComposedSuccess);
    },
  );

  test(
    'media URLs deduplicate, reorder, and update posting eligibility',
    () async {
      bloc.add(
        const NoteMediaUploaded([
          'https://example.com/one',
          'https://example.com/two',
          'https://example.com/one',
        ]),
      );
      await _flush();
      expect((bloc.state as NoteComposeState).mediaUrls.length, 2);
      bloc.add(const NoteMediaReordered(oldIndex: 0, newIndex: 1));
      await _flush();
      expect(
        (bloc.state as NoteComposeState).mediaUrls.first,
        'https://example.com/two',
      );
      bloc.add(const NoteMediaRemoved('https://example.com/one'));
      bloc.add(const NoteMediaRemoved('https://example.com/two'));
      await _flush();
      expect((bloc.state as NoteComposeState).mediaUrls, isEmpty);
      expect((bloc.state as NoteComposeState).canPost, isFalse);
    },
  );
}
