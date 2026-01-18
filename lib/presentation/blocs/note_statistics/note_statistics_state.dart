import '../../../core/bloc/base/base_state.dart';

abstract class NoteStatisticsState extends BaseState {
  const NoteStatisticsState();
}

class NoteStatisticsInitial extends NoteStatisticsState {
  const NoteStatisticsInitial();
}

class NoteStatisticsLoading extends NoteStatisticsState {
  const NoteStatisticsLoading();
}

class NoteStatisticsLoaded extends NoteStatisticsState {
  final List<Map<String, dynamic>> interactions;
  final Map<String, Map<String, dynamic>> users;

  const NoteStatisticsLoaded({
    required this.interactions,
    required this.users,
  });

  NoteStatisticsLoaded copyWith({
    List<Map<String, dynamic>>? interactions,
    Map<String, Map<String, dynamic>>? users,
  }) {
    return NoteStatisticsLoaded(
      interactions: interactions ?? this.interactions,
      users: users ?? this.users,
    );
  }

  @override
  List<Object?> get props => [interactions, users];
}
