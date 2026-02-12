import '../../../core/bloc/base/base_state.dart';
import '../../../data/services/auth_service.dart';

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
  final List<StoredAccount> storedAccounts;
  final Map<String, String> accountProfileImages;

  const SidebarLoaded({
    required this.currentUser,
    this.followerCount = 0,
    this.followingCount = 0,
    this.isLoadingCounts = true,
    this.connectedRelayCount = 0,
    this.storedAccounts = const [],
    this.accountProfileImages = const {},
  });

  SidebarLoaded copyWith({
    Map<String, dynamic>? currentUser,
    int? followerCount,
    int? followingCount,
    bool? isLoadingCounts,
    int? connectedRelayCount,
    List<StoredAccount>? storedAccounts,
    Map<String, String>? accountProfileImages,
  }) {
    return SidebarLoaded(
      currentUser: currentUser ?? this.currentUser,
      followerCount: followerCount ?? this.followerCount,
      followingCount: followingCount ?? this.followingCount,
      isLoadingCounts: isLoadingCounts ?? this.isLoadingCounts,
      connectedRelayCount: connectedRelayCount ?? this.connectedRelayCount,
      storedAccounts: storedAccounts ?? this.storedAccounts,
      accountProfileImages: accountProfileImages ?? this.accountProfileImages,
    );
  }

  @override
  List<Object?> get props =>
      [currentUser, followerCount, followingCount, isLoadingCounts, connectedRelayCount, storedAccounts, accountProfileImages];
}
