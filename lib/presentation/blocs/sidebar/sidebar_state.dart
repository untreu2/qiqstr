import '../../../core/bloc/base/base_state.dart';

abstract class SidebarState extends BaseState {
  const SidebarState();
}

class SidebarInitial extends SidebarState {
  const SidebarInitial();
}

class SidebarLoading extends SidebarState {
  const SidebarLoading();
}

class SidebarLoaded extends SidebarState {
  final Map<String, dynamic> currentUser;
  final int followerCount;
  final int followingCount;
  final bool isLoadingCounts;
  final int connectedRelayCount;

  const SidebarLoaded({
    required this.currentUser,
    this.followerCount = 0,
    this.followingCount = 0,
    this.isLoadingCounts = true,
    this.connectedRelayCount = 0,
  });

  SidebarLoaded copyWith({
    Map<String, dynamic>? currentUser,
    int? followerCount,
    int? followingCount,
    bool? isLoadingCounts,
    int? connectedRelayCount,
  }) {
    return SidebarLoaded(
      currentUser: currentUser ?? this.currentUser,
      followerCount: followerCount ?? this.followerCount,
      followingCount: followingCount ?? this.followingCount,
      isLoadingCounts: isLoadingCounts ?? this.isLoadingCounts,
      connectedRelayCount: connectedRelayCount ?? this.connectedRelayCount,
    );
  }

  @override
  List<Object?> get props =>
      [currentUser, followerCount, followingCount, isLoadingCounts, connectedRelayCount];
}
