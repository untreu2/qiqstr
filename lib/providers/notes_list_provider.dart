import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../models/note_model.dart';
import '../services/data_service.dart';
import '../services/data_service_manager.dart';
import '../services/batch_processing_service.dart';
import '../services/network_service.dart';
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

  // Cache for filtered notes to avoid recomputation
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

  void _initialize() {
    dataService.notesNotifier.addListener(_onNotesChanged);
    _onNotesChanged();

    if (!_isInitialized) {
      // Optimize initialization delays - much faster for profile, reasonable for feed
      final initDelay = dataType == DataType.profile ? const Duration(milliseconds: 50) : const Duration(milliseconds: 200);

      Timer(initDelay, () {
        _isInitialized = true;
        notifyListeners();
        _startPeriodicUpdates();
      });
    }
  }

  void _onNotesChanged() {
    _notes = dataService.notesNotifier.value;
    _updateFilteredNotesProgressive();
  }

  void _updateFilteredNotesProgressive() {
    // Only recompute if notes changed
    if (_cachedFilteredNotes == null || _notes.length != _lastNotesLength) {
      _cachedFilteredNotes = _notes.where((n) => !n.isReply || n.isRepost).toList();
      _lastNotesLength = _notes.length;
    }

    _filteredNotes = _cachedFilteredNotes!;

    if (_isInitialized) {
      notifyListeners();
    }

    // Defer user profile loading to next frame
    if (_filteredNotes.isNotEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _loadUserProfiles();
      });
    }
  }

  void _startPeriodicUpdates() {
    // Only refresh data for feed, don't waste cycles calling notifyListeners
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

      await dataService.initializeLightweight();
      _updateFilteredNotesProgressive();

      if (_isLoading) {
        _setLoading(false);
      }

      // Simplified background initialization
      Future.microtask(() async {
        try {
          if (dataType == DataType.profile) {
            // Parallel initialization for profile
            await Future.wait([
              dataService.initializeHeavyOperations(),
              dataService.initializeConnections(),
            ], eagerError: false);
            debugPrint('[NotesListProvider] Profile: Parallel operations completed');
          } else {
            // Sequential for feed with quick refresh
            await dataService.initializeHeavyOperations();
            await dataService.initializeConnections();

            // Quick refresh after initialization
            createTimer(const Duration(milliseconds: 200), _refreshNewNotes);
            debugPrint('[NotesListProvider] Feed: Background operations completed');
          }
          _updateFilteredNotesProgressive();
        } catch (e) {
          handleError('background initialization', e);
        }
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
      // Simplified user loading - no need for complex batching
      UserProvider.instance.loadUsers(userNpubs.toList()).catchError((e) {
        handleError('user profile load', e);
      });

      debugPrint('[NotesListProvider] ${dataType.name}: Loaded ${userNpubs.length} user profiles');
    }
  }

  // Track fetched interactions to avoid duplicate requests
  final Set<String> _fetchedInteractions = {};
  Timer? _interactionCleanupTimer;

  Future<void> fetchInteractionsForNotes(List<String> noteIds) async {
    if (noteIds.isEmpty) return;

    try {
      // Filter out already fetched interactions
      final newNoteIds = noteIds.where((id) => !_fetchedInteractions.contains(id)).toList();

      if (newNoteIds.isEmpty) {
        debugPrint('[NotesListProvider] All ${noteIds.length} visible notes already have fetched interactions');
        return;
      }

      // Mark as fetched immediately to prevent duplicate requests
      _fetchedInteractions.addAll(newNoteIds);

      // Use only the optimized data service method - no duplicate processing
      await dataService.fetchInteractionsForEvents(newNoteIds);

      debugPrint(
          '[NotesListProvider] Fetched interactions for ${newNoteIds.length} new visible notes (${noteIds.length - newNoteIds.length} already cached)');

      // Schedule cleanup of fetch tracking
      _scheduleInteractionCleanup();
    } catch (e) {
      handleError('fetching interactions for visible notes', e);
      // Remove failed fetches from cache to retry later
      _fetchedInteractions.removeWhere((id) => noteIds.contains(id));
    }
  }

  void _scheduleInteractionCleanup() {
    _interactionCleanupTimer?.cancel();
    _interactionCleanupTimer = Timer(const Duration(minutes: 5), () {
      if (_fetchedInteractions.length > 500) {
        // Keep only the most recent 300 to prevent memory bloat
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
        await UserProvider.instance.loadUsers(authorNpubs.toList());
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

    // Clear caches and timers
    _cachedFilteredNotes = null;
    _fetchedInteractions.clear();
    _interactionCleanupTimer?.cancel();

    super.dispose();
  }
}
