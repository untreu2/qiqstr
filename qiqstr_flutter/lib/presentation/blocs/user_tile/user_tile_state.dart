import '../../../core/bloc/base/base_state.dart';

abstract class UserTileState extends BaseState {
  const UserTileState();
}

class UserTileInitial extends UserTileState {
  const UserTileInitial();
}

class UserTileLoaded extends UserTileState {
  final bool? isFollowing;
  final bool isLoading;

  const UserTileLoaded({
    this.isFollowing,
    this.isLoading = false,
  });

  UserTileLoaded copyWith({
    bool? isFollowing,
    bool? isLoading,
  }) {
    return UserTileLoaded(
      isFollowing: isFollowing ?? this.isFollowing,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [isFollowing, isLoading];
}
