import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import 'user_tile_event.dart';
import 'user_tile_state.dart';

class UserTileBloc extends Bloc<UserTileEvent, UserTileState> {
  final UserRepository _userRepository;
  final AuthRepository _authRepository;
  final String userNpub;

  StreamSubscription<List<Map<String, dynamic>>>? _followingSubscription;

  UserTileBloc({
    required UserRepository userRepository,
    required AuthRepository authRepository,
    required this.userNpub,
  })  : _userRepository = userRepository,
        _authRepository = authRepository,
        super(const UserTileInitial()) {
    on<UserTileInitialized>(_onUserTileInitialized);
    on<UserTileFollowToggled>(_onUserTileFollowToggled);
  }

  Future<void> _onUserTileInitialized(
    UserTileInitialized event,
    Emitter<UserTileState> emit,
  ) async {
    final currentUserNpubResult = await _authRepository.getCurrentUserNpub();
    if (currentUserNpubResult.isError || currentUserNpubResult.data == null) {
      return;
    }

    final followStatusResult = await _userRepository.isFollowing(event.userNpub);
    followStatusResult.fold(
      (isFollowing) {
        emit(UserTileLoaded(isFollowing: isFollowing));
      },
      (_) {
        emit(const UserTileLoaded());
      },
    );

    _followingSubscription?.cancel();
    _followingSubscription = _userRepository.followingListStream.listen(
      (followingList) {
        final targetUserHex = event.userNpub;
        final isFollowing = followingList.any((u) {
          final pubkeyHex = u['pubkeyHex'] as String? ?? '';
          final npub = u['npub'] as String? ?? '';
          return (pubkeyHex.isNotEmpty && pubkeyHex == targetUserHex) ||
              (npub.isNotEmpty && npub == targetUserHex);
        });

        final currentState = state;
        if (currentState is UserTileLoaded && currentState.isFollowing != isFollowing) {
          emit(currentState.copyWith(isFollowing: isFollowing, isLoading: false));
        }
      },
      onError: (_) {
        // Silently handle error - stream error is acceptable
      },
    );
  }

  Future<void> _onUserTileFollowToggled(
    UserTileFollowToggled event,
    Emitter<UserTileState> emit,
  ) async {
    final currentState = state;
    if (currentState is! UserTileLoaded || currentState.isLoading) return;

    final currentIsFollowing = currentState.isFollowing ?? false;

    emit(currentState.copyWith(isLoading: true));

    final currentUserNpubResult = await _authRepository.getCurrentUserNpub();
    if (currentUserNpubResult.isError || currentUserNpubResult.data == null) {
      emit(currentState.copyWith(isLoading: false));
      return;
    }

    if (currentIsFollowing) {
      final result = await _userRepository.unfollowUser(userNpub);
      result.fold(
        (_) {
          emit(currentState.copyWith(isFollowing: false, isLoading: false));
        },
        (_) {
          emit(currentState.copyWith(isFollowing: true, isLoading: false));
        },
      );
    } else {
      final result = await _userRepository.followUser(userNpub);
      result.fold(
        (_) {
          emit(currentState.copyWith(isFollowing: true, isLoading: false));
        },
        (_) {
          emit(currentState.copyWith(isFollowing: false, isLoading: false));
        },
      );
    }
  }

  @override
  Future<void> close() {
    _followingSubscription?.cancel();
    return super.close();
  }
}
