import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/note_model.dart';
import '../services/data_service.dart';
import '../services/data_service_manager.dart';
import '../services/batch_processing_service.dart';
import '../services/network_service.dart';
import '../providers/user_provider.dart';

class NotesListProvider extends ChangeNotifier {
  final String npub;
  final DataType dataType;
  late final DataService dataService;

  List<NoteModel> _notes = [];
  List<NoteModel> _filteredNotes = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasError = false;
  String? _errorMessage;

  Timer? _periodicTimer;
  bool _isInitialized = false;

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
      Timer(const Duration(seconds: 1), () {
        _isInitialized = true;
        notifyListeners();
        _startPeriodicUpdates();
      });
    }
  }

  void _onNotesChanged() {
    _notes = dataService.notesNotifier.value;
    _updateFilteredNotes();
  }

  void _updateFilteredNotes() {
    _filteredNotes = _notes.where((n) => !n.isReply || n.isRepost).toList();
    if (_isInitialized) {
      notifyListeners();
    }
    _loadUserProfiles();
  }

  void _startPeriodicUpdates() {
    _periodicTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      notifyListeners();
    });
  }

  Future<void> fetchInitialNotes() async {
    if (_isLoading) return;

    _setLoading(true);
    _clearError();

    try {
      await dataService.initializeLightweight();
      await dataService.initializeHeavyOperations();
      await dataService.initializeConnections();
    } catch (e) {
      _setError('Failed to load notes: $e');
      debugPrint('[NotesListProvider] Initial fetch error: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> fetchMoreNotes() async {
    if (_isLoadingMore || _isLoading) return;

    _setLoadingMore(true);

    try {
      await dataService.loadMoreNotes();
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
    dataService.initializeConnections();
  }

  void _loadUserProfiles() {
    if (_filteredNotes.isEmpty) return;

    // Only load profiles for first batch of notes to avoid loading too many at once
    final firstBatchNotes = _filteredNotes.take(20).toList(); // Load profiles for first 20 notes only

    final userNpubs = <String>{};
    for (final note in firstBatchNotes) {
      userNpubs.add(note.author);
      if (note.repostedBy != null) {
        userNpubs.add(note.repostedBy!);
      }
    }

    if (userNpubs.isNotEmpty) {
      UserProvider.instance.loadUsers(userNpubs.toList()).catchError((e) {
        debugPrint('[NotesListProvider] User profiles error: $e');
      });
      debugPrint('[NotesListProvider] Initial profile load for ${userNpubs.length} users from ${firstBatchNotes.length} notes');
    }
  }

  Future<void> fetchInteractionsForNotes(List<String> noteIds) async {
    if (noteIds.isEmpty) return;

    try {
      // Use both the optimized DataService method and batch processing for maximum efficiency
      final futures = <Future>[];

      // Use DataService for cached interaction checking and fetching
      futures.add(dataService.fetchInteractionsForEvents(noteIds));

      // Use BatchProcessingService for prioritized visible notes processing
      final batchProcessor = BatchProcessingService(networkService: NetworkService.instance);
      futures.add(batchProcessor.processVisibleNotesInteractions(noteIds));

      await Future.wait(futures, eagerError: false);

      debugPrint('[NotesListProvider] Fetched interactions for ${noteIds.length} visible notes using optimized batch processing');
    } catch (e) {
      debugPrint('[NotesListProvider] Error fetching interactions for visible notes: $e');
    }
  }

  Future<void> fetchProfilesForVisibleNotes(List<String> visibleNoteIds) async {
    if (visibleNoteIds.isEmpty) return;

    try {
      // Get the notes that correspond to visible note IDs
      final visibleNotes = _filteredNotes.where((note) => visibleNoteIds.contains(note.id)).toList();

      if (visibleNotes.isEmpty) return;

      // Extract unique author NPUBs from visible notes only
      final authorNpubs = <String>{};
      for (final note in visibleNotes) {
        authorNpubs.add(note.author);
        if (note.repostedBy != null) {
          authorNpubs.add(note.repostedBy!);
        }
      }

      if (authorNpubs.isNotEmpty) {
        // Load profiles only for authors of visible notes
        await UserProvider.instance.loadUsers(authorNpubs.toList());
        debugPrint('[NotesListProvider] Loaded profiles for ${authorNpubs.length} authors of ${visibleNotes.length} visible notes');
      }
    } catch (e) {
      debugPrint('[NotesListProvider] Error fetching profiles for visible notes: $e');
    }
  }

  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void _setLoadingMore(bool loading) {
    if (_isLoadingMore != loading) {
      _isLoadingMore = loading;
      notifyListeners();
    }
  }

  void _setError(String message) {
    _hasError = true;
    _errorMessage = message;
    notifyListeners();
  }

  void _clearError() {
    if (_hasError) {
      _hasError = false;
      _errorMessage = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    dataService.notesNotifier.removeListener(_onNotesChanged);
    DataServiceManager.instance.releaseService(npub: npub, dataType: dataType);
    super.dispose();
  }
}
