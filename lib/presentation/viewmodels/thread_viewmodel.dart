import 'dart:async';

import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../core/base/app_error.dart';
import '../../core/base/result.dart';
import '../../data/repositories/note_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/nostr_data_service.dart';
import '../../data/services/user_batch_fetcher.dart';
import '../../models/note_model.dart';
import '../../models/user_model.dart';

class ThreadViewModel extends BaseViewModel with CommandMixin {
  final NoteRepository _noteRepository;
  final UserRepository _userRepository;
  final NostrDataService _nostrDataService;

  ThreadViewModel({
    required NoteRepository noteRepository,
    required UserRepository userRepository,
    required NostrDataService nostrDataService,
  })  : _noteRepository = noteRepository,
        _userRepository = userRepository,
        _nostrDataService = nostrDataService;

  UIState<NoteModel> _rootNoteState = const InitialState();
  UIState<NoteModel> get rootNoteState => _rootNoteState;

  UIState<List<NoteModel>> _repliesState = const InitialState();
  UIState<List<NoteModel>> get repliesState => _repliesState;

  UIState<ThreadStructure> _threadStructureState = const InitialState();
  UIState<ThreadStructure> get threadStructureState => _threadStructureState;

  final Map<String, UserModel> _userProfiles = {};
  Map<String, UserModel> get userProfiles => Map.unmodifiable(_userProfiles);

  String _rootNoteId = '';
  String get rootNoteId => _rootNoteId;

  String? _focusedNoteId;
  String? get focusedNoteId => _focusedNoteId;

  LoadThreadCommand? _loadThreadCommand;
  AddReplyCommand? _addReplyCommand;
  RefreshThreadCommand? _refreshThreadCommand;

  LoadThreadCommand get loadThreadCommand => _loadThreadCommand ??= LoadThreadCommand(this);
  AddReplyCommand get addReplyCommand => _addReplyCommand ??= AddReplyCommand(this);
  RefreshThreadCommand get refreshThreadCommand => _refreshThreadCommand ??= RefreshThreadCommand(this);

  @override
  void initialize() {
    super.initialize();

    registerCommand('loadThread', loadThreadCommand);
    registerCommand('addReply', addReplyCommand);
    registerCommand('refreshThread', refreshThreadCommand);
  }

  void initializeWithThread({
    required String rootNoteId,
    String? focusedNoteId,
  }) {
    _rootNoteId = rootNoteId;
    _focusedNoteId = focusedNoteId;

    _nostrDataService.setContext('thread');

    _subscribeToThreadUpdates();
    loadThread();
  }

  Future<void> loadThread() async {
    await executeOperation('loadThread', () async {
      try {
        final cachedRootResult = await _noteRepository.getNoteById(_rootNoteId);
        final cachedRepliesResult = await _noteRepository.getThreadReplies(_rootNoteId);

        bool hasImmediateData = false;

        if (cachedRootResult.isSuccess && cachedRootResult.data != null) {
          _rootNoteState = LoadedState(cachedRootResult.data!);
          hasImmediateData = true;
        }

        if (cachedRepliesResult.isSuccess && cachedRepliesResult.data != null) {
          _repliesState = LoadedState(cachedRepliesResult.data!);

          final structure = _buildThreadStructure(cachedRootResult.data!, cachedRepliesResult.data!);
          _threadStructureState = LoadedState(structure);

          hasImmediateData = true;
        }

        if (hasImmediateData) {
          safeNotifyListeners();
        } else {
          _rootNoteState = const LoadingState();
          safeNotifyListeners();
        }

        final results = await Future.wait([
          _noteRepository.getNoteById(_rootNoteId),
          _noteRepository.getThreadReplies(_rootNoteId),
        ]);

        final rootResult = results[0] as Result<NoteModel?>;
        if (rootResult.isError) {
          _rootNoteState = ErrorState(rootResult.error!);
          _repliesState = ErrorState(rootResult.error!);
          safeNotifyListeners();
          return;
        }

        final rootNote = rootResult.data;
        if (rootNote == null) {
          _rootNoteState = const ErrorState('Note not found');
          _repliesState = const ErrorState('Note not found');
          safeNotifyListeners();
          return;
        }

        _rootNoteState = LoadedState(rootNote);

        final repliesResult = results[1] as Result<List<NoteModel>>;
        if (repliesResult.isSuccess) {
          final replies = repliesResult.data!;

          final shouldUpdate = !hasImmediateData || _hasDataChanged(rootNote, replies);
          if (shouldUpdate) {
            _rootNoteState = LoadedState(rootNote);
            _repliesState = LoadedState(replies);

            final structure = _buildThreadStructure(rootNote, replies);
            _threadStructureState = LoadedState(structure);

            final allThreadNotes = [rootNote, ...replies];
            _loadUserProfiles(allThreadNotes);
            safeNotifyListeners();
          }
        } else {
          _repliesState = ErrorState(repliesResult.error!);
          safeNotifyListeners();
        }
      } catch (e) {
        _rootNoteState = ErrorState('Failed to load thread: $e');
        _repliesState = ErrorState('Failed to load thread: $e');
        safeNotifyListeners();
      }
    });
  }

  bool _hasDataChanged(NoteModel? newRootNote, List<NoteModel> newReplies) {
    if (_rootNoteState.isLoaded && newRootNote != null) {
      final currentRoot = _rootNoteState.data!;
      if (currentRoot.id != newRootNote.id) {
        return true;
      }
    }

    if (_repliesState.isLoaded) {
      final currentReplies = _repliesState.data!;
      if (currentReplies.length != newReplies.length) {
        return true;
      }
    }

    return false;
  }

  Future<void> refreshThread() async {
    await loadThread();
  }

  Future<void> addReply({
    required String content,
    required String parentNoteId,
    String? rootId,
  }) async {
    await executeOperation('addReply', () async {
      final parentNote =
          _rootNoteId == parentNoteId ? _rootNoteState.data : _repliesState.data?.where((n) => n.id == parentNoteId).firstOrNull;

      if (parentNote == null) {
        throw Exception('Parent note not found');
      }

      final result = await _noteRepository.postReply(
        content: content,
        rootId: rootId ?? _rootNoteId,
        replyId: parentNoteId,
        parentAuthor: parentNote.author,
        relayUrls: ['wss://relay.damus.io'],
      );

      if (result.isError) {
        throw Exception(result.error);
      }

      await loadThread();
    });
  }

  Future<void> _loadUserProfiles(List<NoteModel> notes) async {
    try {
      final Set<String> authorIds = {};
      for (final note in notes) {
        authorIds.add(note.author);
      }

      final missingAuthorIds = authorIds.where((id) => !_userProfiles.containsKey(id)).take(10).toList();

      if (missingAuthorIds.isEmpty) {
        return;
      }

      final results = await _userRepository.getUserProfiles(
        missingAuthorIds,
        priority: FetchPriority.low,
      );

      for (final entry in results.entries) {
        entry.value.fold(
          (user) {
            _userProfiles[entry.key] = user;
          },
          (error) {
            _userProfiles[entry.key] = UserModel(
              pubkeyHex: entry.key,
              name: entry.key.length > 8 ? entry.key.substring(0, 8) : entry.key,
              about: '',
              profileImage: '',
              banner: '',
              website: '',
              nip05: '',
              lud16: '',
              updatedAt: DateTime.now(),
              nip05Verified: false,
            );
          },
        );
      }
    } catch (e) {}
  }

  ThreadStructure _buildThreadStructure(NoteModel root, List<NoteModel> replies) {
    final Map<String, List<NoteModel>> childrenMap = {};
    final Map<String, NoteModel> notesMap = {root.id: root};

    for (final reply in replies) {
      notesMap[reply.id] = reply;
    }

    for (final reply in replies) {
      final parentId = reply.parentId ?? root.id;

      childrenMap.putIfAbsent(parentId, () => []);
      childrenMap[parentId]!.add(reply);
    }

    for (final children in childrenMap.values) {
      children.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    return ThreadStructure(
      rootNote: root,
      childrenMap: childrenMap,
      notesMap: notesMap,
      totalReplies: replies.length,
    );
  }

  void _subscribeToThreadUpdates() {
    if (_focusedNoteId != null) {
      addSubscription(
        _noteRepository.realTimeNotesStream.listen((notes) {
          if (!isDisposed && _rootNoteState.isLoaded) {
            final newFocusedNotes = notes.where((note) => note.id == _focusedNoteId).toList();

            if (newFocusedNotes.isNotEmpty) {
              loadThread();
            }
          }
        }),
      );
    }
  }

  Future<void> reactToNote(String noteId, String reaction) async {
    try {
      final result = await _noteRepository.reactToNote(noteId, reaction);
      result.fold(
        (_) {},
        (error) {
          setError(NetworkError(message: 'Failed to react: $error'));
        },
      );
    } catch (e) {
      setError(NetworkError(message: 'Failed to react: $e'));
    }
  }

  Future<void> repostNote(String noteId) async {
    try {
      final result = await _noteRepository.repostNote(noteId);
      result.fold(
        (_) {},
        (error) {
          setError(NetworkError(message: 'Failed to repost: $error'));
        },
      );
    } catch (e) {
      setError(NetworkError(message: 'Failed to repost: $e'));
    }
  }

  List<NoteModel> getReplies(String noteId) {
    if (_threadStructureState.isLoaded) {
      final structure = _threadStructureState.data!;
      return structure.getChildren(noteId);
    }
    return [];
  }

  int getThreadDepth(String noteId) {
    if (_threadStructureState.isLoaded) {
      final structure = _threadStructureState.data!;
      return structure.getDepth(noteId);
    }
    return 0;
  }

  NoteModel? get currentRootNote => _rootNoteState.data;

  List<NoteModel> get currentReplies => _repliesState.data ?? [];

  bool get isThreadLoading => _rootNoteState.isLoading || _repliesState.isLoading;

  String? get threadErrorMessage => _rootNoteState.error ?? _repliesState.error;

  @override
  void dispose() {
    _persistCalculatedCountsOnDispose();
    super.dispose();
  }

  Future<void> _persistCalculatedCountsOnDispose() async {}

  @override
  void onRetry() {
    if (_rootNoteId.isNotEmpty) {
      loadThread();
    }
  }
}

class ThreadStructure {
  final NoteModel rootNote;
  final Map<String, List<NoteModel>> childrenMap;
  final Map<String, NoteModel> notesMap;
  final int totalReplies;

  ThreadStructure({
    required this.rootNote,
    required this.childrenMap,
    required this.notesMap,
    required this.totalReplies,
  });

  List<NoteModel> getChildren(String noteId) {
    return childrenMap[noteId] ?? [];
  }

  NoteModel? getNote(String noteId) {
    return notesMap[noteId];
  }

  int getDepth(String noteId) {
    int depth = 0;
    NoteModel? current = notesMap[noteId];

    while (current != null && current.parentId != null) {
      depth++;
      current = notesMap[current.parentId!];
    }

    return depth;
  }

  bool hasChildren(String noteId) {
    return childrenMap.containsKey(noteId) && childrenMap[noteId]!.isNotEmpty;
  }

  List<NoteModel> getAllNotes() {
    return notesMap.values.toList();
  }
}

class LoadThreadCommand extends ParameterlessCommand {
  final ThreadViewModel _viewModel;

  LoadThreadCommand(this._viewModel);

  @override
  Future<void> executeImpl() => _viewModel.loadThread();
}

class RefreshThreadCommand extends ParameterlessCommand {
  final ThreadViewModel _viewModel;

  RefreshThreadCommand(this._viewModel);

  @override
  Future<void> executeImpl() => _viewModel.refreshThread();
}

class AddReplyCommand extends ParameterizedCommand<ReplyParams> {
  final ThreadViewModel _viewModel;

  AddReplyCommand(this._viewModel);

  @override
  Future<void> executeImpl(ReplyParams params) async {
    await _viewModel.addReply(
      content: params.content,
      parentNoteId: params.parentNoteId,
      rootId: params.rootId,
    );
  }
}

class ReplyParams {
  final String content;
  final String parentNoteId;
  final String? rootId;

  ReplyParams({
    required this.content,
    required this.parentNoteId,
    this.rootId,
  });
}
