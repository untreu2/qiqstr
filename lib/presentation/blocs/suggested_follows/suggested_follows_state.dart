import '../../../core/bloc/base/base_state.dart';

abstract class SuggestedFollowsState extends BaseState {
  const SuggestedFollowsState();
}

class SuggestedFollowsInitial extends SuggestedFollowsState {
  const SuggestedFollowsInitial();
}

class SuggestedFollowsLoading extends SuggestedFollowsState {
  const SuggestedFollowsLoading();
}

class SuggestedFollowsLoaded extends SuggestedFollowsState {
  final List<Map<String, dynamic>> suggestedUsers;
  final Set<String> selectedUsers;
  final bool isProcessing;
  final bool shouldNavigate;

  const SuggestedFollowsLoaded({
    required this.suggestedUsers,
    required this.selectedUsers,
    this.isProcessing = false,
    this.shouldNavigate = false,
  });

  SuggestedFollowsLoaded copyWith({
    List<Map<String, dynamic>>? suggestedUsers,
    Set<String>? selectedUsers,
    bool? isProcessing,
    bool? shouldNavigate,
  }) {
    return SuggestedFollowsLoaded(
      suggestedUsers: suggestedUsers ?? this.suggestedUsers,
      selectedUsers: selectedUsers ?? this.selectedUsers,
      isProcessing: isProcessing ?? this.isProcessing,
      shouldNavigate: shouldNavigate ?? this.shouldNavigate,
    );
  }

  @override
  List<Object?> get props => [suggestedUsers, selectedUsers, isProcessing, shouldNavigate];
}

class SuggestedFollowsError extends SuggestedFollowsState {
  final String message;

  const SuggestedFollowsError(this.message);

  @override
  List<Object?> get props => [message];
}
