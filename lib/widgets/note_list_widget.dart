import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math' as math;
import '../providers/notes_list_provider.dart';
import '../providers/interactions_provider.dart';
import '../services/data_service.dart';
import '../services/cache_service.dart';
import '../theme/theme_manager.dart';
import 'note_widget.dart';

class NoteListWidget extends StatefulWidget {
  const NoteListWidget({super.key});

  @override
  State<NoteListWidget> createState() => _NoteListWidgetState();
}

class _NoteListWidgetState extends State<NoteListWidget> {
  late final ScrollController _scrollController;
  double _savedScrollPosition = 0.0;
  bool _isUserScrolling = false;

  final Set<String> _visibleNoteIds = {};
  Timer? _interactionFetchTimer;
  Duration _interactionFetchDelay = const Duration(milliseconds: 150);

  Set<String>? _cachedVisibleNoteIds;
  double _lastCalculatedScrollPosition = -1;
  int _lastNotesLength = 0;

  double _lastScrollPosition = 0;
  int _lastScrollTime = 0; // Use milliseconds since epoch for better performance
  static const double _scrollThreshold = 10.0;
  int _scrollDebounceInterval = 16; // milliseconds

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(keepScrollOffset: true);
    _setupScrollListener();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<NotesListProvider>();

      if (provider.dataType == DataType.profile) {
        _interactionFetchDelay = const Duration(milliseconds: 80);
        _scrollDebounceInterval = 12; // milliseconds
      }

      provider.fetchInitialNotes();
    });
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      final currentPosition = _scrollController.position.pixels;
      final nowMillis = DateTime.now().millisecondsSinceEpoch;

      // Simplified throttling using milliseconds
      final shouldThrottle =
          (currentPosition - _lastScrollPosition).abs() < _scrollThreshold && (nowMillis - _lastScrollTime) < _scrollDebounceInterval;

      if (!shouldThrottle) {
        _lastScrollPosition = currentPosition;
        _lastScrollTime = nowMillis;

        if (_scrollController.position.isScrollingNotifier.value) {
          _isUserScrolling = true;
          _savedScrollPosition = currentPosition;
        }

        final provider = context.read<NotesListProvider>();

        // Check for load more with optimized threshold
        final threshold = provider.dataType == DataType.profile ? 0.85 : 0.9;
        if (currentPosition >= _scrollController.position.maxScrollExtent * threshold) {
          if (!provider.isLoadingMore) {
            provider.fetchMoreNotes();
          }
        }

        _scheduleInteractionFetch();
      }
    });
  }

  void _scheduleInteractionFetch() {
    _interactionFetchTimer?.cancel();
    _interactionFetchTimer = Timer(_interactionFetchDelay, () {
      _fetchInteractionsForVisibleNotes();
    });
  }

  void _fetchInteractionsForVisibleNotes() {
    if (!mounted || !_scrollController.hasClients) return;

    final provider = context.read<NotesListProvider>();
    final visibleNoteIds = _getVisibleNoteIds();

    // Update InteractionsProvider with current visible notes
    InteractionsProvider.instance.updateVisibleNotes(visibleNoteIds);

    final newVisibleNotes = visibleNoteIds.difference(_visibleNoteIds);
    if (newVisibleNotes.isNotEmpty) {
      // Only fetch for truly new visible notes to avoid redundant operations
      provider.fetchInteractionsForNotes(newVisibleNotes.toList());
      provider.fetchProfilesForVisibleNotes(newVisibleNotes.toList());
      _visibleNoteIds.addAll(newVisibleNotes);

      print(
          '[NoteListWidget] Processing ${newVisibleNotes.length} newly visible notes (${visibleNoteIds.length - newVisibleNotes.length} already tracked)');
    }

    // Clean up no longer visible notes from tracking
    final removedNotes = _visibleNoteIds.difference(visibleNoteIds);
    if (removedNotes.isNotEmpty) {
      _visibleNoteIds.retainWhere((id) => visibleNoteIds.contains(id));
      print('[NoteListWidget] Stopped tracking ${removedNotes.length} notes that are no longer visible');
    }

    // Optimize cache for current visible notes
    if (visibleNoteIds.isNotEmpty) {
      Future.microtask(() {
        try {
          // Tell cache service to optimize for these visible notes
          CacheService.instance.optimizeForVisibleNotes(visibleNoteIds);
        } catch (e) {
          print('[NoteListWidget] Cache optimization error: $e');
        }
      });
    }
  }

  Set<String> _getVisibleNoteIds() {
    if (!_scrollController.hasClients) return {};

    final provider = context.read<NotesListProvider>();
    final notes = provider.notes;
    if (notes.isEmpty) return {};

    final scrollPosition = _scrollController.position.pixels;
    final cacheThreshold = provider.dataType == DataType.profile ? 20.0 : 50.0;

    // Use cached result if scroll position hasn't changed much
    if (_cachedVisibleNoteIds != null &&
        (scrollPosition - _lastCalculatedScrollPosition).abs() < cacheThreshold &&
        notes.length == _lastNotesLength) {
      return _cachedVisibleNoteIds!;
    }

    final viewportHeight = _scrollController.position.viewportDimension;

    // Optimized buffer calculation
    final bufferMultiplier = provider.dataType == DataType.profile ? 0.4 : 0.3;
    final bufferSize = viewportHeight * bufferMultiplier;
    final visibleStart = math.max(0.0, scrollPosition - bufferSize);
    final visibleEnd = scrollPosition + viewportHeight + bufferSize;

    final visibleNoteIds = <String>{};

    // More accurate item height estimation
    final estimatedItemHeight = provider.dataType == DataType.profile ? viewportHeight / 9 : viewportHeight / 7;
    final startIndex = (visibleStart / estimatedItemHeight).floor().clamp(0, notes.length - 1);
    final endIndex = (visibleEnd / estimatedItemHeight).ceil().clamp(startIndex, notes.length - 1);

    // Limit maximum visible items for performance
    final maxVisibleItems = provider.dataType == DataType.profile ? 60 : 40;
    final actualEndIndex = math.min(endIndex, startIndex + maxVisibleItems - 1);

    for (int i = startIndex; i <= actualEndIndex && i < notes.length; i++) {
      visibleNoteIds.add(notes[i].id);
    }

    _cachedVisibleNoteIds = visibleNoteIds;
    _lastCalculatedScrollPosition = scrollPosition;
    _lastNotesLength = notes.length;

    return visibleNoteIds;
  }

  void _preserveScrollPosition() {
    if (_scrollController.hasClients && !_isUserScrolling && !_scrollController.position.isScrollingNotifier.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && _savedScrollPosition > 0) {
          final targetPosition = _savedScrollPosition.clamp(0.0, _scrollController.position.maxScrollExtent);

          // Only jump if difference is significant enough to matter
          if ((targetPosition - _scrollController.position.pixels).abs() > 5.0) {
            _scrollController.jumpTo(targetPosition);
          }
        }
      });
    }

    // Shorter delay for better responsiveness
    Timer(const Duration(milliseconds: 30), () {
      _isUserScrolling = false;
    });
  }

  @override
  void dispose() {
    _interactionFetchTimer?.cancel();
    _scrollController.dispose();
    _clearCaches();
    super.dispose();
  }

  void _clearCaches() {
    _cachedVisibleNoteIds = null;
    _visibleNoteIds.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<NotesListProvider, ({List<dynamic> notes, bool isLoadingMore, bool hasError, String? errorMessage})>(
      selector: (_, provider) => (
        notes: provider.notes,
        isLoadingMore: provider.isLoadingMore,
        hasError: provider.hasError,
        errorMessage: provider.errorMessage,
      ),
      builder: (context, data, child) {
        if (data.hasError) {
          return _buildErrorState(data.errorMessage ?? 'Unknown error');
        }

        if (data.notes.isEmpty) {
          return _buildLoadingState();
        }

        return _buildNotesList(data.notes, data.isLoadingMore);
      },
    );
  }

  Widget _buildLoadingState() {
    return const SliverToBoxAdapter(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return SliverToBoxAdapter(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error loading notes', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(error, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.read<NotesListProvider>().fetchInitialNotes(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotesList(List<dynamic> notes, bool isLoadingMore) {
    final noteCount = notes.length;

    // Simplified item count calculation
    int itemCount = (noteCount * 2) - 1; // notes + dividers
    if (isLoadingMore) {
      itemCount++;
    }

    if (!isLoadingMore) {
      _preserveScrollPosition();
    }

    return SliverList.builder(
      key: const PageStorageKey<String>('notes_list'),
      itemCount: itemCount,
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        if (isLoadingMore && index == itemCount - 1) {
          return const _LoadingIndicator();
        }

        if (index.isOdd) {
          return _DividerWidget(key: ValueKey('divider_${index ~/ 2}'));
        }

        final noteIndex = index ~/ 2;
        if (noteIndex >= notes.length) {
          return const SizedBox.shrink();
        }

        final note = notes[noteIndex];

        return _OptimizedNoteItem(
          key: ValueKey('note_${note.id}'),
          note: note,
          noteIndex: noteIndex,
        );
      },
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _DividerWidget extends StatelessWidget {
  const _DividerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 12, thickness: 1, color: context.colors.border);
  }
}

class _OptimizedNoteItem extends StatelessWidget {
  final dynamic note;
  final int noteIndex;

  const _OptimizedNoteItem({
    super.key,
    required this.note,
    required this.noteIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<NotesListProvider, ({DataService dataService, String npub})>(
      selector: (_, provider) => (
        dataService: provider.dataService,
        npub: provider.npub,
      ),
      builder: (context, data, child) {
        return NoteWidget(
          note: note,
          reactionCount: note.reactionCount,
          replyCount: note.replyCount,
          repostCount: note.repostCount,
          dataService: data.dataService,
          currentUserNpub: data.npub,
          notesNotifier: data.dataService.notesNotifier,
          profiles: const {},
          isSmallView: true,
        );
      },
    );
  }
}

class NoteListWidgetFactory {
  static Widget create({
    required String npub,
    required DataType dataType,
    DataService? sharedDataService,
    String? scrollRestorationId,
  }) {
    return ChangeNotifierProvider(
      create: (context) => NotesListProvider(
        npub: npub,
        dataType: dataType,
        sharedDataService: sharedDataService,
      ),
      child: const NoteListWidget(),
    );
  }
}
