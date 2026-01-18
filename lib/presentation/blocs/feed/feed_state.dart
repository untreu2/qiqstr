import '../../../core/bloc/base/base_state.dart';
import '../../../data/services/feed_loader_service.dart';

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
  final String currentUserNpub;
  final bool canLoadMore;
  final NoteViewMode viewMode;
  final FeedSortMode sortMode;
  final String? hashtag;
  final bool isLoadingMore;

  const FeedLoaded({
    required this.notes,
    required this.profiles,
    required this.currentUserNpub,
    this.canLoadMore = true,
    this.viewMode = NoteViewMode.list,
    this.sortMode = FeedSortMode.latest,
    this.hashtag,
    this.isLoadingMore = false,
  });

  @override
  List<Object?> get props => [
        notes,
        profiles,
        currentUserNpub,
        canLoadMore,
        viewMode,
        sortMode,
        hashtag,
        isLoadingMore,
      ];

  FeedLoaded copyWith({
    List<Map<String, dynamic>>? notes,
    Map<String, Map<String, dynamic>>? profiles,
    String? currentUserNpub,
    bool? canLoadMore,
    NoteViewMode? viewMode,
    FeedSortMode? sortMode,
    String? hashtag,
    bool? isLoadingMore,
  }) {
    return FeedLoaded(
      notes: notes ?? this.notes,
      profiles: profiles ?? this.profiles,
      currentUserNpub: currentUserNpub ?? this.currentUserNpub,
      canLoadMore: canLoadMore ?? this.canLoadMore,
      viewMode: viewMode ?? this.viewMode,
      sortMode: sortMode ?? this.sortMode,
      hashtag: hashtag ?? this.hashtag,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
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
