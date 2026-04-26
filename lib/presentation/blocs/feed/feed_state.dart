import '../../../core/bloc/base/base_state.dart';
import '../../../domain/entities/feed_note.dart';

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
  final List<FeedNote> feedNotes;
  final Map<String, Map<String, dynamic>> profiles;
  final String currentUserHex;
  final bool canLoadMore;
  final NoteViewMode viewMode;
  final FeedSortMode sortMode;
  final String? hashtag;
  final bool isLoadingMore;
  final bool isSyncing;
  final int pendingNotesCount;
  final String? activeListId;
  final String? activeListTitle;

  const FeedLoaded({
    required this.notes,
    this.feedNotes = const [],
    required this.profiles,
    required this.currentUserHex,
    this.canLoadMore = true,
    this.viewMode = NoteViewMode.list,
    this.sortMode = FeedSortMode.latest,
    this.hashtag,
    this.isLoadingMore = false,
    this.isSyncing = false,
    this.pendingNotesCount = 0,
    this.activeListId,
    this.activeListTitle,
  });

  @override
  List<Object?> get props => [
        notes,
        feedNotes,
        profiles,
        currentUserHex,
        canLoadMore,
        viewMode,
        sortMode,
        hashtag,
        isLoadingMore,
        isSyncing,
        pendingNotesCount,
        activeListId,
        activeListTitle,
      ];

  FeedLoaded copyWith({
    List<Map<String, dynamic>>? notes,
    List<FeedNote>? feedNotes,
    Map<String, Map<String, dynamic>>? profiles,
    String? currentUserHex,
    bool? canLoadMore,
    NoteViewMode? viewMode,
    FeedSortMode? sortMode,
    String? hashtag,
    bool? isLoadingMore,
    bool? isSyncing,
    int? pendingNotesCount,
    String? activeListId,
    String? activeListTitle,
    bool clearActiveList = false,
  }) {
    return FeedLoaded(
      notes: notes ?? this.notes,
      feedNotes: feedNotes ?? this.feedNotes,
      profiles: profiles ?? this.profiles,
      currentUserHex: currentUserHex ?? this.currentUserHex,
      canLoadMore: canLoadMore ?? this.canLoadMore,
      viewMode: viewMode ?? this.viewMode,
      sortMode: sortMode ?? this.sortMode,
      hashtag: hashtag ?? this.hashtag,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isSyncing: isSyncing ?? this.isSyncing,
      pendingNotesCount: pendingNotesCount ?? this.pendingNotesCount,
      activeListId:
          clearActiveList ? null : (activeListId ?? this.activeListId),
      activeListTitle:
          clearActiveList ? null : (activeListTitle ?? this.activeListTitle),
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
