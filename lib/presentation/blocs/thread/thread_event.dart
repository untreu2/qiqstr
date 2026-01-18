import '../../../core/bloc/base/base_event.dart';

abstract class ThreadEvent extends BaseEvent {
  const ThreadEvent();
}

class ThreadLoadRequested extends ThreadEvent {
  final String rootNoteId;
  final String? focusedNoteId;

  const ThreadLoadRequested({
    required this.rootNoteId,
    this.focusedNoteId,
  });

  @override
  List<Object?> get props => [rootNoteId, focusedNoteId];
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
