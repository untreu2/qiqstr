import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/data/repositories/following_repository.dart';
import '../../../../lib/data/repositories/profile_repository.dart';
import '../../../../lib/data/services/auth_service.dart';
import '../../../../lib/data/sync/sync_service.dart';
import '../../../../lib/domain/entities/user_profile.dart';
import '../../../../lib/presentation/blocs/following/following_bloc.dart';
import '../../../../lib/presentation/blocs/following/following_event.dart';
import '../../../../lib/presentation/blocs/following/following_state.dart';

class _Following implements FollowingRepository {
  final updates = StreamController<List<String>>.broadcast();

  @override
  Stream<List<String>> watchFollowing(String pubkey) => updates.stream;

  @override
  Future<List<String>?> getFollowing(String pubkey) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profiles implements ProfileRepository {
  final pending = <Completer<Map<String, UserProfile>>>[];

  @override
  Future<Map<String, UserProfile>> getProfiles(List<String> pubkeys) {
    final request = Completer<Map<String, UserProfile>>();
    pending.add(request);
    return request.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements AuthService {
  @override
  String? hexToNpub(String hex) => 'npub1$hex';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync implements SyncService {
  @override
  Future<void> syncFollowingList(String pubkey) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FollowingBloc bloc;
  late _Following following;
  late _Profiles profiles;

  setUp(() async {
    following = _Following();
    profiles = _Profiles();
    bloc = FollowingBloc(
      followingRepository: following,
      profileRepository: profiles,
      syncService: _Sync(),
      authService: _Auth(),
    );
    bloc.add(const FollowingLoadRequested(userNpub: 'user'));
    await bloc.stream.firstWhere((state) => state is FollowingLoaded);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() async {
    await bloc.close();
    await following.updates.close();
  });

  test(
    'an empty latest following list wins over a delayed old profile lookup',
    () async {
      following.updates.add(['old']);
      await Future<void>.delayed(Duration.zero);
      following.updates.add([]);
      await Future<void>.delayed(Duration.zero);
      profiles.pending.single.complete({
        'old': const UserProfile(pubkey: 'old', name: 'Old'),
      });
      await Future<void>.delayed(Duration.zero);
      expect((bloc.state as FollowingLoaded).followingUsers, isEmpty);
    },
  );

  test(
    'followed users remain visible when metadata is not available',
    () async {
      following.updates.add(['unknown']);
      await Future<void>.delayed(Duration.zero);
      profiles.pending.single.complete({});
      await bloc.stream.firstWhere(
        (state) => state is FollowingLoaded && state.followingUsers.isNotEmpty,
      );
      expect(
        (bloc.state as FollowingLoaded).followingUsers.single['pubkey'],
        'unknown',
      );
      expect(
        (bloc.state as FollowingLoaded).loadedUsers.containsKey('npub1unknown'),
        isTrue,
      );
    },
  );
}
