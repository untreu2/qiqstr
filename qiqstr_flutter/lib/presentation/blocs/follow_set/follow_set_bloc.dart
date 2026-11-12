import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/follow_set_service.dart';
import '../../../domain/entities/follow_set.dart';
import 'follow_set_event.dart';
import 'follow_set_state.dart';

class FollowSetBloc extends Bloc<FollowSetEvent, FollowSetState> {
  final ProfileRepository _profileRepository;
  final FollowingRepository _followingRepository;
  final SyncService _syncService;
  final AuthService _authService;

  FollowSetBloc({
    required this._profileRepository,
    required this._followingRepository,
    required this._syncService,
    required this._authService,
  }) : super(const FollowSetInitial()) {
    on<FollowSetEvent>(_onEvent, transformer: sequential());
  }

  bool _isCurrentSession(int generation, String? userHex) =>
      generation == FollowSetService.instance.sessionGeneration &&
      userHex == _authService.currentUserPubkeyHex;

  Future<void> _onEvent(
    FollowSetEvent event,
    Emitter<FollowSetState> emit,
  ) async {
    final sessionGeneration = FollowSetService.instance.sessionGeneration;
    final userHex = _authService.currentUserPubkeyHex;
    try {
      switch (event) {
        case FollowSetLoadRequested():
          await _onLoadRequested(event, emit);
        case FollowSetCreated():
          await _onCreated(event, emit);
        case FollowSetDeleted():
          await _onDeleted(event, emit);
        case FollowSetUserAdded():
          await _onUserAdded(event, emit);
        case FollowSetUserRemoved():
          await _onUserRemoved(event, emit);
        case FollowSetRefreshed():
          await _onRefreshed(event, emit);
        case FollowSetFavoriteToggled():
          await _onFavoriteToggled(event, emit);
      }
    } catch (error) {
      if (emit.isDone || !_isCurrentSession(sessionGeneration, userHex)) return;
      final currentState = state;
      emit(FollowSetError(error.toString()));
      if (currentState is FollowSetLoaded) {
        emit(currentState);
      }
    }
  }

  static const _favoritesKey = 'favorite_follow_set_ids';

  Future<List<String>> _loadFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_favoritesKey) ?? [];
  }

  Future<void> _saveFavoriteIds(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, ids);
  }

  Future<void> _onFavoriteToggled(
    FollowSetFavoriteToggled event,
    Emitter<FollowSetState> emit,
  ) async {
    if (state is! FollowSetLoaded) return;
    final current = state as FollowSetLoaded;
    final ids = List<String>.from(current.favoriteIds);
    if (ids.contains(event.listId)) {
      ids.remove(event.listId);
    } else {
      ids.add(event.listId);
    }
    await _saveFavoriteIds(ids);
    emit(current.copyWith(favoriteIds: ids));
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

      final follows = await _followingRepository.getFollowing(currentUserHex);
      if (follows != null && follows.isNotEmpty) {
        await service.loadFollowedUsersSets(followedPubkeys: follows);
      }
    }
    final favoriteIds = await _loadFavoriteIds();

    if (service.followSets.isNotEmpty || service.followedUsersSets.isNotEmpty) {
      final resolved = await _resolveProfiles(service.allSets);
      emit(
        FollowSetLoaded(
          followSets: service.followSets,
          followedUsersSets: service.followedUsersSets,
          resolvedProfiles: resolved.profiles,
          resolvedAuthors: resolved.authors,
          favoriteIds: favoriteIds,
        ),
      );
      await _sync(currentUserHex, emit);
    } else {
      emit(FollowSetLoaded(followSets: const [], favoriteIds: favoriteIds));
      await _sync(currentUserHex, emit);
    }
  }

  Future<
    ({
      Map<String, List<Map<String, dynamic>>> profiles,
      Map<String, Map<String, String>> authors,
    })
  >
  _resolveProfiles(List<FollowSet> sets) async {
    final allPubkeys = <String>{};
    for (final set in sets) {
      allPubkeys.addAll(set.pubkeys);
      allPubkeys.add(set.pubkey);
    }
    if (allPubkeys.isEmpty) {
      return (
        profiles: <String, List<Map<String, dynamic>>>{},
        authors: <String, Map<String, String>>{},
      );
    }

    final profilesMap = await _profileRepository.getProfiles(
      allPubkeys.toList(),
    );

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

  Future<void> _sync(
    String currentUserHex,
    Emitter<FollowSetState> emit,
  ) async {
    await _syncService.syncFollowSets(currentUserHex);
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
    if (!emit.isDone && state is FollowSetLoaded) {
      final current = state as FollowSetLoaded;
      emit(
        FollowSetLoaded(
          followSets: service.followSets,
          followedUsersSets: service.followedUsersSets,
          resolvedProfiles: resolved.profiles,
          resolvedAuthors: resolved.authors,
          favoriteIds: current.favoriteIds,
        ),
      );
    }
  }

  Future<void> _onCreated(
    FollowSetCreated event,
    Emitter<FollowSetState> emit,
  ) async {
    final sessionGeneration = FollowSetService.instance.sessionGeneration;
    final userHex = _authService.currentUserPubkeyHex;
    final dTag = const Uuid().v4().replaceAll('-', '').substring(0, 8);

    try {
      await _syncService.publishFollowSet(
        dTag: dTag,
        title: event.title,
        description: event.description,
        image: '',
        pubkeys: event.pubkeys,
      );

      if (emit.isDone || !_isCurrentSession(sessionGeneration, userHex)) return;
      final service = FollowSetService.instance;
      final resolved = await _resolveProfiles(service.allSets);
      final favoriteIds = state is FollowSetLoaded
          ? (state as FollowSetLoaded).favoriteIds
          : await _loadFavoriteIds();
      if (emit.isDone || !_isCurrentSession(sessionGeneration, userHex)) return;
      emit(
        FollowSetLoaded(
          followSets: service.followSets,
          followedUsersSets: service.followedUsersSets,
          resolvedProfiles: resolved.profiles,
          resolvedAuthors: resolved.authors,
          favoriteIds: favoriteIds,
        ),
      );
    } catch (_) {
      if (!_isCurrentSession(sessionGeneration, userHex)) return;
      FollowSetService.instance.removeSet(dTag);
      rethrow;
    }
  }

  Future<void> _onDeleted(
    FollowSetDeleted event,
    Emitter<FollowSetState> emit,
  ) async {
    final sessionGeneration = FollowSetService.instance.sessionGeneration;
    final userHex = _authService.currentUserPubkeyHex;
    final service = FollowSetService.instance;
    final set = service.getByDTag(event.dTag);

    if (set != null && set.id.isNotEmpty) {
      await _syncService.publishDeletion(
        eventIds: [set.id],
        reason: 'User deleted list',
      );
    }

    if (!_isCurrentSession(sessionGeneration, userHex)) return;
    service.removeSet(event.dTag);

    if (emit.isDone || !_isCurrentSession(sessionGeneration, userHex)) return;
    final resolved = await _resolveProfiles(service.allSets);
    final favoriteIds = state is FollowSetLoaded
        ? (state as FollowSetLoaded).favoriteIds
        : await _loadFavoriteIds();
    if (emit.isDone || !_isCurrentSession(sessionGeneration, userHex)) return;
    emit(
      FollowSetLoaded(
        followSets: service.followSets,
        followedUsersSets: service.followedUsersSets,
        resolvedProfiles: resolved.profiles,
        resolvedAuthors: resolved.authors,
        favoriteIds: favoriteIds,
      ),
    );
  }

  Future<void> _onUserAdded(
    FollowSetUserAdded event,
    Emitter<FollowSetState> emit,
  ) async {
    final sessionGeneration = FollowSetService.instance.sessionGeneration;
    final userHex = _authService.currentUserPubkeyHex;
    final service = FollowSetService.instance;
    final previousSet = service.getByDTag(event.dTag);
    if (previousSet == null || previousSet.pubkeys.contains(event.pubkeyHex)) {
      return;
    }
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
    } catch (_) {
      if (!_isCurrentSession(sessionGeneration, userHex)) return;
      service.addSet(previousSet);
      rethrow;
    }

    if (emit.isDone || !_isCurrentSession(sessionGeneration, userHex)) return;
    final resolved = await _resolveProfiles(service.allSets);
    final favoriteIds = state is FollowSetLoaded
        ? (state as FollowSetLoaded).favoriteIds
        : await _loadFavoriteIds();
    if (emit.isDone || !_isCurrentSession(sessionGeneration, userHex)) return;
    emit(
      FollowSetLoaded(
        followSets: service.followSets,
        followedUsersSets: service.followedUsersSets,
        resolvedProfiles: resolved.profiles,
        resolvedAuthors: resolved.authors,
        favoriteIds: favoriteIds,
      ),
    );
  }

  Future<void> _onUserRemoved(
    FollowSetUserRemoved event,
    Emitter<FollowSetState> emit,
  ) async {
    final sessionGeneration = FollowSetService.instance.sessionGeneration;
    final userHex = _authService.currentUserPubkeyHex;
    final service = FollowSetService.instance;
    final previousSet = service.getByDTag(event.dTag);
    if (previousSet == null || !previousSet.pubkeys.contains(event.pubkeyHex)) {
      return;
    }
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
    } catch (_) {
      if (!_isCurrentSession(sessionGeneration, userHex)) return;
      service.addSet(previousSet);
      rethrow;
    }

    if (emit.isDone || !_isCurrentSession(sessionGeneration, userHex)) return;
    final resolved = await _resolveProfiles(service.allSets);
    final favoriteIds = state is FollowSetLoaded
        ? (state as FollowSetLoaded).favoriteIds
        : await _loadFavoriteIds();
    if (emit.isDone || !_isCurrentSession(sessionGeneration, userHex)) return;
    emit(
      FollowSetLoaded(
        followSets: service.followSets,
        followedUsersSets: service.followedUsersSets,
        resolvedProfiles: resolved.profiles,
        resolvedAuthors: resolved.authors,
        favoriteIds: favoriteIds,
      ),
    );
  }

  Future<void> _onRefreshed(
    FollowSetRefreshed event,
    Emitter<FollowSetState> emit,
  ) async {
    await _onLoadRequested(const FollowSetLoadRequested(), emit);
  }
}
