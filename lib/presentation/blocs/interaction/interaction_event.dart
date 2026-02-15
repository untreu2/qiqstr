import '../../../core/bloc/base/base_event.dart';
import '../../../data/services/interaction_service.dart';

abstract class InteractionEvent extends BaseEvent {
  const InteractionEvent();
}

class InteractionInitialized extends InteractionEvent {
  final String noteId;
  final String currentUserHex;
  final Map<String, dynamic>? note;

  const InteractionInitialized({
    required this.noteId,
    required this.currentUserHex,
    this.note,
  });

  @override
  List<Object?> get props => [noteId, currentUserHex, note];
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

class InteractionZapStarted extends InteractionEvent {
  final int amount;

  const InteractionZapStarted({required this.amount});

  @override
  List<Object?> get props => [amount];
}

class InteractionZapCompleted extends InteractionEvent {
  final int amount;

  const InteractionZapCompleted({required this.amount});

  @override
  List<Object?> get props => [amount];
}

class InteractionZapFailed extends InteractionEvent {
  const InteractionZapFailed();
}

class InteractionCountsUpdated extends InteractionEvent {
  final InteractionCounts counts;

  const InteractionCountsUpdated(this.counts);

  @override
  List<Object?> get props => [counts];
}
