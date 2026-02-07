import '../../../core/bloc/base/base_event.dart';

abstract class NoteContentEvent extends BaseEvent {
  const NoteContentEvent();
}

class NoteContentInitialized extends NoteContentEvent {
  final List<Map<String, dynamic>> textParts;
  final Map<String, Map<String, dynamic>>? initialProfiles;

  const NoteContentInitialized({
    required this.textParts,
    this.initialProfiles,
  });

  @override
  List<Object?> get props => [textParts, initialProfiles];
}
