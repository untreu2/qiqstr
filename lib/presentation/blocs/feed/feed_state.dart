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
  final List<FeedNote> notes;
  final List<Map<String, dynamic>> notesMaps;
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
  final int version;

  const FeedLoaded._({
    required this.notes,
    required this.notesMaps,
    required this.profiles,
    required this.currentUserHex,
    required this.canLoadMore,
    required this.viewMode,
    required this.sortMode,
    required this.hashtag,
    required this.isLoadingMore,
    required this.isSyncing,
    required this.pendingNotesCount,
    required this.activeListId,
    required this.activeListTitle,
    required this.version,
  });

  factory FeedLoaded({
    required List<FeedNote> notes,
    required Map<String, Map<String, dynamic>> profiles,
    required String currentUserHex,
    bool canLoadMore = true,
    NoteViewMode viewMode = NoteViewMode.list,
    FeedSortMode sortMode = FeedSortMode.latest,
    String? hashtag,
    bool isLoadingMore = false,
    bool isSyncing = false,
    int pendingNotesCount = 0,
    String? activeListId,
    String? activeListTitle,
    int version = 0,
    List<Map<String, dynamic>>? notesMaps,
  }) {
    return FeedLoaded._(
      notes: notes,
      notesMaps: notesMaps ?? _buildMaps(notes),
      profiles: profiles,
      currentUserHex: currentUserHex,
      canLoadMore: canLoadMore,
      viewMode: viewMode,
      sortMode: sortMode,
      hashtag: hashtag,
      isLoadingMore: isLoadingMore,
      isSyncing: isSyncing,
      pendingNotesCount: pendingNotesCount,
      activeListId: activeListId,
      activeListTitle: activeListTitle,
      version: version,
    );
  }

  static List<Map<String, dynamic>> _buildMaps(List<FeedNote> notes) {
    if (notes.isEmpty) return const [];
    return List<Map<String, dynamic>>.unmodifiable(
      notes.map((n) => n.toMap()),
    );
  }

  @override
  List<Object?> get props => [
        version,
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
    List<FeedNote>? notes,
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
    final notesChanged = notes != null && !identical(notes, this.notes);
    final profilesChanged =
        profiles != null && !identical(profiles, this.profiles);
    return FeedLoaded._(
      notes: notes ?? this.notes,
      notesMaps: notesChanged ? _buildMaps(notes) : notesMaps,
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
      version: (notesChanged || profilesChanged) ? version + 1 : version,
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
