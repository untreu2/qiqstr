import '../../../core/bloc/base/base_event.dart';
import '../../../data/services/feed_loader_service.dart';

abstract class FeedEvent extends BaseEvent {
  const FeedEvent();
}

class FeedInitialized extends FeedEvent {
  final String npub;
  final String? hashtag;

  const FeedInitialized({required this.npub, this.hashtag});

  @override
  List<Object?> get props => [npub, hashtag];
}

class FeedRefreshed extends FeedEvent {
  const FeedRefreshed();
}

class FeedLoadMoreRequested extends FeedEvent {
  const FeedLoadMoreRequested();
}

class FeedViewModeChanged extends FeedEvent {
  final NoteViewMode mode;

  const FeedViewModeChanged(this.mode);

  @override
  List<Object?> get props => [mode];
}

class FeedSortModeChanged extends FeedEvent {
  final FeedSortMode mode;

  const FeedSortModeChanged(this.mode);

  @override
  List<Object?> get props => [mode];
}

class FeedHashtagChanged extends FeedEvent {
  final String? hashtag;

  const FeedHashtagChanged(this.hashtag);

  @override
  List<Object?> get props => [hashtag];
}

class FeedUserProfileUpdated extends FeedEvent {
  final String userId;
  final Map<String, dynamic> user;

  const FeedUserProfileUpdated(this.userId, this.user);

  @override
  List<Object?> get props => [userId, user];
}

class FeedNoteDeleted extends FeedEvent {
  final String noteId;

  const FeedNoteDeleted(this.noteId);

  @override
  List<Object?> get props => [noteId];
}

enum NoteViewMode {
  list,
  grid,
}
