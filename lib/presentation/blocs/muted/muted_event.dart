import '../../../core/bloc/base/base_event.dart';

abstract class MutedEvent extends BaseEvent {
  const MutedEvent();
}

class MutedLoadRequested extends MutedEvent {
  const MutedLoadRequested();
}

class MutedUserUnmuted extends MutedEvent {
  final String userNpub;

  const MutedUserUnmuted(this.userNpub);

  @override
  List<Object?> get props => [userNpub];
}

class MutedWordAdded extends MutedEvent {
  final String word;

  const MutedWordAdded(this.word);

  @override
  List<Object?> get props => [word];
}

class MutedWordRemoved extends MutedEvent {
  final String word;

  const MutedWordRemoved(this.word);

  @override
  List<Object?> get props => [word];
}

class MutedRefreshed extends MutedEvent {
  const MutedRefreshed();
}
