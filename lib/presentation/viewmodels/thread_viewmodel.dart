import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../core/base/app_error.dart';
import '../../data/repositories/note_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/user_batch_fetcher.dart';
import '../../models/note_model.dart';
import '../../models/user_model.dart';

class ThreadViewModel extends BaseViewModel with CommandMixin {
  final NoteRepository _noteRepository;
  final UserRepository _userRepository;
  final AuthRepository _authRepository;

  ThreadViewModel({
    required NoteRepository noteRepository,
    required UserRepository userRepository,
    required AuthRepository authRepository,
  })  : _noteRepository = noteRepository,
        _userRepository = userRepository,
        _authRepository = authRepository;

  UIState<NoteModel> _rootNoteState = const InitialState();
  UIState<NoteModel> get rootNoteState => _rootNoteState;

  UIState<List<NoteModel>> _repliesState = const InitialState();
  UIState<List<NoteModel>> get repliesState => _repliesState;

  UIState<ThreadStructure> _threadStructureState = const InitialState();
  UIState<ThreadStructure> get threadStructureState => _threadStructureState;

  UIState<NoteModel> _focusedNoteState = const InitialState();
  UIState<NoteModel> get focusedNoteState => _focusedNoteState;

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
    
    if (focusedNoteId != null) {
      _loadFocusedNoteFromCache();
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isDisposed) {
        loadThread();
      }
    });
  }

  void changeFocusedNote(String? noteId) {
    if (_focusedNoteId == noteId) return;
    
    _focusedNoteId = noteId;
    
    if (noteId == null) {
      _focusedNoteState = const InitialState();
    } else {
      final threadStructure = _threadStructureState.data;
      if (threadStructure != null) {
        final note = threadStructure.getNote(noteId);
        if (note != null) {
          _focusedNoteState = LoadedState(note);
        } else {
          _loadFocusedNoteFromCache();
        }
      } else {
        _loadFocusedNoteFromCache();
      }
    }
    
    safeNotifyListeners();
  }

  Future<void> _loadFocusedNoteFromCache() async {
    if (_focusedNoteId == null) return;

    try {
      final result = await _noteRepository.getNoteById(_focusedNoteId!);
      if (result.isSuccess && result.data != null) {
        _focusedNoteState = LoadedState(result.data!);
        safeNotifyListeners();
      }
    } catch (e) {
      debugPrint('[ThreadViewModel] Error loading focused note from cache: $e');
    }
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
        final cachedRootResult = await _noteRepository.getNoteById(_rootNoteId);
        final cachedRepliesResult = await _noteRepository.getThreadReplies(_rootNoteId);

        final rootNote = cachedRootResult.data;
        final replies = cachedRepliesResult.data ?? [];

        if (rootNote == null) {
          _rootNoteState = const ErrorState('Note not found');
          _repliesState = const ErrorState('Note not found');
          safeNotifyListeners();
          return;
        }

        _rootNoteState = LoadedState(rootNote);
        _repliesState = LoadedState(replies);

        final structure = _buildThreadStructure(rootNote, replies);
        _threadStructureState = LoadedState(structure);

        final allThreadNotes = [rootNote, ...replies];
        _loadUserProfiles(allThreadNotes);
        safeNotifyListeners();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!isDisposed) {
            _noteRepository.getThreadReplies(_rootNoteId, fetchFromRelays: true).then((result) {
              if (!isDisposed && result.isSuccess) {
                final newReplies = result.data ?? [];
                if (newReplies.length != replies.length) {
                  _repliesState = LoadedState(newReplies);
                  final newStructure = _buildThreadStructure(rootNote, newReplies);
                  _threadStructureState = LoadedState(newStructure);
                  _loadUserProfiles([rootNote, ...newReplies]);
                  safeNotifyListeners();
                }
              }
            });
          }
        });
      } catch (e) {
        _rootNoteState = ErrorState('Failed to load thread: $e');
        _repliesState = ErrorState('Failed to load thread: $e');
        safeNotifyListeners();
      }
    });
  }


  Future<void> refreshThread() async {
    await loadThread();
  }


  Future<void> checkRepliesFromCache() async {
    try {
      final cachedRepliesResult = await _noteRepository.getThreadReplies(_rootNoteId);
      
      if (cachedRepliesResult.isSuccess && cachedRepliesResult.data != null) {
        final replies = cachedRepliesResult.data!;
        final currentReplies = _repliesState.data ?? [];
        
        if (replies.length != currentReplies.length || 
            replies.any((r) => !currentReplies.any((cr) => cr.id == r.id))) {
          final rootNote = _rootNoteState.data;
          if (rootNote != null) {
            final structure = _buildThreadStructure(rootNote, replies);
            _threadStructureState = LoadedState(structure);
            _repliesState = LoadedState(replies);
            
            final newReplies = replies.where((r) => !currentReplies.any((cr) => cr.id == r.id)).toList();
            if (newReplies.isNotEmpty) {
              final allThreadNotes = [rootNote, ...newReplies];
              _loadUserProfiles(allThreadNotes);
            }
            
            safeNotifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('[ThreadViewModel] Error checking replies from cache: $e');
    }
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
            _userProfiles[entry.key] = UserModel.create(
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

      if (_userProfiles.isNotEmpty) {
        _profilesController.add(Map.from(_userProfiles));
      }
    } catch (e) {
      debugPrint('[ThreadViewModel] Error loading user profiles: $e');
    }
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
    addSubscription(
      _noteRepository.realTimeNotesStream.listen((notes) {
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

          final updatedReplies = notes.where((note) {
            if (!currentReplyIds.contains(note.id)) return false;
            if (note.isReply && (note.rootId == _rootNoteId || note.parentId == _rootNoteId)) {
              return true;
            }
            if (note.isReply && currentReplyIds.isNotEmpty) {
              return note.parentId != null && currentReplyIds.contains(note.parentId);
            }
            return false;
          }).toList();

          if (newReplies.isNotEmpty || updatedReplies.isNotEmpty) {
            debugPrint('[ThreadViewModel] Detected ${newReplies.length} new replies and ${updatedReplies.length} updated replies, updating UI');
            _updateThreadWithReplies(newReplies, updatedReplies);
          }
        }
      }),
    );
  }

  Future<void> _updateThreadWithReplies(List<NoteModel> newReplies, List<NoteModel> updatedReplies) async {
    try {
      final currentReplies = _repliesState.data ?? [];
      final updatedRepliesList = List<NoteModel>.from(currentReplies);
      
      for (final updatedReply in updatedReplies) {
        final index = updatedRepliesList.indexWhere((r) => r.id == updatedReply.id);
        if (index != -1) {
          updatedRepliesList[index] = updatedReply;
        }
      }
      
      for (final newReply in newReplies) {
        if (!updatedRepliesList.any((r) => r.id == newReply.id)) {
          updatedRepliesList.add(newReply);
        }
      }

      updatedRepliesList.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final rootNote = _rootNoteState.data;
      if (rootNote != null) {
        final structure = _buildThreadStructure(rootNote, updatedRepliesList);
        _threadStructureState = LoadedState(structure);
        _repliesState = LoadedState(updatedRepliesList);

        final allNewNotes = [...newReplies, ...updatedReplies];
        if (allNewNotes.isNotEmpty) {
          _loadUserProfiles(allNewNotes);
        }
        
        safeNotifyListeners();
      }
    } catch (e) {
      debugPrint('[ThreadViewModel] Error updating thread with replies: $e');
      loadThread();
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

  List<NoteModel> getParentChain(String noteId) {
    final chain = <NoteModel>[];
    NoteModel? current = notesMap[noteId];
    
    if (current == null) return chain;
    if (current.id == rootNote.id) return chain;
    
    final visited = <String>{};
    
    while (current != null && !visited.contains(current.id)) {
      visited.add(current.id);
      
      if (current.parentId == null) {
        break;
      }
      
      if (current.parentId == rootNote.id) {
        chain.insert(0, rootNote);
        break;
      }
      
      final parent = notesMap[current.parentId!];
      if (parent == null) {
        break;
      }
      
      if (parent.isRepost) {
        if (parent.rootId == rootNote.id) {
          chain.insert(0, rootNote);
        }
        break;
      }
      
      if (parent.id == rootNote.id) {
        chain.insert(0, rootNote);
        break;
      }
      
      chain.insert(0, parent);
      current = parent;
    }
    
    return chain;
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
