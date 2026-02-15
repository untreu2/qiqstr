import '../../../core/bloc/base/base_state.dart';

abstract class BookmarkState extends BaseState {
  const BookmarkState();
}

class BookmarkInitial extends BookmarkState {
  const BookmarkInitial();
}

class BookmarkLoading extends BookmarkState {
  const BookmarkLoading();
}

class BookmarkLoaded extends BookmarkState {
  final List<Map<String, dynamic>> bookmarkedNotes;
  final Map<String, bool> removingStates;
  final bool isSyncing;

  const BookmarkLoaded({
    required this.bookmarkedNotes,
    required this.removingStates,
    this.isSyncing = false,
  });

  BookmarkLoaded copyWith({
    List<Map<String, dynamic>>? bookmarkedNotes,
    Map<String, bool>? removingStates,
    bool? isSyncing,
  }) {
    return BookmarkLoaded(
      bookmarkedNotes: bookmarkedNotes ?? this.bookmarkedNotes,
      removingStates: removingStates ?? this.removingStates,
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }

  @override
  List<Object?> get props => [bookmarkedNotes, removingStates, isSyncing];
}

class BookmarkError extends BookmarkState {
  final String message;

  const BookmarkError(this.message);

  @override
  List<Object?> get props => [message];
}
