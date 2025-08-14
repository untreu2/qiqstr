import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../theme/theme_manager.dart';
import '../models/note_model.dart';
import '../services/data_service.dart';
import '../services/initialization_service.dart';
import '../providers/user_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/interactions_provider.dart';
import 'note_widget.dart';

class NoteListWidget extends StatefulWidget {
  final String npub;
  final DataType dataType;
  final DataService? sharedDataService;

  const NoteListWidget({
    super.key,
    required this.npub,
    required this.dataType,
    this.sharedDataService,
  });

  @override
  State<NoteListWidget> createState() => _NoteListWidgetState();
}

class _NoteListWidgetState extends State<NoteListWidget> {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  final ScrollController _scrollController = ScrollController();
  late DataService _dataService;

  String? _currentUserNpub;
  bool _isLoadingMore = false;

  List<NoteModel> _filteredNotes = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAsync();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _dataService.notesNotifier.removeListener(_onNotesChanged);
    NotesProvider.instance.removeListener(_onProviderNotesChanged);

    // Only close connections if we created our own DataService
    if (widget.sharedDataService == null) {
      _dataService.closeConnections();
    }
    super.dispose();
  }

  void _onNotesChanged() {
    if (mounted) {
      _updateFilteredNotes(_dataService.notesNotifier.value);
    }
  }

  void _onProviderNotesChanged() {
    if (mounted) {
      // Sync notes from provider to DataService if needed
      final providerNotes = NotesProvider.instance.getFeedNotes();
      _updateFilteredNotes(providerNotes);
    }
  }

  Future<void> _initializeAsync() async {
    try {
      _currentUserNpub = await _secureStorage.read(key: 'npub');
      if (!mounted) return;

      // Use optimized initialization service for faster startup
      await InitializationService.instance.initializeApp(_currentUserNpub ?? '');

      // Initialize InteractionsProvider for this specific dataType
      await _initializeInteractionsProvider();

      await _setupDataService();
      _dataService.notesNotifier.addListener(_onNotesChanged);

      // Listen to NotesProvider changes as well
      NotesProvider.instance.addListener(_onProviderNotesChanged);

      _updateFilteredNotes(_dataService.notesNotifier.value);

      // UI is shown immediately without loading state
    } catch (e) {
      debugPrint('[NoteListWidget] Initialization error: $e');
      // No loading state to update
    }
  }

  Future<void> _initializeInteractionsProvider() async {
    try {
      // Initialize InteractionsProvider with correct dataType
      final dataTypeString = widget.dataType.toString().split('.').last;
      await InteractionsProvider.instance.initialize(_currentUserNpub ?? '', dataType: dataTypeString);
    } catch (e) {
      debugPrint('[NoteListWidget] InteractionsProvider initialization error: $e');
    }
  }

  Future<void> _setupDataService() async {
    if (widget.sharedDataService != null) {
      _dataService = widget.sharedDataService!;

      // Check if shared DataService matches our requirements
      if (_dataService.npub != widget.npub || _dataService.dataType != widget.dataType) {
        _dataService = _createDataService();
        await _initializeDataService();
      } else {
        // Trigger initial load if needed for shared DataService
        _scheduleConnectionInitialization(50);
      }
    } else {
      _dataService = _createDataService();
      await _initializeDataService();
    }
  }

  Future<void> _initializeDataService() async {
    await _dataService.initializeLightweight();
    _scheduleHeavyOperations();
  }

  void _scheduleHeavyOperations() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _dataService.initializeHeavyOperations().then((_) {
          if (mounted) {
            _dataService.initializeConnections();
          }
        }).catchError((e) {
          debugPrint('[NoteListWidget] Heavy initialization error: $e');
        });
      }
    });
  }

  void _scheduleConnectionInitialization(int delayMs) {
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted && _dataService.notesNotifier.value.isEmpty) {
        _dataService.initializeConnections();
      }
    });
  }

  DataService _createDataService() {
    return DataService(
      npub: widget.npub,
      dataType: widget.dataType,
      onNewNote: (_) {},
      onReactionsUpdated: (_, __) {},
      onRepliesUpdated: (_, __) {},
      onRepostsUpdated: (_, __) {},
      onReactionCountUpdated: (_, __) {},
      onReplyCountUpdated: (_, __) {},
      onRepostCountUpdated: (_, __) {},
    );
  }

  void _onScroll() {
    if (!_isLoadingMore && _scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.9) {
      _loadMoreItemsFromNetwork();
    }
  }

  void _loadMoreItemsFromNetwork() {
    if (_isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    _dataService.loadMoreNotes().whenComplete(() {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    });
  }

  void _updateFilteredNotes(List<NoteModel> notes) {
    final filtered = notes.where((n) => !n.isReply || n.isRepost).toList();

    if (mounted) {
      setState(() {
        _filteredNotes = filtered;
      });
    }

    // Progressive loading in background - non-blocking
    _scheduleProgressiveLoading(filtered);
  }

  /// Progressive loading strategy to prevent UI blocking
  void _scheduleProgressiveLoading(List<NoteModel> notes) {
    Future.microtask(() async {
      // Phase 1: Load critical user profiles for first 5 notes only
      final criticalUserNpubs = <String>{};
      for (final note in notes.take(5)) {
        criticalUserNpubs.add(note.author);
        if (note.repostedBy != null) {
          criticalUserNpubs.add(note.repostedBy!);
        }
      }

      if (criticalUserNpubs.isNotEmpty) {
        UserProvider.instance.loadUsers(criticalUserNpubs.toList());
      }

      // Small delay before loading more
      await Future.delayed(const Duration(milliseconds: 50));

      // Phase 2: Load remaining user profiles in batches
      _loadRemainingUsersInBatches(notes);

      // Phase 3: Load interactions progressively
      _loadInteractionsProgressively(notes);
    });
  }

  void _loadRemainingUsersInBatches(List<NoteModel> notes) {
    Future.microtask(() async {
      const batchSize = 10;
      final remainingNotes = notes.skip(5).toList();

      for (int i = 0; i < remainingNotes.length; i += batchSize) {
        final batch = remainingNotes.skip(i).take(batchSize);
        final userNpubs = <String>{};

        for (final note in batch) {
          userNpubs.add(note.author);
          if (note.repostedBy != null) {
            userNpubs.add(note.repostedBy!);
          }
        }

        if (userNpubs.isNotEmpty) {
          UserProvider.instance.loadUsers(userNpubs.toList());
        }

        // Small delay between batches
        await Future.delayed(const Duration(milliseconds: 25));
      }
    });
  }

  void _loadInteractionsProgressively(List<NoteModel> notes) {
    Future.microtask(() async {
      const batchSize = 5;
      final interactionsProvider = InteractionsProvider.instance;
      final notesProvider = NotesProvider.instance;

      for (int i = 0; i < notes.length; i += batchSize) {
        final batch = notes.skip(i).take(batchSize);

        for (final note in batch) {
          // Load interactions without blocking
          Future.microtask(() {
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
          });
        }

        // Delay between interaction batches
        await Future.delayed(const Duration(milliseconds: 100));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_filteredNotes.isEmpty) {
      return _buildEmptyState();
    }

    return _buildNotesList();
  }

  Widget _buildEmptyState() {
    return const SliverToBoxAdapter(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text('No notes found.'),
        ),
      ),
    );
  }

  Widget _buildNotesList() {
    final itemsToShow = _filteredNotes.length;

    return SliverList.separated(
      itemCount: itemsToShow + (_isLoadingMore ? 1 : 0),
      separatorBuilder: (context, index) => Divider(
        height: 12,
        thickness: 1,
        color: context.colors.border,
      ),
      itemBuilder: (context, index) {
        if (index >= itemsToShow) {
          return _buildLoadingIndicator();
        }

        return _buildNoteItem(index);
      },
    );
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildNoteItem(int index) {
    final note = _filteredNotes[index];
    return NoteWidget(
      key: ValueKey(note.id),
      note: note,
      reactionCount: note.reactionCount,
      replyCount: note.replyCount,
      repostCount: note.repostCount,
      dataService: _dataService,
      currentUserNpub: _currentUserNpub!,
      notesNotifier: _dataService.notesNotifier,
      profiles: {}, // Empty since we're using UserProvider now
      isSmallView: true,
    );
  }
}
