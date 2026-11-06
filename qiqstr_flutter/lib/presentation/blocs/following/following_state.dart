import '../../../core/bloc/base/base_state.dart';

abstract class FollowingState extends BaseState {
  const FollowingState();
}

class FollowingInitial extends FollowingState {
  const FollowingInitial();
}

class FollowingLoading extends FollowingState {
  const FollowingLoading();
}

class FollowingLoaded extends FollowingState {
  final List<Map<String, dynamic>> followingUsers;
  final Map<String, Map<String, dynamic>> loadedUsers;

  const FollowingLoaded({
    required this.followingUsers,
    required this.loadedUsers,
  });

  FollowingLoaded copyWith({
    List<Map<String, dynamic>>? followingUsers,
    Map<String, Map<String, dynamic>>? loadedUsers,
  }) {
    return FollowingLoaded(
      followingUsers: followingUsers ?? this.followingUsers,
      loadedUsers: loadedUsers ?? this.loadedUsers,
    );
  }

  @override
  List<Object?> get props => [followingUsers, loadedUsers];
}

class FollowingError extends FollowingState {
  final String message;

  const FollowingError(this.message);

  @override
  List<Object?> get props => [message];
}
