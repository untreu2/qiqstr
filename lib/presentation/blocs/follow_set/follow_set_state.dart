import '../../../core/bloc/base/base_state.dart';
import '../../../domain/entities/follow_set.dart';

abstract class FollowSetState extends BaseState {
  const FollowSetState();
}

class FollowSetInitial extends FollowSetState {
  const FollowSetInitial();
}

class FollowSetLoading extends FollowSetState {
  const FollowSetLoading();
}

class FollowSetLoaded extends FollowSetState {
  final List<FollowSet> followSets;
  final List<FollowSet> followedUsersSets;
  final Map<String, List<Map<String, dynamic>>> resolvedProfiles;
  final Map<String, Map<String, String>> resolvedAuthors;

  const FollowSetLoaded({
    required this.followSets,
    this.followedUsersSets = const [],
    this.resolvedProfiles = const {},
    this.resolvedAuthors = const {},
  });

  FollowSetLoaded copyWith({
    List<FollowSet>? followSets,
    List<FollowSet>? followedUsersSets,
    Map<String, List<Map<String, dynamic>>>? resolvedProfiles,
    Map<String, Map<String, String>>? resolvedAuthors,
  }) {
    return FollowSetLoaded(
      followSets: followSets ?? this.followSets,
      followedUsersSets: followedUsersSets ?? this.followedUsersSets,
      resolvedProfiles: resolvedProfiles ?? this.resolvedProfiles,
      resolvedAuthors: resolvedAuthors ?? this.resolvedAuthors,
    );
  }

  @override
  List<Object?> get props =>
      [followSets, followedUsersSets, resolvedProfiles, resolvedAuthors];
}

class FollowSetError extends FollowSetState {
  final String message;

  const FollowSetError(this.message);

  @override
  List<Object?> get props => [message];
}
