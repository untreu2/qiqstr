import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../lib/core/base/result.dart';
import '../../../../lib/data/repositories/following_repository.dart';
import '../../../../lib/data/repositories/profile_repository.dart';
import '../../../../lib/data/services/auth_service.dart';
import '../../../../lib/data/services/follow_set_service.dart';
import '../../../../lib/data/sync/sync_service.dart';
import '../../../../lib/domain/entities/follow_set.dart';
import '../../../../lib/domain/entities/user_profile.dart';
import '../../../../lib/presentation/blocs/follow_set/follow_set_bloc.dart';
import '../../../../lib/presentation/blocs/follow_set/follow_set_event.dart';
import '../../../../lib/presentation/blocs/follow_set/follow_set_state.dart';

class _Auth implements AuthService {
  @override
  String? currentUserPubkeyHex = 'user';

  @override
  Future<Result<String>> getCurrentUserPublicKeyHex() async =>
      currentUserPubkeyHex == null
      ? Result.error('Not authenticated')
      : Success(currentUserPubkeyHex!);

  @override
  String? hexToNpub(String hex) => hex;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profiles implements ProfileRepository {
  @override
  Future<Map<String, UserProfile>> getProfiles(List<String> pubkeys) async =>
      {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Following implements FollowingRepository {
  @override
  Future<List<String>?> getFollowing(String pubkey) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync implements SyncService {
  Future<void> Function()? onSync;
  bool failPublish = false;
  Future<Map<String, dynamic>> Function()? onPublish;
  String? lastDTag;

  @override
  Future<void> syncFollowSets(String userPubkey) async => onSync?.call();

  @override
  Future<void> syncProfiles(List<String> pubkeys) async {}

  @override
  Future<Map<String, dynamic>> publishFollowSet({
    required String dTag,
    required String title,
    required String description,
    required String image,
    required List<String> pubkeys,
  }) async {
    lastDTag = dTag;
    if (failPublish) throw StateError('offline');
    return await onPublish?.call() ?? {};
  }

  @override
  Future<Map<String, dynamic>> publishDeletion({
    required List<String> eventIds,
    String? reason,
  }) async {
    if (failPublish) throw StateError('offline');
    return await onPublish?.call() ?? {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Sync sync;
  late _Auth auth;
  late FollowSetBloc bloc;
  final service = FollowSetService.instance;
  const initialSet = FollowSet(
    id: 'event-id',
    pubkey: 'user',
    dTag: 'friends',
    pubkeys: ['alice'],
    createdAt: 1,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service.clear();
    await service.loadFromDatabase(userPubkeyHex: 'user');
    service.addSet(initialSet);
    sync = _Sync();
    auth = _Auth();
    bloc = FollowSetBloc(
      followingRepository: _Following(),
      profileRepository: _Profiles(),
      syncService: sync,
      authService: auth,
    );
  });

  tearDown(() async {
    await bloc.close();
    service.clear();
  });

  test('publishes synchronized lists within the live handler', () async {
    final pending = Completer<void>();
    sync.onSync = () => pending.future;
    bloc.add(const FollowSetLoadRequested());
    await bloc.stream.firstWhere((state) => state is FollowSetLoaded);
    await Future<void>.delayed(Duration.zero);
    service.addSet(initialSet.copyWith(title: 'Updated'));
    final refreshed = bloc.stream.firstWhere(
      (state) =>
          state is FollowSetLoaded &&
          state.followSets.single.title == 'Updated',
    );
    pending.complete();
    await refreshed;
  });

  test(
    'serializes rapid favorite changes without losing earlier selections',
    () async {
      bloc.add(const FollowSetLoadRequested());
      await bloc.stream.firstWhere((state) => state is FollowSetLoaded);
      bloc.add(const FollowSetFavoriteToggled('one'));
      bloc.add(const FollowSetFavoriteToggled('two'));
      await bloc.stream.firstWhere(
        (state) => state is FollowSetLoaded && state.favoriteIds.length == 2,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('favorite_follow_set_ids'), ['one', 'two']);
    },
  );

  test(
    'list deletion changes the cache only after accepted publication',
    () async {
      bloc.add(const FollowSetLoadRequested());
      await bloc.stream.firstWhere((state) => state is FollowSetLoaded);
      sync.failPublish = true;
      final failure = bloc.stream.firstWhere(
        (state) => state is FollowSetError,
      );
      bloc.add(const FollowSetDeleted('friends'));
      await failure;
      await Future<void>.delayed(Duration.zero);
      expect(service.followSets, [initialSet]);
      sync.failPublish = false;
      bloc.add(const FollowSetDeleted('friends'));
      await bloc.stream.firstWhere(
        (state) => state is FollowSetLoaded && state.followSets.isEmpty,
      );
      expect(service.followSets, isEmpty);
    },
  );

  test('failed membership writes restore the list cache', () async {
    bloc.add(const FollowSetLoadRequested());
    await bloc.stream.firstWhere((state) => state is FollowSetLoaded);
    sync.failPublish = true;
    for (final event in [
      const FollowSetUserAdded(dTag: 'friends', pubkeyHex: 'bob'),
      const FollowSetUserRemoved(dTag: 'friends', pubkeyHex: 'alice'),
    ]) {
      final failure = bloc.stream.firstWhere(
        (state) => state is FollowSetError,
      );
      bloc.add(event);
      await failure;
      await Future<void>.delayed(Duration.zero);
      expect(service.getByDTag('friends'), initialSet);
      expect((bloc.state as FollowSetLoaded).followSets, [initialSet]);
    }
  });
  for (final event in [
    const FollowSetUserAdded(dTag: 'friends', pubkeyHex: 'bob'),
    const FollowSetUserRemoved(dTag: 'friends', pubkeyHex: 'alice'),
    const FollowSetCreated(title: 'New list'),
  ]) {
    for (final transition in ['clear', 'identity', 'switchAndClose']) {
      test(
        '${event.runtimeType} cannot restore a prior session after $transition',
        () async {
          bloc.add(const FollowSetLoadRequested());
          await bloc.stream.firstWhere((state) => state is FollowSetLoaded);
          await Future<void>.delayed(Duration.zero);
          final pending = Completer<Map<String, dynamic>>();
          final started = Completer<void>();
          sync.onPublish = () {
            started.complete();
            return pending.future;
          };
          bloc.add(event);
          await started.future;
          if (transition != 'identity') {
            service.clear();
          } else {
            service.removeSet('friends');
          }
          if (transition != 'clear') auth.currentUserPubkeyHex = 'other';
          final otherSet = initialSet.copyWith(
            pubkey: 'other',
            dTag: sync.lastDTag,
            pubkeys: ['other-account-user'],
          );
          service.addSet(otherSet);
          final states = <FollowSetState>[];
          final subscription = bloc.stream.listen(states.add);
          final closing = transition == 'switchAndClose' ? bloc.close() : null;
          await Future<void>.delayed(Duration.zero);
          pending.completeError(StateError('old publication failed'));
          if (closing != null) await closing;
          await Future<void>.delayed(Duration.zero);
          expect(service.followSets, [otherSet]);
          expect(states, isEmpty);
          await subscription.cancel();
        },
      );
    }
  }

  test(
    'a completed deletion cannot remove a new account list with the same identifier',
    () async {
      bloc.add(const FollowSetLoadRequested());
      await bloc.stream.firstWhere((state) => state is FollowSetLoaded);
      await Future<void>.delayed(Duration.zero);
      final pending = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      sync.onPublish = () {
        started.complete();
        return pending.future;
      };
      bloc.add(const FollowSetDeleted('friends'));
      await started.future;
      service.clear();
      auth.currentUserPubkeyHex = 'other';
      final otherSet = initialSet.copyWith(
        pubkey: 'other',
        pubkeys: ['other-account-user'],
      );
      service.addSet(otherSet);
      pending.complete({});
      await Future<void>.delayed(Duration.zero);
      expect(service.followSets, [otherSet]);
    },
  );
}
