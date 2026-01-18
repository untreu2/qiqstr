import '../../../core/bloc/base/base_event.dart';

abstract class NoteContentEvent extends BaseEvent {
  const NoteContentEvent();
}

class NoteContentInitialized extends NoteContentEvent {
  final List<Map<String, dynamic>> textParts;

  const NoteContentInitialized({required this.textParts});

  @override
  List<Object?> get props => [textParts];
}
