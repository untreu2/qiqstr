import 'package:flutter/foundation.dart';
import '../models/note_model.dart';
import '../services/data_service.dart';
import '../services/data_service_manager.dart';
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
  }

  void _onNotesChanged() {
    _notes = dataService.notesNotifier.value;
    _updateFilteredNotes();
  }

  void _updateFilteredNotes() {
    _filteredNotes = _notes.where((n) => !n.isReply || n.isRepost).toList();
    notifyListeners();
    _loadUserProfiles();
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

    final userNpubs = <String>{};
    for (final note in _filteredNotes) {
      userNpubs.add(note.author);
      if (note.repostedBy != null) {
        userNpubs.add(note.repostedBy!);
      }
    }

    if (userNpubs.isNotEmpty) {
      UserProvider.instance.loadUsers(userNpubs.toList()).catchError((e) {
        debugPrint('[NotesListProvider] User profiles error: $e');
      });
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
    dataService.notesNotifier.removeListener(_onNotesChanged);
    DataServiceManager.instance.releaseService(npub: npub, dataType: dataType);
    super.dispose();
  }
}
