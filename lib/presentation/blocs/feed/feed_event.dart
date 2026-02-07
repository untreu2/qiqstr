import '../../../core/bloc/base/base_event.dart';
import '../../../domain/entities/feed_note.dart';
import 'feed_state.dart';

abstract class FeedEvent extends BaseEvent {
  const FeedEvent();
}

class FeedInitialized extends FeedEvent {
  final String userHex;
  final String? hashtag;

  const FeedInitialized({required this.userHex, this.hashtag});

  @override
  List<Object?> get props => [userHex, hashtag];
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

class FeedUserNotePublished extends FeedEvent {
  final Map<String, dynamic> note;

  const FeedUserNotePublished(this.note);

  @override
  List<Object?> get props => [note];
}

class FeedProfilesLoaded extends FeedEvent {
  final Map<String, Map<String, dynamic>> profiles;

  const FeedProfilesLoaded(this.profiles);

  @override
  List<Object?> get props => [profiles];
}

class FeedNotesUpdated extends FeedEvent {
  final List<FeedNote> notes;

  const FeedNotesUpdated(this.notes);

  @override
  List<Object?> get props => [notes];
}

class FeedSyncCompleted extends FeedEvent {
  const FeedSyncCompleted();
}
