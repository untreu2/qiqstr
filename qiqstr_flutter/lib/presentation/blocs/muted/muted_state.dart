import '../../../core/bloc/base/base_state.dart';

abstract class MutedState extends BaseState {
  const MutedState();
}

class MutedInitial extends MutedState {
  const MutedInitial();
}

class MutedLoading extends MutedState {
  const MutedLoading();
}

class MutedLoaded extends MutedState {
  final List<Map<String, dynamic>> mutedUsers;
  final List<String> mutedWords;
  final Map<String, bool> unmutingStates;

  const MutedLoaded({
    required this.mutedUsers,
    required this.mutedWords,
    required this.unmutingStates,
  });

  MutedLoaded copyWith({
    List<Map<String, dynamic>>? mutedUsers,
    List<String>? mutedWords,
    Map<String, bool>? unmutingStates,
  }) {
    return MutedLoaded(
      mutedUsers: mutedUsers ?? this.mutedUsers,
      mutedWords: mutedWords ?? this.mutedWords,
      unmutingStates: unmutingStates ?? this.unmutingStates,
    );
  }

  @override
  List<Object?> get props => [mutedUsers, mutedWords, unmutingStates];
}

class MutedError extends MutedState {
  final String message;

  const MutedError(this.message);

  @override
  List<Object?> get props => [message];
}
