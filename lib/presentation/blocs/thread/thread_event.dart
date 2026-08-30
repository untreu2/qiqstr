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

class ThreadProfilesUpdated extends ThreadEvent {
  final Map<String, Map<String, dynamic>> profiles;
  final int requestId;

  const ThreadProfilesUpdated(this.profiles, this.requestId);

  @override
  List<Object?> get props => [profiles, requestId];
}

class ThreadRepliesUpdated extends ThreadEvent {
  final Map<String, dynamic>? threadData;
  final String rootNoteId;

  const ThreadRepliesUpdated(this.threadData, this.rootNoteId);

  @override
  List<Object?> get props => [threadData, rootNoteId];
}

class ThreadCurrentUserLoaded extends ThreadEvent {
  final Map<String, dynamic> profileMap;
  final int requestId;

  const ThreadCurrentUserLoaded(this.profileMap, this.requestId);

  @override
  List<Object?> get props => [profileMap, requestId];
}

class ThreadNetworkDataLoaded extends ThreadEvent {
  final Map<String, dynamic> threadData;
  final List<String> chain;
  final String currentUserHex;
  final int requestId;

  const ThreadNetworkDataLoaded(
    this.threadData,
    this.chain,
    this.currentUserHex,
    this.requestId,
  );

  @override
  List<Object?> get props => [threadData, chain, currentUserHex, requestId];
}

class ThreadNetworkFailed extends ThreadEvent {
  final int requestId;

  const ThreadNetworkFailed(this.requestId);

  @override
  List<Object?> get props => [requestId];
}
