import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../models/note_model.dart';
import '../services/data_service.dart';
import '../services/data_service_manager.dart';
import '../providers/user_provider.dart';
import '../providers/interactions_provider.dart';
import '../providers/notes_provider.dart';

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
    // Use shared service or get from manager
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

  // Getters
  List<NoteModel> get notes => _filteredNotes;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => _filteredNotes.isEmpty && !_isLoading;

  void _initialize() {
    // Single source of truth: listen only to DataService
    dataService.notesNotifier.addListener(_onNotesChanged);
    _onNotesChanged(); // Initial load of existing data
  }

  void _onNotesChanged() {
    _notes = dataService.notesNotifier.value;
    _updateFilteredNotes();
  }

  void _updateFilteredNotes() {
    // Filter out replies unless they are reposts
    final filtered = _notes.where((n) => !n.isReply || n.isRepost).toList();

    _filteredNotes = filtered;
    notifyListeners();

    // Schedule progressive loading in a non-blocking way
    _scheduleProgressiveLoading(filtered);
  }

  Future<void> fetchInitialNotes() async {
    if (_isLoading) return;

    _setLoading(true);
    _clearError();

    try {
      // Initialize DataService - these methods are idempotent so safe to call multiple times
      await dataService.initializeLightweight();

      // Schedule heavy operations for later using SchedulerBinding instead of Future.delayed
      SchedulerBinding.instance.scheduleTask(() async {
        try {
          await dataService.initializeHeavyOperations();
          await dataService.initializeConnections();
        } catch (e) {
          debugPrint('[NotesListProvider] Heavy initialization error: $e');
        }
      }, Priority.idle);
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
      // Don't show error for "load more" failures
    } finally {
      _setLoadingMore(false);
    }
  }

  void refresh() {
    _notes.clear();
    _filteredNotes.clear();
    notifyListeners();

    // Trigger fresh data load
    SchedulerBinding.instance.scheduleTask(() {
      dataService.initializeConnections();
    }, Priority.animation);
  }

  void _scheduleProgressiveLoading(List<NoteModel> notes) {
    if (notes.isEmpty) return;

    // Use SchedulerBinding instead of Future.delayed for better performance
    SchedulerBinding.instance.scheduleTask(() async {
      await _loadCriticalUserProfiles(notes);
    }, Priority.animation);

    SchedulerBinding.instance.scheduleTask(() async {
      await _loadRemainingUserProfiles(notes);
    }, Priority.idle);

    SchedulerBinding.instance.scheduleTask(() async {
      await _loadInteractionsProgressive(notes);
    }, Priority.idle);
  }

  Future<void> _loadCriticalUserProfiles(List<NoteModel> notes) async {
    // Load profiles for first 5 notes immediately
    final criticalUserNpubs = <String>{};
    for (final note in notes.take(5)) {
      criticalUserNpubs.add(note.author);
      if (note.repostedBy != null) {
        criticalUserNpubs.add(note.repostedBy!);
      }
    }

    if (criticalUserNpubs.isNotEmpty) {
      try {
        await UserProvider.instance.loadUsers(criticalUserNpubs.toList());
      } catch (e) {
        debugPrint('[NotesListProvider] Critical user profiles error: $e');
      }
    }
  }

  Future<void> _loadRemainingUserProfiles(List<NoteModel> notes) async {
    const batchSize = 10;
    final remainingNotes = notes.skip(5).toList();

    for (int i = 0; i < remainingNotes.length; i += batchSize) {
      // Yield control to UI thread between batches using SchedulerBinding
      await SchedulerBinding.instance.endOfFrame;

      final batch = remainingNotes.skip(i).take(batchSize);
      final userNpubs = <String>{};

      for (final note in batch) {
        userNpubs.add(note.author);
        if (note.repostedBy != null) {
          userNpubs.add(note.repostedBy!);
        }
      }

      if (userNpubs.isNotEmpty) {
        try {
          await UserProvider.instance.loadUsers(userNpubs.toList());
        } catch (e) {
          debugPrint('[NotesListProvider] Batch user profiles error: $e');
        }
      }
    }
  }

  Future<void> _loadInteractionsProgressive(List<NoteModel> notes) async {
    const batchSize = 5;
    final interactionsProvider = InteractionsProvider.instance;
    final notesProvider = NotesProvider.instance;

    for (int i = 0; i < notes.length; i += batchSize) {
      // Yield control to UI thread between batches using SchedulerBinding
      await SchedulerBinding.instance.endOfFrame;

      final batch = notes.skip(i).take(batchSize);

      for (final note in batch) {
        // Schedule each note's interactions loading using SchedulerBinding instead of Future.microtask
        SchedulerBinding.instance.scheduleTask(() {
          try {
            final reactions = interactionsProvider.getReactionsForNote(note.id);
            final replies = interactionsProvider.getRepliesForNote(note.id);
            final reposts = interactionsProvider.getRepostsForNote(note.id);
            final zaps = interactionsProvider.getZapsForNote(note.id);

            // Update counts if available
            if (reactions.isNotEmpty || replies.isNotEmpty || reposts.isNotEmpty || zaps.isNotEmpty) {
              notesProvider.updateNoteInteractionCounts(
                note.id,
                reactionCount: reactions.length,
                replyCount: replies.length,
                repostCount: reposts.length,
                zapAmount: zaps.fold<int>(0, (sum, zap) => sum + zap.amount),
              );
            }
          } catch (e) {
            debugPrint('[NotesListProvider] Interaction loading error for ${note.id}: $e');
          }
        }, Priority.idle);
      }
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

    // Release the DataService reference
    SchedulerBinding.instance.scheduleTask(() async {
      await DataServiceManager.instance.releaseService(
        npub: npub,
        dataType: dataType,
      );
    }, Priority.idle);

    super.dispose();
  }
}
