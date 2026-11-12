import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/core/base/result.dart';
import '../../../../lib/data/repositories/following_repository.dart';
import '../../../../lib/data/repositories/profile_repository.dart';
import '../../../../lib/data/services/auth_service.dart';
import '../../../../lib/data/services/encrypted_mute_service.dart';
import '../../../../lib/data/sync/sync_service.dart';
import '../../../../lib/domain/entities/user_profile.dart';
import '../../../../lib/presentation/blocs/muted/muted_bloc.dart';
import '../../../../lib/presentation/blocs/muted/muted_event.dart';
import '../../../../lib/presentation/blocs/muted/muted_state.dart';

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
  String? npubToHex(String npub) => npub;

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync implements SyncService {
  Future<void> Function()? onSync;
  bool failPublish = false;
  Future<Map<String, dynamic>> Function()? onPublish;

  @override
  Future<void> syncMuteList(String userPubkey) async => onSync?.call();

  @override
  Future<void> syncProfiles(List<String> pubkeys) async {}

  @override
  Future<Map<String, dynamic>> publishMute({
    required List<String> mutedPubkeys,
    List<String>? mutedWords,
  }) async {
    if (failPublish) throw StateError('offline');
    return await onPublish?.call() ?? {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Sync sync;
  late _Auth auth;
  late MutedBloc bloc;
  final service = EncryptedMuteService.instance;

  setUp(() async {
    service.clear();
    await service.loadFromDatabase(userPubkeyHex: 'user', privateKeyHex: 'key');
    service.addMutedWord('old');
    sync = _Sync();
    auth = _Auth();
    bloc = MutedBloc(
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

  test(
    'keeps refresh emission in the handler lifetime and clears stale mutes',
    () async {
      final pending = Completer<void>();
      sync.onSync = () => pending.future;
      bloc.add(const MutedLoadRequested());
      await bloc.stream.firstWhere((state) => state is MutedLoaded);
      await Future<void>.delayed(Duration.zero);
      service.removeMutedWord('old');
      final refreshed = bloc.stream.firstWhere(
        (state) => state is MutedLoaded && state.mutedWords.isEmpty,
      );
      pending.complete();
      await refreshed;
      expect((bloc.state as MutedLoaded).mutedWords, isEmpty);
    },
  );

  test(
    'failed word changes roll back both filtering and displayed words',
    () async {
      bloc.add(const MutedLoadRequested());
      await bloc.stream.firstWhere((state) => state is MutedLoaded);
      await Future<void>.delayed(Duration.zero);
      sync.failPublish = true;
      for (final event in [
        const MutedWordAdded('new'),
        const MutedWordRemoved('old'),
      ]) {
        final error = bloc.stream.firstWhere((state) => state is MutedError);
        bloc.add(event);
        await error;
        await Future<void>.delayed(Duration.zero);
        expect((bloc.state as MutedLoaded).mutedWords, ['old']);
        expect(service.containsMutedWord('old'), isTrue);
        expect(service.containsMutedWord('new'), isFalse);
      }
    },
  );

  test('failed unmute restores the muted user', () async {
    service.addMutedPubkey('target');
    bloc.add(const MutedLoadRequested());
    await bloc.stream.firstWhere((state) => state is MutedLoaded);
    await Future<void>.delayed(Duration.zero);
    sync.failPublish = true;
    final error = bloc.stream.firstWhere((state) => state is MutedError);
    bloc.add(const MutedUserUnmuted('target'));
    await error;
    await Future<void>.delayed(Duration.zero);
    expect(service.isUserMuted('target'), isTrue);
    expect((bloc.state as MutedLoaded).mutedUsers.single['pubkey'], 'target');
    expect((bloc.state as MutedLoaded).unmutingStates, isEmpty);
  });

  test('failed initial synchronization becomes an error state', () async {
    service.clear();
    sync.onSync = () => Future.error(StateError('offline'));
    bloc.add(const MutedLoadRequested());
    await bloc.stream.firstWhere((state) => state is MutedError);
  });
  for (final event in [
    const MutedWordAdded('new'),
    const MutedWordRemoved('old'),
    const MutedUserUnmuted('target'),
  ]) {
    for (final transition in ['clear', 'identity', 'switchAndClose']) {
      test(
        '${event.runtimeType} cannot restore a prior session after $transition',
        () async {
          service.addMutedPubkey('target');
          bloc.add(const MutedLoadRequested());
          await bloc.stream.firstWhere((state) => state is MutedLoaded);
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
            service.removeMutedPubkey('target');
            service.removeMutedWord('old');
            service.removeMutedWord('new');
          }
          if (transition != 'clear') auth.currentUserPubkeyHex = 'other';
          service.addMutedPubkey('other-account-user');
          service.addMutedWord('new');
          final states = <MutedState>[];
          final subscription = bloc.stream.listen(states.add);
          final closing = transition == 'switchAndClose' ? bloc.close() : null;
          await Future<void>.delayed(Duration.zero);
          states.clear();
          pending.completeError(StateError('old publication failed'));
          if (closing != null) await closing;
          await Future<void>.delayed(Duration.zero);
          expect(service.mutedPubkeys, ['other-account-user']);
          expect(service.mutedWords, ['new']);
          expect(states, isEmpty);
          await subscription.cancel();
        },
      );
    }
  }
}
