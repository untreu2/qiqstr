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

  const BookmarkLoaded({
    required this.bookmarkedNotes,
    required this.removingStates,
  });

  BookmarkLoaded copyWith({
    List<Map<String, dynamic>>? bookmarkedNotes,
    Map<String, bool>? removingStates,
  }) {
    return BookmarkLoaded(
      bookmarkedNotes: bookmarkedNotes ?? this.bookmarkedNotes,
      removingStates: removingStates ?? this.removingStates,
    );
  }

  @override
  List<Object?> get props => [bookmarkedNotes, removingStates];
}

class BookmarkError extends BookmarkState {
  final String message;

  const BookmarkError(this.message);

  @override
  List<Object?> get props => [message];
}
