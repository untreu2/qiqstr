import '../../../core/bloc/base/base_event.dart';

abstract class SuggestedFollowsEvent extends BaseEvent {
  const SuggestedFollowsEvent();
}

class SuggestedFollowsLoadRequested extends SuggestedFollowsEvent {
  const SuggestedFollowsLoadRequested();
}

class SuggestedFollowsUserToggled extends SuggestedFollowsEvent {
  final String npub;

  const SuggestedFollowsUserToggled(this.npub);

  @override
  List<Object?> get props => [npub];
}

class SuggestedFollowsFollowSelectedRequested extends SuggestedFollowsEvent {
  const SuggestedFollowsFollowSelectedRequested();
}

class SuggestedFollowsSkipRequested extends SuggestedFollowsEvent {
  const SuggestedFollowsSkipRequested();
}
