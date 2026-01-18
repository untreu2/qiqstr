import '../../../core/bloc/base/base_event.dart';

abstract class NoteStatisticsEvent extends BaseEvent {
  const NoteStatisticsEvent();
}

class NoteStatisticsInitialized extends NoteStatisticsEvent {
  final String noteId;

  const NoteStatisticsInitialized({required this.noteId});

  @override
  List<Object?> get props => [noteId];
}

class NoteStatisticsRefreshed extends NoteStatisticsEvent {
  const NoteStatisticsRefreshed();
}
