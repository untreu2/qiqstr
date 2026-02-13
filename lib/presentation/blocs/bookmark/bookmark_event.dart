import '../../../core/bloc/base/base_event.dart';

abstract class BookmarkEvent extends BaseEvent {
  const BookmarkEvent();
}

class BookmarkLoadRequested extends BookmarkEvent {
  const BookmarkLoadRequested();
}

class BookmarkAdded extends BookmarkEvent {
  final String eventId;

  const BookmarkAdded(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

class BookmarkRemoved extends BookmarkEvent {
  final String eventId;

  const BookmarkRemoved(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

class BookmarkRefreshed extends BookmarkEvent {
  const BookmarkRefreshed();
}
