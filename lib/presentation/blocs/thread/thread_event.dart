import '../../../core/bloc/base/base_event.dart';
import '../../../domain/entities/feed_note.dart';

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

class ThreadProfilesUpdated extends ThreadEvent {
  final Map<String, Map<String, dynamic>> profiles;

  const ThreadProfilesUpdated(this.profiles);

  @override
  List<Object?> get props => [profiles];
}

class ThreadRepliesUpdated extends ThreadEvent {
  final List<FeedNote> replies;

  const ThreadRepliesUpdated(this.replies);

  @override
  List<Object?> get props => [replies];
}

class ThreadCurrentUserLoaded extends ThreadEvent {
  final Map<String, dynamic> profileMap;

  const ThreadCurrentUserLoaded(this.profileMap);

  @override
  List<Object?> get props => [profileMap];
}

class ThreadNetworkDataLoaded extends ThreadEvent {
  final Map<String, dynamic> threadData;
  final List<String> chain;
  final String currentUserHex;

  const ThreadNetworkDataLoaded(this.threadData, this.chain, this.currentUserHex);

  @override
  List<Object?> get props => [threadData, chain, currentUserHex];
}

class ThreadNetworkFailed extends ThreadEvent {
  const ThreadNetworkFailed();

  @override
  List<Object?> get props => [];
}
