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
  final List<Map<String, dynamic>> replies;
  final List<Map<String, dynamic>> articles;
  final List<Map<String, dynamic>> likedNotes;
  final bool canLoadMore;
  final bool isLoadingMore;
  final bool canLoadMoreReplies;
  final bool isLoadingMoreReplies;
  final bool canLoadMoreArticles;
  final bool isLoadingMoreArticles;
  final bool canLoadMoreLikes;
  final bool isLoadingMoreLikes;
  final bool isSyncing;
  final String currentProfileHex;
  final String currentUserHex;

  const ProfileLoaded({
    required this.user,
    required this.isFollowing,
    required this.isCurrentUser,
    required this.profiles,
    required this.notes,
    this.replies = const [],
    this.articles = const [],
    this.likedNotes = const [],
    required this.currentProfileHex,
    required this.currentUserHex,
    this.canLoadMore = true,
    this.isLoadingMore = false,
    this.canLoadMoreReplies = true,
    this.isLoadingMoreReplies = false,
    this.canLoadMoreArticles = true,
    this.isLoadingMoreArticles = false,
    this.canLoadMoreLikes = true,
    this.isLoadingMoreLikes = false,
    this.isSyncing = false,
  });

  @override
  List<Object?> get props => [
        user,
        isFollowing,
        isCurrentUser,
        profiles,
        notes,
        replies,
        articles,
        likedNotes,
        canLoadMore,
        isLoadingMore,
        canLoadMoreReplies,
        isLoadingMoreReplies,
        canLoadMoreArticles,
        isLoadingMoreArticles,
        canLoadMoreLikes,
        isLoadingMoreLikes,
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
    List<Map<String, dynamic>>? replies,
    List<Map<String, dynamic>>? articles,
    List<Map<String, dynamic>>? likedNotes,
    bool? canLoadMore,
    bool? isLoadingMore,
    bool? canLoadMoreReplies,
    bool? isLoadingMoreReplies,
    bool? canLoadMoreArticles,
    bool? isLoadingMoreArticles,
    bool? canLoadMoreLikes,
    bool? isLoadingMoreLikes,
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
      replies: replies ?? this.replies,
      articles: articles ?? this.articles,
      likedNotes: likedNotes ?? this.likedNotes,
      canLoadMore: canLoadMore ?? this.canLoadMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      canLoadMoreReplies: canLoadMoreReplies ?? this.canLoadMoreReplies,
      isLoadingMoreReplies: isLoadingMoreReplies ?? this.isLoadingMoreReplies,
      canLoadMoreArticles: canLoadMoreArticles ?? this.canLoadMoreArticles,
      isLoadingMoreArticles:
          isLoadingMoreArticles ?? this.isLoadingMoreArticles,
      canLoadMoreLikes: canLoadMoreLikes ?? this.canLoadMoreLikes,
      isLoadingMoreLikes: isLoadingMoreLikes ?? this.isLoadingMoreLikes,
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
