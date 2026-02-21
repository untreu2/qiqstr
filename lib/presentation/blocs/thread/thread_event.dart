import '../../../core/bloc/base/base_event.dart';

abstract class ThreadEvent extends BaseEvent {
  const ThreadEvent();
}

class ThreadLoadRequested extends ThreadEvent {
  final List<String> chain;
  final Map<String, dynamic>? initialNoteData;

  const ThreadLoadRequested({
    required this.chain,
    this.initialNoteData,
  });

  @override
  List<Object?> get props => [chain, initialNoteData];
}

class ThreadRefreshed extends ThreadEvent {
  const ThreadRefreshed();
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
