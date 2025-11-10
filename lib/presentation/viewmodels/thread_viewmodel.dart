import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../core/base/app_error.dart';
import '../../data/repositories/thread_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../models/note_model.dart';
import '../../models/user_model.dart';

export '../../data/repositories/thread_repository.dart' show ThreadStructure;

class ThreadViewModel extends BaseViewModel with CommandMixin {
  final ThreadRepository _threadRepository;
  final UserRepository _userRepository;
  final AuthRepository _authRepository;

  ThreadViewModel({
    required ThreadRepository threadRepository,
    required UserRepository userRepository,
    required AuthRepository authRepository,
  })  : _threadRepository = threadRepository,
        _userRepository = userRepository,
        _authRepository = authRepository;

  UIState<NoteModel> _rootNoteState = const InitialState();
  UIState<NoteModel> get rootNoteState => _rootNoteState;

  UIState<List<NoteModel>> _repliesState = const InitialState();
  UIState<List<NoteModel>> get repliesState => _repliesState;

  UIState<ThreadStructure> _threadStructureState = const InitialState();
  UIState<ThreadStructure> get threadStructureState => _threadStructureState;

  final Map<String, UserModel> _userProfiles = {};
  Map<String, UserModel> get userProfiles => _userProfiles;

  final StreamController<Map<String, UserModel>> _profilesController = StreamController<Map<String, UserModel>>.broadcast();
  Stream<Map<String, UserModel>> get profilesStream => _profilesController.stream;

  String _rootNoteId = '';
  String get rootNoteId => _rootNoteId;

  String? _focusedNoteId;
  String? get focusedNoteId => _focusedNoteId;

  String _currentUserNpub = '';
  String get currentUserNpub => _currentUserNpub;

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

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

    _loadCurrentUser();
    _loadExistingProfileCache();
    _subscribeToThreadUpdates();
    loadThread();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final result = await _authRepository.getCurrentUserNpub();
      if (result.isSuccess && result.data != null) {
        _currentUserNpub = result.data!;

        final userResult = await _userRepository.getCurrentUser();
        if (userResult.isSuccess && userResult.data != null) {
          _currentUser = userResult.data!;
          safeNotifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[ThreadViewModel] Error loading current user: $e');
    }
  }

  void _loadExistingProfileCache() {
    try {
      final cachedUsers = _userRepository.getAllCachedUsers();
      _userProfiles.addAll(cachedUsers);
      debugPrint('[ThreadViewModel] Loaded ${cachedUsers.length} cached profiles');
      
      if (_userProfiles.isNotEmpty) {
        _profilesController.add(Map.from(_userProfiles));
        safeNotifyListeners();
      }
    } catch (e) {
      debugPrint('[ThreadViewModel] Error loading profile cache: $e');
    }
  }

  Future<void> loadThread() async {
    await executeOperation('loadThread', () async {
      try {
        final cachedRootResult = await _threadRepository.getRootNote(_rootNoteId);
        final cachedRepliesResult = await _threadRepository.getThreadReplies(_rootNoteId);

        bool hasImmediateData = false;

        if (cachedRootResult.isSuccess && cachedRootResult.data != null) {
          _rootNoteState = LoadedState(cachedRootResult.data!);
          hasImmediateData = true;
        }

        if (cachedRepliesResult.isSuccess && 
            cachedRepliesResult.data != null && 
            cachedRootResult.isSuccess && 
            cachedRootResult.data != null) {
          _repliesState = LoadedState(cachedRepliesResult.data!);

          final structure = _threadRepository.buildThreadStructure(cachedRootResult.data!, cachedRepliesResult.data!);
          _threadStructureState = LoadedState(structure);

          hasImmediateData = true;
        }

        if (hasImmediateData) {
          safeNotifyListeners();
        } else {
          _rootNoteState = const LoadingState();
          safeNotifyListeners();
        }

        final threadResult = await _threadRepository.loadThread(_rootNoteId);

        threadResult.fold(
          (threadData) {
            final shouldUpdate = !hasImmediateData || _hasDataChanged(threadData.rootNote, threadData.replies);
            if (shouldUpdate) {
              _rootNoteState = LoadedState(threadData.rootNote);
              _repliesState = LoadedState(threadData.replies);
              _threadStructureState = LoadedState(threadData.structure);

              final allThreadNotes = [threadData.rootNote, ...threadData.replies];
              _loadInteractionsForThread(allThreadNotes);
              safeNotifyListeners();
            } else {
              _loadInteractionsForThread([threadData.rootNote, ...threadData.replies]);
            }
          },
          (error) {
            _rootNoteState = ErrorState(error);
            _repliesState = ErrorState(error);
            safeNotifyListeners();
          },
        );
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

      final result = await _threadRepository.addReply(
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


  Future<void> _loadInteractionsForThread(List<NoteModel> notes) async {
    try {
      await _threadRepository.fetchInteractionsForThread(notes);
      safeNotifyListeners();
    } catch (e) {
      debugPrint('[ThreadViewModel] Error loading interactions for thread: $e');
    }
  }


  void _subscribeToThreadUpdates() {
    addSubscription(
      _threadRepository.realTimeNotesStream.listen((notes) {
        if (!isDisposed && _rootNoteState.isLoaded) {
          if (_focusedNoteId != null) {
            final newFocusedNotes = notes.where((note) => note.id == _focusedNoteId).toList();
            if (newFocusedNotes.isNotEmpty) {
              loadThread();
              return;
            }
          }

          final currentReplies = _repliesState.data ?? [];
          final currentReplyIds = currentReplies.map((r) => r.id).toSet();
          
          final newReplies = notes.where((note) {
            if (currentReplyIds.contains(note.id)) return false;
            if (note.isReply && (note.rootId == _rootNoteId || note.parentId == _rootNoteId)) {
              return true;
            }
            if (note.isReply && currentReplyIds.isNotEmpty) {
              return note.parentId != null && currentReplyIds.contains(note.parentId);
            }
            return false;
          }).toList();

          if (newReplies.isNotEmpty) {
            debugPrint('[ThreadViewModel] Detected ${newReplies.length} new replies, loading interactions');
            _loadInteractionsForThread(newReplies).then((_) {
              loadThread();
            });
          }
        }
      }),
    );
  }

  Future<void> reactToNote(String noteId, String reaction) async {
    try {
      final result = await _threadRepository.reactToNote(noteId, reaction);
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
      final result = await _threadRepository.repostNote(noteId);
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
    _profilesController.close();
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
