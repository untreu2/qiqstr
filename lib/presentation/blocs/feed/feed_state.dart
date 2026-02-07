import '../../../core/bloc/base/base_state.dart';

enum FeedSortMode {
  latest,
  mostInteracted,
}

abstract class FeedState extends BaseState {
  const FeedState();
}

class FeedInitial extends FeedState {
  const FeedInitial();
}

class FeedLoading extends FeedState {
  const FeedLoading();
}

class FeedLoaded extends FeedState {
  final List<Map<String, dynamic>> notes;
  final Map<String, Map<String, dynamic>> profiles;
  final String currentUserHex;
  final bool canLoadMore;
  final NoteViewMode viewMode;
  final FeedSortMode sortMode;
  final String? hashtag;
  final bool isLoadingMore;
  final bool isSyncing;

  const FeedLoaded({
    required this.notes,
    required this.profiles,
    required this.currentUserHex,
    this.canLoadMore = true,
    this.viewMode = NoteViewMode.list,
    this.sortMode = FeedSortMode.latest,
    this.hashtag,
    this.isLoadingMore = false,
    this.isSyncing = false,
  });

  @override
  List<Object?> get props => [
        notes,
        profiles,
        currentUserHex,
        canLoadMore,
        viewMode,
        sortMode,
        hashtag,
        isLoadingMore,
        isSyncing,
      ];

  FeedLoaded copyWith({
    List<Map<String, dynamic>>? notes,
    Map<String, Map<String, dynamic>>? profiles,
    String? currentUserHex,
    bool? canLoadMore,
    NoteViewMode? viewMode,
    FeedSortMode? sortMode,
    String? hashtag,
    bool? isLoadingMore,
    bool? isSyncing,
  }) {
    return FeedLoaded(
      notes: notes ?? this.notes,
      profiles: profiles ?? this.profiles,
      currentUserHex: currentUserHex ?? this.currentUserHex,
      canLoadMore: canLoadMore ?? this.canLoadMore,
      viewMode: viewMode ?? this.viewMode,
      sortMode: sortMode ?? this.sortMode,
      hashtag: hashtag ?? this.hashtag,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }
}

class FeedError extends FeedState {
  final String message;

  const FeedError(this.message);

  @override
  List<Object?> get props => [message];
}

class FeedEmpty extends FeedState {
  const FeedEmpty();
}

enum NoteViewMode {
  list,
  grid,
}
