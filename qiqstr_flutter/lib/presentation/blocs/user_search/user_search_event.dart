import '../../../core/bloc/base/base_event.dart';

abstract class UserSearchEvent extends BaseEvent {
  const UserSearchEvent();
}

class UserSearchQueryChanged extends UserSearchEvent {
  final String query;

  const UserSearchQueryChanged(this.query);

  @override
  List<Object?> get props => [query];
}
