import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/data/repositories/article_repository.dart';
import '../../../../lib/data/repositories/feed_repository.dart';
import '../../../../lib/data/repositories/following_repository.dart';
import '../../../../lib/data/repositories/profile_repository.dart';
import '../../../../lib/data/services/auth_service.dart';
import '../../../../lib/data/sync/sync_service.dart';
import '../../../../lib/domain/entities/article.dart';
import '../../../../lib/domain/entities/feed_note.dart';
import '../../../../lib/domain/entities/user_profile.dart';
import '../../../../lib/presentation/blocs/profile/profile_bloc.dart';
import '../../../../lib/presentation/blocs/profile/profile_event.dart';
import '../../../../lib/presentation/blocs/profile/profile_state.dart';

class _Auth implements AuthService {
  @override
  String? get currentUserPubkeyHex => 'a' * 64;

  @override
  String? npubToHex(String npub) => null;

  @override
  String? hexToNpub(String hex) => hex;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profiles implements ProfileRepository {
  @override
  Future<UserProfile?> getProfile(String pubkey) async => null;

  @override
  Stream<UserProfile?> watchProfile(String pubkey) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Feed implements FeedRepository {
  @override
  Stream<({List<FeedNote> notes, List<FeedNote> replies})>
  watchProfileNotesAndReplies(
    String pubkey, {
    int notesLimit = 200,
    int repliesLimit = 200,
    int debounceMs = 300,
  }) => const Stream.empty();

  @override
  Stream<List<FeedNote>> watchLikes(String pubkey, {int limit = 50}) =>
      const Stream.empty();

  @override
  Future<List<FeedNote>> getNotes(
    String pubkey, {
    int limit = 50,
    int? untilTimestamp,
  }) async => [];

  @override
  Future<List<FeedNote>> getUserReplies(
    String pubkey, {
    int limit = 50,
    int? untilTimestamp,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Following implements FollowingRepository {
  bool following = true;

  @override
  Future<bool> isFollowing(String user, String target) async => following;

  @override
  Future<void> follow(String user, String target) async => following = true;

  @override
  Future<void> unfollow(String user, String target) async => following = false;

  @override
  Future<List<String>?> getFollowing(String user) async =>
      following ? ['b' * 64] : [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Articles implements ArticleRepository {
  @override
  Future<List<Article>> getArticles({
    List<String>? authors,
    int limit = 50,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync implements SyncService {
  final publication = Completer<Map<String, dynamic>>();

  @override
  Future<void> syncProfile(String pubkey) async {}

  @override
  Stream<int> streamProfileNotesProgress(
    String pubkey, {
    int limit = 100,
    bool force = false,
  }) => const Stream.empty();

  @override
  Future<void> syncProfileReactions(
    String pubkey, {
    int limit = 100,
    bool force = false,
  }) async {}

  @override
  Future<void> syncPinnedNotes(String pubkey) async {}

  @override
  Future<Map<String, dynamic>> publishFollow({
    required List<String> followingPubkeys,
  }) => publication.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ProfileBloc bloc;
  late _Following following;
  late _Sync sync;
  final target = 'b' * 64;

  setUp(() {
    following = _Following();
    sync = _Sync();
    bloc = ProfileBloc(
      feedRepository: _Feed(),
      profileRepository: _Profiles(),
      followingRepository: following,
      articleRepository: _Articles(),
      syncService: sync,
      authService: _Auth(),
    );
  });

  tearDown(() async => bloc.close());

  test(
    'uncached profiles preserve the actual following relationship',
    () async {
      bloc.add(ProfileLoadRequested(target));
      await bloc.stream.firstWhere((state) => state is ProfileLoaded);
      expect((bloc.state as ProfileLoaded).isFollowing, isTrue);
    },
  );

  test(
    'failed unfollow restores the relationship without discarding fresh profile data',
    () async {
      bloc.add(ProfileLoadRequested(target));
      await bloc.stream.firstWhere((state) => state is ProfileLoaded);
      bloc.add(const ProfileFollowToggled());
      await bloc.stream.firstWhere(
        (state) => state is ProfileLoaded && !state.isFollowing,
      );
      bloc.add(ProfileUserUpdated({'pubkey': target, 'name': 'Fresh name'}));
      await bloc.stream.firstWhere(
        (state) => state is ProfileLoaded && state.user['name'] == 'Fresh name',
      );
      sync.publication.completeError(StateError('offline'));
      await bloc.stream.firstWhere(
        (state) => state is ProfileLoaded && state.followError != null,
      );
      expect((bloc.state as ProfileLoaded).user['name'], 'Fresh name');
      expect((bloc.state as ProfileLoaded).isFollowing, isTrue);
      expect(following.following, isTrue);
    },
  );
}
