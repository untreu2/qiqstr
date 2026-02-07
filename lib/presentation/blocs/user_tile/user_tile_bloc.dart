import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import 'user_tile_event.dart';
import 'user_tile_state.dart';

class UserTileBloc extends Bloc<UserTileEvent, UserTileState> {
  final FollowingRepository _followingRepository;
  final SyncService _syncService;
  final AuthService _authService;
  final String userNpub;

  UserTileBloc({
    required FollowingRepository followingRepository,
    required SyncService syncService,
    required AuthService authService,
    required this.userNpub,
  })  : _followingRepository = followingRepository,
        _syncService = syncService,
        _authService = authService,
        super(const UserTileInitial()) {
    on<UserTileInitialized>(_onUserTileInitialized);
    on<UserTileFollowToggled>(_onUserTileFollowToggled);
  }

  Future<void> _onUserTileInitialized(
    UserTileInitialized event,
    Emitter<UserTileState> emit,
  ) async {
    final pubkeyResult = await _authService.getCurrentUserPublicKeyHex();
    if (pubkeyResult.isError || pubkeyResult.data == null) {
      return;
    }
    final currentUserHex = pubkeyResult.data!;

    try {
      final targetHex =
          _authService.npubToHex(event.userNpub) ?? event.userNpub;
      final isFollowing =
          await _followingRepository.isFollowing(currentUserHex, targetHex);
      emit(UserTileLoaded(isFollowing: isFollowing));
    } catch (e) {
      emit(const UserTileLoaded());
    }
  }

  Future<void> _onUserTileFollowToggled(
    UserTileFollowToggled event,
    Emitter<UserTileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! UserTileLoaded || currentState.isLoading) return;

    final currentIsFollowing = currentState.isFollowing ?? false;

    emit(currentState.copyWith(isLoading: true));

    try {
      final pubkeyResult = await _authService.getCurrentUserPublicKeyHex();
      if (pubkeyResult.isError || pubkeyResult.data == null) {
        emit(currentState.copyWith(isLoading: false));
        return;
      }
      final currentUserHex = pubkeyResult.data!;

      final targetHex = _authService.npubToHex(userNpub) ?? userNpub;

      final currentFollows =
          await _followingRepository.getFollowingList(currentUserHex) ?? [];

      List<String> updatedFollows;
      if (currentIsFollowing) {
        updatedFollows = currentFollows.where((p) => p != targetHex).toList();
        emit(currentState.copyWith(isFollowing: false, isLoading: false));
      } else {
        updatedFollows = [...currentFollows, targetHex];
        emit(currentState.copyWith(isFollowing: true, isLoading: false));
      }

      await _syncService.publishFollow(followingPubkeys: updatedFollows);
    } catch (e) {
      emit(currentState.copyWith(
          isFollowing: currentIsFollowing, isLoading: false));
    }
  }
}
