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
      final initDelay = dataType == DataType.profile ? const Duration(milliseconds: 100) : const Duration(milliseconds: 500);

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
    final allFiltered = _notes.where((n) => !n.isReply || n.isRepost).toList();

    if (dataType == DataType.profile) {
      _filteredNotes = allFiltered;

      if (_isInitialized) {
        notifyListeners();
      }

      Future.microtask(() => _loadUserProfiles());
    } else {
      _filteredNotes = allFiltered;

      if (_isInitialized) {
        notifyListeners();
      }

      _loadUserProfiles();
    }
  }

  void _startPeriodicUpdates() {
    final updateInterval = dataType == DataType.feed ? const Duration(seconds: 15) : const Duration(seconds: 30);

    _periodicTimer = Timer.periodic(updateInterval, (timer) {
      notifyListeners();

      if (dataType == DataType.feed) {
        _refreshNewNotes();
      }
    });
  }

  void _refreshNewNotes() {
    try {
      dataService.refreshNotes().catchError((e) {
        debugPrint('[NotesListProvider] Refresh error: $e');
      });
    } catch (e) {
      debugPrint('[NotesListProvider] Refresh new notes error: $e');
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

      if (dataType == DataType.profile) {
        Future.microtask(() async {
          try {
            final futures = [
              dataService.initializeHeavyOperations(),
              Future.delayed(const Duration(milliseconds: 25)).then((_) => dataService.initializeConnections()),
            ];

            await Future.wait(futures, eagerError: false);
            _updateFilteredNotesProgressive();
            debugPrint('[NotesListProvider] Profile: Ultra-fast parallel operations completed');
          } catch (e) {
            debugPrint('[NotesListProvider] Profile background error: $e');
          }
        });
      } else {
        Future.microtask(() async {
          try {
            await dataService.initializeHeavyOperations();
            await dataService.initializeConnections();

            Timer(const Duration(milliseconds: 400), () {
              _refreshNewNotes();
            });
            _updateFilteredNotesProgressive();
            debugPrint('[NotesListProvider] Feed: Background operations completed');
          } catch (e) {
            debugPrint('[NotesListProvider] Feed background error: $e');
          }
        });
      }
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
      debugPrint('[NotesListProvider] Refresh error: $e');
    });
  }

  void _loadUserProfiles() {
    if (_filteredNotes.isEmpty) return;

    final batchSize = dataType == DataType.profile ? 12 : 8;
    final firstBatchNotes = _filteredNotes.take(batchSize).toList();

    final userNpubs = <String>{};
    for (final note in firstBatchNotes) {
      userNpubs.add(note.author);
      if (note.repostedBy != null) {
        userNpubs.add(note.repostedBy!);
      }

      if (userNpubs.length >= 10) break;
    }

    if (userNpubs.isNotEmpty) {
      if (dataType == DataType.profile) {
        final userList = userNpubs.take(6).toList();
        UserProvider.instance.loadUsers(userList).catchError((e) {
          debugPrint('[NotesListProvider] Profile user load error: $e');
        });

        if (userNpubs.length > 6) {
          Future.microtask(() {
            final remainingUsers = userNpubs.skip(6).toList();
            UserProvider.instance.loadUsers(remainingUsers).catchError((e) {
              debugPrint('[NotesListProvider] Profile background user load error: $e');
            });
          });
        }
      } else {
        Future.microtask(() {
          UserProvider.instance.loadUsers(userNpubs.toList()).catchError((e) {
            debugPrint('[NotesListProvider] Feed user load error: $e');
          });
        });
      }

      debugPrint(
          '[NotesListProvider] ${dataType == DataType.profile ? 'Profile (MICRO-BATCH)' : 'Feed'}: Profile load for ${userNpubs.length} users from ${firstBatchNotes.length} notes');
    }
  }

  Future<void> fetchInteractionsForNotes(List<String> noteIds) async {
    if (noteIds.isEmpty) return;

    try {
      final futures = <Future>[];

      futures.add(dataService.fetchInteractionsForEvents(noteIds));

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
