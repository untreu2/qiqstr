import '../../../core/bloc/base/base_state.dart';

abstract class ProfileInfoState extends BaseState {
  const ProfileInfoState();
}

class ProfileInfoInitial extends ProfileInfoState {
  const ProfileInfoInitial();
}

class ProfileInfoLoading extends ProfileInfoState {
  const ProfileInfoLoading();
}

class ProfileInfoLoaded extends ProfileInfoState {
  final Map<String, dynamic> user;
  final bool? isFollowing;
  final bool? isMuted;
  final bool? doesUserFollowMe;
  final int followingCount;
  final int followerCount;
  final bool isLoadingCounts;
  final bool isLoadingProfile;
  final String? currentUserHex;
  final int? followScoreCount;
  final List<String> followScoreAvatars;

  const ProfileInfoLoaded({
    required this.user,
    this.isFollowing,
    this.isMuted,
    this.doesUserFollowMe,
    this.followingCount = 0,
    this.followerCount = 0,
    this.isLoadingCounts = true,
    this.isLoadingProfile = false,
    this.currentUserHex,
    this.followScoreCount,
    this.followScoreAvatars = const [],
  });

  ProfileInfoLoaded copyWith({
    Map<String, dynamic>? user,
    bool? isFollowing,
    bool? isMuted,
    bool? doesUserFollowMe,
    int? followingCount,
    int? followerCount,
    bool? isLoadingCounts,
    bool? isLoadingProfile,
    String? currentUserHex,
    int? followScoreCount,
    List<String>? followScoreAvatars,
  }) {
    return ProfileInfoLoaded(
      user: user ?? this.user,
      isFollowing: isFollowing ?? this.isFollowing,
      isMuted: isMuted ?? this.isMuted,
      doesUserFollowMe: doesUserFollowMe ?? this.doesUserFollowMe,
      followingCount: followingCount ?? this.followingCount,
      followerCount: followerCount ?? this.followerCount,
      isLoadingCounts: isLoadingCounts ?? this.isLoadingCounts,
      isLoadingProfile: isLoadingProfile ?? this.isLoadingProfile,
      currentUserHex: currentUserHex ?? this.currentUserHex,
      followScoreCount: followScoreCount ?? this.followScoreCount,
      followScoreAvatars: followScoreAvatars ?? this.followScoreAvatars,
    );
  }

  @override
  List<Object?> get props => [
        user,
        isFollowing,
        isMuted,
        doesUserFollowMe,
        followingCount,
        followerCount,
        isLoadingCounts,
        isLoadingProfile,
        currentUserHex,
        followScoreCount,
        followScoreAvatars,
      ];
}

class ProfileInfoError extends ProfileInfoState {
  final String message;

  const ProfileInfoError(this.message);

  @override
  List<Object?> get props => [message];
}
