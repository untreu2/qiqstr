import '../../../core/bloc/base/base_state.dart';

abstract class NoteContentState extends BaseState {
  const NoteContentState();
}

class NoteContentInitial extends NoteContentState {
  const NoteContentInitial();
}

class NoteContentLoaded extends NoteContentState {
  final Map<String, Map<String, dynamic>> mentionUsers;

  const NoteContentLoaded({required this.mentionUsers});

  NoteContentLoaded copyWith({
    Map<String, Map<String, dynamic>>? mentionUsers,
  }) {
    return NoteContentLoaded(
      mentionUsers: mentionUsers ?? this.mentionUsers,
    );
  }

  @override
  List<Object?> get props => [mentionUsers];
}
