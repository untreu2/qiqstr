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
  final List<Map<String, dynamic>> chainNotes;
  final List<String> chain;
  final Map<String, Map<String, dynamic>> userProfiles;
  final String currentUserHex;
  final Map<String, dynamic>? currentUser;
  final bool repliesSynced;

  const ThreadLoaded({
    required this.rootNote,
    required this.replies,
    required this.threadStructure,
    required this.chainNotes,
    required this.chain,
    required this.userProfiles,
    required this.currentUserHex,
    this.currentUser,
    this.repliesSynced = false,
  });

  Map<String, dynamic> get focusedNote => chainNotes.last;
  String get focusedNoteId => focusedNote['id'] as String? ?? '';
  String get rootNoteId => rootNote['id'] as String? ?? '';

  List<Map<String, dynamic>> get contextNotes =>
      chainNotes.length > 1 ? chainNotes.sublist(0, chainNotes.length - 1) : [];

  @override
  List<Object?> get props => [
        rootNote,
        replies,
        threadStructure,
        chainNotes,
        chain,
        userProfiles,
        currentUserHex,
        currentUser,
        repliesSynced,
      ];

  ThreadLoaded copyWith({
    Map<String, dynamic>? rootNote,
    List<Map<String, dynamic>>? replies,
    ThreadStructure? threadStructure,
    List<Map<String, dynamic>>? chainNotes,
    List<String>? chain,
    Map<String, Map<String, dynamic>>? userProfiles,
    String? currentUserHex,
    Map<String, dynamic>? currentUser,
    bool? repliesSynced,
  }) {
    return ThreadLoaded(
      rootNote: rootNote ?? this.rootNote,
      replies: replies ?? this.replies,
      threadStructure: threadStructure ?? this.threadStructure,
      chainNotes: chainNotes ?? this.chainNotes,
      chain: chain ?? this.chain,
      userProfiles: userProfiles ?? this.userProfiles,
      currentUserHex: currentUserHex ?? this.currentUserHex,
      currentUser: currentUser ?? this.currentUser,
      repliesSynced: repliesSynced ?? this.repliesSynced,
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
