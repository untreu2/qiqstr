import '../../../core/bloc/base/base_event.dart';

abstract class FollowSetEvent extends BaseEvent {
  const FollowSetEvent();
}

class FollowSetLoadRequested extends FollowSetEvent {
  const FollowSetLoadRequested();
}

class FollowSetCreated extends FollowSetEvent {
  final String title;
  final String description;
  final List<String> pubkeys;

  const FollowSetCreated({
    required this.title,
    this.description = '',
    this.pubkeys = const [],
  });

  @override
  List<Object?> get props => [title, description, pubkeys];
}

class FollowSetDeleted extends FollowSetEvent {
  final String dTag;

  const FollowSetDeleted(this.dTag);

  @override
  List<Object?> get props => [dTag];
}

class FollowSetUserAdded extends FollowSetEvent {
  final String dTag;
  final String pubkeyHex;

  const FollowSetUserAdded({
    required this.dTag,
    required this.pubkeyHex,
  });

  @override
  List<Object?> get props => [dTag, pubkeyHex];
}

class FollowSetUserRemoved extends FollowSetEvent {
  final String dTag;
  final String pubkeyHex;

  const FollowSetUserRemoved({
    required this.dTag,
    required this.pubkeyHex,
  });

  @override
  List<Object?> get props => [dTag, pubkeyHex];
}

class FollowSetRefreshed extends FollowSetEvent {
  const FollowSetRefreshed();
}
