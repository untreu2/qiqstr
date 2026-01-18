import '../../../core/bloc/base/base_state.dart';

abstract class ThreadState extends BaseState {
  const ThreadState();
}

class ThreadInitial extends ThreadState {
  const ThreadInitial();
}

class ThreadLoading extends ThreadState {
  const ThreadLoading();
}

class ThreadLoaded extends ThreadState {
  final Map<String, dynamic> rootNote;
  final List<Map<String, dynamic>> replies;
  final ThreadStructure threadStructure;
  final Map<String, dynamic>? focusedNote;
  final Map<String, Map<String, dynamic>> userProfiles;
  final String rootNoteId;
  final String? focusedNoteId;
  final String currentUserNpub;
  final Map<String, dynamic>? currentUser;

  const ThreadLoaded({
    required this.rootNote,
    required this.replies,
    required this.threadStructure,
    this.focusedNote,
    required this.userProfiles,
    required this.rootNoteId,
    this.focusedNoteId,
    required this.currentUserNpub,
    this.currentUser,
  });

  @override
  List<Object?> get props => [
        rootNote,
        replies,
        threadStructure,
        focusedNote,
        userProfiles,
        rootNoteId,
        focusedNoteId,
        currentUserNpub,
        currentUser,
      ];

  ThreadLoaded copyWith({
    Map<String, dynamic>? rootNote,
    List<Map<String, dynamic>>? replies,
    ThreadStructure? threadStructure,
    Map<String, dynamic>? focusedNote,
    Map<String, Map<String, dynamic>>? userProfiles,
    String? rootNoteId,
    String? focusedNoteId,
    String? currentUserNpub,
    Map<String, dynamic>? currentUser,
  }) {
    return ThreadLoaded(
      rootNote: rootNote ?? this.rootNote,
      replies: replies ?? this.replies,
      threadStructure: threadStructure ?? this.threadStructure,
      focusedNote: focusedNote ?? this.focusedNote,
      userProfiles: userProfiles ?? this.userProfiles,
      rootNoteId: rootNoteId ?? this.rootNoteId,
      focusedNoteId: focusedNoteId ?? this.focusedNoteId,
      currentUserNpub: currentUserNpub ?? this.currentUserNpub,
      currentUser: currentUser ?? this.currentUser,
    );
  }
}

class ThreadError extends ThreadState {
  final String message;

  const ThreadError(this.message);

  @override
  List<Object?> get props => [message];
}

class ThreadStructure {
  final Map<String, dynamic> rootNote;
  final Map<String, List<Map<String, dynamic>>> childrenMap;
  final Map<String, Map<String, dynamic>> notesMap;
  final int totalReplies;

  ThreadStructure({
    required this.rootNote,
    required this.childrenMap,
    required this.notesMap,
    required this.totalReplies,
  });

  List<Map<String, dynamic>> getChildren(String noteId) {
    return childrenMap[noteId] ?? [];
  }

  Map<String, dynamic>? getNote(String noteId) {
    return notesMap[noteId];
  }

  bool hasChildren(String noteId) {
    return childrenMap.containsKey(noteId) && childrenMap[noteId]!.isNotEmpty;
  }
}
