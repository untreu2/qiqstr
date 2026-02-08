import '../../../core/bloc/base/base_event.dart';

abstract class ThreadEvent extends BaseEvent {
  const ThreadEvent();
}

class ThreadLoadRequested extends ThreadEvent {
  final String rootNoteId;
  final String? focusedNoteId;
  final Map<String, dynamic>? initialNoteData;

  const ThreadLoadRequested({
    required this.rootNoteId,
    this.focusedNoteId,
    this.initialNoteData,
  });

  @override
  List<Object?> get props => [rootNoteId, focusedNoteId, initialNoteData];
}

class ThreadRefreshed extends ThreadEvent {
  const ThreadRefreshed();
}

class ThreadFocusedNoteChanged extends ThreadEvent {
  final String? noteId;

  const ThreadFocusedNoteChanged(this.noteId);

  @override
  List<Object?> get props => [noteId];
}

class ThreadReplyPublished extends ThreadEvent {
  final Map<String, dynamic> note;

  const ThreadReplyPublished(this.note);

  @override
  List<Object?> get props => [note];
}

class ThreadProfilesUpdated extends ThreadEvent {
  final Map<String, Map<String, dynamic>> profiles;

  const ThreadProfilesUpdated(this.profiles);

  @override
  List<Object?> get props => [profiles];
}
