import '../../../core/bloc/base/base_state.dart';

abstract class ProfileState extends BaseState {
  const ProfileState();
}

class ProfileInitial extends ProfileState {
  const ProfileInitial();
}

class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

class ProfileLoaded extends ProfileState {
  final Map<String, dynamic> user;
  final bool isFollowing;
  final bool isCurrentUser;
  final Map<String, Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> notes;
  final bool canLoadMore;
  final bool isLoadingMore;
  final bool isSyncing;
  final String currentProfileHex;
  final String currentUserHex;

  const ProfileLoaded({
    required this.user,
    required this.isFollowing,
    required this.isCurrentUser,
    required this.profiles,
    required this.notes,
    required this.currentProfileHex,
    required this.currentUserHex,
    this.canLoadMore = true,
    this.isLoadingMore = false,
    this.isSyncing = false,
  });

  @override
  List<Object?> get props => [
        user,
        isFollowing,
        isCurrentUser,
        profiles,
        notes,
        canLoadMore,
        isLoadingMore,
        isSyncing,
        currentProfileHex,
        currentUserHex,
      ];

  ProfileLoaded copyWith({
    Map<String, dynamic>? user,
    bool? isFollowing,
    bool? isCurrentUser,
    Map<String, Map<String, dynamic>>? profiles,
    List<Map<String, dynamic>>? notes,
    bool? canLoadMore,
    bool? isLoadingMore,
    bool? isSyncing,
    String? currentProfileHex,
    String? currentUserHex,
  }) {
    return ProfileLoaded(
      user: user ?? this.user,
      isFollowing: isFollowing ?? this.isFollowing,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
      profiles: profiles ?? this.profiles,
      notes: notes ?? this.notes,
      canLoadMore: canLoadMore ?? this.canLoadMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isSyncing: isSyncing ?? this.isSyncing,
      currentProfileHex: currentProfileHex ?? this.currentProfileHex,
      currentUserHex: currentUserHex ?? this.currentUserHex,
    );
  }
}

class ProfileError extends ProfileState {
  final String message;

  const ProfileError(this.message);

  @override
  List<Object?> get props => [message];
}

class ProfileFollowingListLoaded extends ProfileState {
  final List<Map<String, dynamic>> following;

  const ProfileFollowingListLoaded(this.following);

  @override
  List<Object?> get props => [following];
}

class ProfileFollowersListLoaded extends ProfileState {
  final List<Map<String, dynamic>> followers;

  const ProfileFollowersListLoaded(this.followers);

  @override
  List<Object?> get props => [followers];
}
