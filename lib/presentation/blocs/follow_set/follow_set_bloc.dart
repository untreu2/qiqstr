import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/follow_set_service.dart';
import '../../../domain/entities/follow_set.dart';
import '../../../src/rust/api/relay.dart' as rust_relay;
import 'follow_set_event.dart';
import 'follow_set_state.dart';

class FollowSetBloc extends Bloc<FollowSetEvent, FollowSetState> {
  final ProfileRepository _profileRepository;
  final FollowingRepository _followingRepository;
  final SyncService _syncService;
  final AuthService _authService;

  FollowSetBloc({
    required ProfileRepository profileRepository,
    required FollowingRepository followingRepository,
    required SyncService syncService,
    required AuthService authService,
  })  : _profileRepository = profileRepository,
        _followingRepository = followingRepository,
        _syncService = syncService,
        _authService = authService,
        super(const FollowSetInitial()) {
    on<FollowSetLoadRequested>(_onLoadRequested);
    on<FollowSetCreated>(_onCreated);
    on<FollowSetDeleted>(_onDeleted);
    on<FollowSetUserAdded>(_onUserAdded);
    on<FollowSetUserRemoved>(_onUserRemoved);
    on<FollowSetRefreshed>(_onRefreshed);
  }

  Future<void> _onLoadRequested(
    FollowSetLoadRequested event,
    Emitter<FollowSetState> emit,
  ) async {
    final pubkeyResult = await _authService.getCurrentUserPublicKeyHex();
    if (pubkeyResult.isError || pubkeyResult.data == null) {
      emit(const FollowSetError('Not authenticated'));
      return;
    }
    final currentUserHex = pubkeyResult.data!;
    final service = FollowSetService.instance;

    if (!service.isInitialized) {
      await service.loadFromDatabase(userPubkeyHex: currentUserHex);

      final follows =
          await _followingRepository.getFollowingList(currentUserHex);
      if (follows != null && follows.isNotEmpty) {
        await service.loadFollowedUsersSets(followedPubkeys: follows);
      }
    }

    if (service.followSets.isNotEmpty ||
        service.followedUsersSets.isNotEmpty) {
      final resolved = await _resolveProfiles(service.allSets);
      emit(FollowSetLoaded(
        followSets: service.followSets,
        followedUsersSets: service.followedUsersSets,
        resolvedProfiles: resolved.profiles,
        resolvedAuthors: resolved.authors,
      ));
      _syncInBackground(currentUserHex, emit);
    } else {
      emit(const FollowSetLoaded(followSets: []));
      _syncInBackground(currentUserHex, emit);
    }
  }

  Future<({Map<String, List<Map<String, dynamic>>> profiles, Map<String, Map<String, String>> authors})>
      _resolveProfiles(List<FollowSet> sets) async {
    final allPubkeys = <String>{};
    for (final set in sets) {
      allPubkeys.addAll(set.pubkeys);
      allPubkeys.add(set.pubkey);
    }
    if (allPubkeys.isEmpty) {
      return (profiles: <String, List<Map<String, dynamic>>>{}, authors: <String, Map<String, String>>{});
    }

    final profilesMap =
        await _profileRepository.getProfiles(allPubkeys.toList());

    final result = <String, List<Map<String, dynamic>>>{};
    final authors = <String, Map<String, String>>{};

    for (final set in sets) {
      final key = '${set.pubkey}:${set.dTag}';
      final users = <Map<String, dynamic>>[];
      for (final pubkey in set.pubkeys) {
        final profile = profilesMap[pubkey];
        final npub = _authService.hexToNpub(pubkey) ?? pubkey;
        if (profile != null) {
          users.add({
            'pubkey': pubkey,
            'npub': npub,
            'name': profile.name ?? profile.displayName ?? '',
            'picture': profile.picture ?? '',
          });
        } else {
          final shortName = npub.length > 12
              ? '${npub.substring(0, 8)}...${npub.substring(npub.length - 4)}'
              : npub;
          users.add({
            'pubkey': pubkey,
            'npub': npub,
            'name': shortName,
            'picture': '',
          });
        }
      }
      result[key] = users;
      result[set.dTag] = users;

      if (!authors.containsKey(set.pubkey)) {
        final authorProfile = profilesMap[set.pubkey];
        String name = '';
        String picture = '';
        if (authorProfile != null) {
          name = authorProfile.name ?? authorProfile.displayName ?? '';
          picture = authorProfile.picture ?? '';
        }
        if (name.isEmpty) {
          final npub = _authService.hexToNpub(set.pubkey) ?? set.pubkey;
          name = npub.length > 12
              ? '${npub.substring(0, 8)}...${npub.substring(npub.length - 4)}'
              : npub;
        }
        authors[set.pubkey] = {'name': name, 'picture': picture};
      }
    }
    return (profiles: result, authors: authors);
  }

  void _syncInBackground(
      String currentUserHex, Emitter<FollowSetState> emit) {
    _syncService.syncFollowSets(currentUserHex).then((_) async {
      final service = FollowSetService.instance;

      final allPubkeys = <String>{};
      for (final set in service.allSets) {
        allPubkeys.addAll(set.pubkeys);
        allPubkeys.add(set.pubkey);
      }
      if (allPubkeys.isNotEmpty) {
        await _syncService.syncProfiles(allPubkeys.toList());
      }

      final resolved = await _resolveProfiles(service.allSets);
      if (state is FollowSetLoaded) {
        emit(FollowSetLoaded(
          followSets: service.followSets,
          followedUsersSets: service.followedUsersSets,
          resolvedProfiles: resolved.profiles,
          resolvedAuthors: resolved.authors,
        ));
      }
    });
  }

  Future<void> _onCreated(
    FollowSetCreated event,
    Emitter<FollowSetState> emit,
  ) async {
    final dTag = const Uuid().v4().replaceAll('-', '').substring(0, 8);

    try {
      await _syncService.publishFollowSet(
        dTag: dTag,
        title: event.title,
        description: event.description,
        image: '',
        pubkeys: event.pubkeys,
      );

      final service = FollowSetService.instance;
      final resolved = await _resolveProfiles(service.allSets);
      emit(FollowSetLoaded(
        followSets: service.followSets,
        followedUsersSets: service.followedUsersSets,
        resolvedProfiles: resolved.profiles,
        resolvedAuthors: resolved.authors,
      ));
    } catch (_) {}
  }

  Future<void> _onDeleted(
    FollowSetDeleted event,
    Emitter<FollowSetState> emit,
  ) async {
    final service = FollowSetService.instance;
    final set = service.getByDTag(event.dTag);

    if (set != null && set.id.isNotEmpty) {
      try {
        await rust_relay.deleteEvents(
          eventIds: [set.id],
          reason: 'User deleted list',
        );
      } catch (_) {}
    }

    service.removeSet(event.dTag);

    final resolved = await _resolveProfiles(service.allSets);
    emit(FollowSetLoaded(
      followSets: service.followSets,
      followedUsersSets: service.followedUsersSets,
      resolvedProfiles: resolved.profiles,
      resolvedAuthors: resolved.authors,
    ));
  }

  Future<void> _onUserAdded(
    FollowSetUserAdded event,
    Emitter<FollowSetState> emit,
  ) async {
    final service = FollowSetService.instance;
    service.addPubkeyToSet(event.dTag, event.pubkeyHex);

    final set = service.getByDTag(event.dTag);
    if (set == null) return;

    try {
      await _syncService.publishFollowSet(
        dTag: set.dTag,
        title: set.title,
        description: set.description,
        image: set.image,
        pubkeys: set.pubkeys,
      );
    } catch (_) {}

    final resolved = await _resolveProfiles(service.allSets);
    emit(FollowSetLoaded(
      followSets: service.followSets,
      followedUsersSets: service.followedUsersSets,
      resolvedProfiles: resolved.profiles,
      resolvedAuthors: resolved.authors,
    ));
  }

  Future<void> _onUserRemoved(
    FollowSetUserRemoved event,
    Emitter<FollowSetState> emit,
  ) async {
    final service = FollowSetService.instance;
    service.removePubkeyFromSet(event.dTag, event.pubkeyHex);

    final set = service.getByDTag(event.dTag);
    if (set == null) return;

    try {
      await _syncService.publishFollowSet(
        dTag: set.dTag,
        title: set.title,
        description: set.description,
        image: set.image,
        pubkeys: set.pubkeys,
      );
    } catch (_) {}

    final resolved = await _resolveProfiles(service.allSets);
    emit(FollowSetLoaded(
      followSets: service.followSets,
      followedUsersSets: service.followedUsersSets,
      resolvedProfiles: resolved.profiles,
      resolvedAuthors: resolved.authors,
    ));
  }

  Future<void> _onRefreshed(
    FollowSetRefreshed event,
    Emitter<FollowSetState> emit,
  ) async {
    await _onLoadRequested(const FollowSetLoadRequested(), emit);
  }
}
