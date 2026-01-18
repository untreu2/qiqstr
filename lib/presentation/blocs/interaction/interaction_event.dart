import '../../../core/bloc/base/base_event.dart';

abstract class InteractionEvent extends BaseEvent {
  const InteractionEvent();
}

class InteractionInitialized extends InteractionEvent {
  final String noteId;
  final String currentUserNpub;
  final Map<String, dynamic>? note;

  const InteractionInitialized({
    required this.noteId,
    required this.currentUserNpub,
    this.note,
  });

  @override
  List<Object?> get props => [noteId, currentUserNpub, note];
}

class InteractionNoteUpdated extends InteractionEvent {
  final Map<String, dynamic>? note;

  const InteractionNoteUpdated(this.note);

  @override
  List<Object?> get props => [note];
}

class InteractionStateRefreshed extends InteractionEvent {
  const InteractionStateRefreshed();
}

class InteractionReactRequested extends InteractionEvent {
  const InteractionReactRequested();
}

class InteractionRepostRequested extends InteractionEvent {
  const InteractionRepostRequested();
}

class InteractionRepostDeleted extends InteractionEvent {
  const InteractionRepostDeleted();
}

class InteractionNoteDeleted extends InteractionEvent {
  const InteractionNoteDeleted();
}
