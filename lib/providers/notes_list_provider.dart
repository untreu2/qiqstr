import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/note_model.dart';
import '../services/data_service.dart';
import '../services/data_service_manager.dart';
import '../providers/user_provider.dart';
import 'base_provider.dart';

class NotesListProvider extends BaseProvider {
  final String npub;
  final DataType dataType;
  late final DataService dataService;

  List<NoteModel> _notes = [];
  List<NoteModel> _filteredNotes = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasError = false;
  String? _errorMessage;

  bool _isInitialized = false;

  String? _currentUserNpub;

  int _newNotesCount = 0;
  List<String> _lastKnownNoteIds = [];

  List<NoteModel>? _cachedFilteredNotes;
  int _lastNotesLength = 0;

  NotesListProvider({
    required this.npub,
    required this.dataType,
    DataService? sharedDataService,
  }) {
    if (sharedDataService != null) {
      dataService = sharedDataService;
    } else {
      dataService = DataServiceManager.instance.getOrCreateService(
        npub: npub,
        dataType: dataType,
      );
    }
    _initialize();
  }

  List<NoteModel> get notes => _filteredNotes;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => _filteredNotes.isEmpty && !_isLoading;

  int get newNotesCount => _newNotesCount;
  bool get hasNewNotes => _newNotesCount > 0;

  String get currentUserNpub => _currentUserNpub ?? '';

  void _initialize() {
    dataService.notesNotifier.addListener(_onNotesChanged);
    _onNotesChanged();
    _loadCurrentUserNpub();

    if (!_isInitialized) {
      final initDelay = dataType == DataType.profile ? const Duration(milliseconds: 50) : const Duration(milliseconds: 200);

      Timer(initDelay, () {
        _isInitialized = true;
        notifyListeners();
        _startPeriodicUpdates();
      });
    }
  }

  Future<void> _loadCurrentUserNpub() async {
    try {
      final storage = const FlutterSecureStorage();
      _currentUserNpub = await storage.read(key: 'npub');
      debugPrint('[NotesListProvider] Loaded current user npub: ${_currentUserNpub?.substring(0, 8)}...');
    } catch (e) {
      debugPrint('[NotesListProvider] Error loading current user npub: $e');
    }
  }

  void _onNotesChanged() {
    _notes = dataService.notesNotifier.value;
    _detectNewNotes();
    _updateFilteredNotesProgressive();
  }

  void _detectNewNotes() {
    if (!_isInitialized || dataType != DataType.feed) return;

    final newFilteredNotes = _notes.where((n) => !n.isReply || n.isRepost).toList();
    final currentNoteIds = newFilteredNotes.map((n) => n.id).toList();

    if (_lastKnownNoteIds.isNotEmpty) {
      final newNoteIds = currentNoteIds.where((id) => !_lastKnownNoteIds.contains(id)).toList();
      if (newNoteIds.isNotEmpty) {
        _newNotesCount += newNoteIds.length;
        print('[NotesListProvider] Detected ${newNoteIds.length} new notes (total pending: $_newNotesCount)');
      }
    }

    _lastKnownNoteIds = currentNoteIds;
  }

  void _updateFilteredNotesProgressive() {
    if (_cachedFilteredNotes == null || _notes.length != _lastNotesLength) {
      _cachedFilteredNotes = _notes.where((n) => !n.isReply || n.isRepost).toList();
      _lastNotesLength = _notes.length;
    }

    if (_newNotesCount == 0) {
      _filteredNotes = _cachedFilteredNotes!;
    }

    if (_isInitialized) {
      notifyListeners();
    }

    if (_filteredNotes.isNotEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _loadUserProfiles();
      });
    }
  }

  void _startPeriodicUpdates() {
    if (dataType == DataType.feed) {
      createPeriodicTimer(const Duration(seconds: 20), (timer) {
        _refreshNewNotes();
      });
    }
  }

  void _refreshNewNotes() {
    try {
      dataService.refreshNotes().catchError((e) {
        handleError('refresh notes', e);
      });
    } catch (e) {
      handleError('refresh new notes', e);
    }
  }

  void loadNewNotes() {
    if (_newNotesCount == 0) return;

    print('[NotesListProvider] Loading $_newNotesCount new notes');

    _filteredNotes = _cachedFilteredNotes ?? _notes.where((n) => !n.isReply || n.isRepost).toList();

    _newNotesCount = 0;

    _lastKnownNoteIds = _filteredNotes.map((n) => n.id).toList();

    notifyListeners();

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _loadUserProfiles();
    });
  }

  Future<void> fetchInitialNotes() async {
    if (_isLoading) return;

    _setLoading(true);
    _clearError();

    try {
      _updateFilteredNotesProgressive();
      if (dataService.notes.isNotEmpty) {
        _setLoading(false);
        debugPrint('[NotesListProvider] Instant display: ${dataService.notes.length} cached notes');
      }

      // Complete non-blocking initialization
      Future.microtask(() async {
        await dataService.initializeLightweight();
        _updateFilteredNotesProgressive();

        if (_isLoading) {
          _setLoading(false);
        }

        // All heavy operations run in background without blocking UI
        Future.microtask(() async {
          try {
            if (dataType == DataType.profile) {
              Future.microtask(() => dataService.initializeHeavyOperations());
              Future.microtask(() => dataService.initializeConnections());
              debugPrint('[NotesListProvider] Profile: Background operations started');
            } else {
              Future.microtask(() => dataService.initializeHeavyOperations());
              Future.microtask(() => dataService.initializeConnections());

              createTimer(const Duration(milliseconds: 500), _refreshNewNotes);
              debugPrint('[NotesListProvider] Feed: Background operations started');
            }
            _updateFilteredNotesProgressive();
          } catch (e) {
            handleError('background initialization', e);
          }
        });
      });
    } catch (e) {
      _setError('Failed to load notes: $e');
      debugPrint('[NotesListProvider] Initial fetch error: $e');
      _setLoading(false);
    }
  }

  Future<void> fetchMoreNotes() async {
    if (_isLoadingMore || _isLoading) return;

    _setLoadingMore(true);

    try {
      if (dataType == DataType.profile) {
        await dataService.loadMoreNotes();
        debugPrint('[NotesListProvider] Profile: Load more completed faster');
      } else {
        await dataService.loadMoreNotes();

        Future.microtask(() => _refreshNewNotes());
      }
    } catch (e) {
      debugPrint('[NotesListProvider] Load more error: $e');
    } finally {
      _setLoadingMore(false);
    }
  }

  void refresh() {
    _notes.clear();
    _filteredNotes.clear();
    notifyListeners();

    dataService.forceRefresh().then((_) {
      dataService.initializeConnections();
    }).catchError((e) {
      handleError('refresh', e);
    });
  }

  void _loadUserProfiles() {
    if (_filteredNotes.isEmpty) return;

    final batchSize = dataType == DataType.profile ? 15 : 10;
    final firstBatchNotes = _filteredNotes.take(batchSize).toList();

    final userNpubs = <String>{};
    for (final note in firstBatchNotes) {
      userNpubs.add(note.author);
      if (note.repostedBy != null) {
        userNpubs.add(note.repostedBy!);
      }

      if (userNpubs.length >= 12) break;
    }

    if (userNpubs.isNotEmpty) {
      UserProvider.instance.loadUsers(userNpubs.toList()).catchError((e) {
        handleError('user profile load', e);
      });

      debugPrint('[NotesListProvider] ${dataType.name}: Loaded ${userNpubs.length} user profiles');
    }
  }

  final Set<String> _fetchedInteractions = {};
  Timer? _interactionCleanupTimer;

  Future<void> fetchInteractionsForNotes(List<String> noteIds) async {
    if (noteIds.isEmpty) return;

    try {
      final newNoteIds = noteIds.where((id) => !_fetchedInteractions.contains(id)).toList();

      if (newNoteIds.isEmpty) {
        debugPrint('[NotesListProvider] All ${noteIds.length} visible notes already have fetched interactions');
        return;
      }

      _fetchedInteractions.addAll(newNoteIds);

      // Non-blocking interaction fetching
      Future.microtask(() async {
        await dataService.fetchInteractionsForEvents(newNoteIds, forceLoad: true);
      });

      debugPrint(
          '[NotesListProvider] Fetched interactions for ${newNoteIds.length} new visible notes (${noteIds.length - newNoteIds.length} already cached)');

      _scheduleInteractionCleanup();
    } catch (e) {
      handleError('fetching interactions for visible notes', e);

      _fetchedInteractions.removeWhere((id) => noteIds.contains(id));
    }
  }

  void _scheduleInteractionCleanup() {
    _interactionCleanupTimer?.cancel();
    _interactionCleanupTimer = Timer(const Duration(minutes: 5), () {
      if (_fetchedInteractions.length > 500) {
        final recentNoteIds = _filteredNotes.take(300).map((note) => note.id).toSet();
        _fetchedInteractions.retainWhere((id) => recentNoteIds.contains(id));
        debugPrint('[NotesListProvider] Cleaned up interaction fetch cache: ${_fetchedInteractions.length} entries retained');
      }
    });
  }

  Future<void> fetchProfilesForVisibleNotes(List<String> visibleNoteIds) async {
    if (visibleNoteIds.isEmpty) return;

    try {
      final visibleNotes = _filteredNotes.where((note) => visibleNoteIds.contains(note.id)).toList();

      if (visibleNotes.isEmpty) return;

      final authorNpubs = <String>{};
      for (final note in visibleNotes) {
        authorNpubs.add(note.author);
        if (note.repostedBy != null) {
          authorNpubs.add(note.repostedBy!);
        }
      }

      if (authorNpubs.isNotEmpty) {
        // Non-blocking profile loading
        Future.microtask(() async {
          await UserProvider.instance.loadUsers(authorNpubs.toList());
        });
        debugPrint('[NotesListProvider] Loaded profiles for ${authorNpubs.length} authors of ${visibleNotes.length} visible notes');
      }
    } catch (e) {
      handleError('fetching profiles for visible notes', e);
    }
  }

  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      safeNotifyListeners();
    }
  }

  void _setLoadingMore(bool loading) {
    if (_isLoadingMore != loading) {
      _isLoadingMore = loading;
      safeNotifyListeners();
    }
  }

  void _setError(String message) {
    _hasError = true;
    _errorMessage = message;
    safeNotifyListeners();
  }

  void _clearError() {
    if (_hasError) {
      _hasError = false;
      _errorMessage = null;
      safeNotifyListeners();
    }
  }

  @override
  void dispose() {
    dataService.notesNotifier.removeListener(_onNotesChanged);
    DataServiceManager.instance.releaseService(npub: npub, dataType: dataType);

    _cachedFilteredNotes = null;
    _fetchedInteractions.clear();
    _interactionCleanupTimer?.cancel();

    super.dispose();
  }
}
