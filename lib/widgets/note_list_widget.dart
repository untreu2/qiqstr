import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/notes_list_provider.dart';
import '../providers/media_provider.dart';
import '../services/data_service.dart';
import 'note_widget.dart';
import 'grid_view_widget.dart';

enum NoteViewMode { text, grid }

class NoteListWidget extends StatefulWidget {
  final NoteViewMode viewMode;

  const NoteListWidget({
    super.key,
    this.viewMode = NoteViewMode.text,
  });

  @override
  State<NoteListWidget> createState() => _NoteListWidgetState();
}

class _NoteListWidgetState extends State<NoteListWidget> with AutomaticKeepAliveClientMixin<NoteListWidget> {
  late final ScrollController _scrollController;
  static final Map<String, double> _globalScrollPositions = {};

  Timer? _loadMoreTimer;
  Timer? _scrollSaveTimer;
  static const double _loadMoreThreshold = 200.0;
  static const int _criticalNotesCount = 3;
  static const Duration _scrollSaveDelay = Duration(milliseconds: 300);
  static const Duration _loadMoreDelay = Duration(milliseconds: 100);

  bool _isScrollJumping = false;
  double? _lastScrollPosition;
  final GlobalKey _listKey = GlobalKey();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeScrollController();
    _setupScrollListener();

    // Optimize post-frame callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final provider = context.read<NotesListProvider>();
      provider.fetchInitialNotes();

      // Delay media preloading to avoid blocking UI
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _preloadCriticalMedia();
      });
    });
  }

  void _initializeScrollController() {
    final provider = context.read<NotesListProvider>();
    final scrollKey = '${provider.npub}_${provider.dataType.name}';
    final savedPosition = _globalScrollPositions[scrollKey] ?? 0.0;

    _scrollController = ScrollController(
      keepScrollOffset: true,
      initialScrollOffset: savedPosition,
    );

    // Prevent initial jump by waiting for widget to be fully built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && savedPosition > 0) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && _scrollController.hasClients) {
            _scrollController.jumpTo(savedPosition);
          }
        });
      }
    });
  }

  void _setupScrollListener() {
    _scrollController.addListener(_onScroll);
  }

  // Improved scroll handler with jump prevention
  void _onScroll() {
    if (!_scrollController.hasClients || _isScrollJumping) return;

    final currentPosition = _scrollController.position.pixels;
    final maxScrollExtent = _scrollController.position.maxScrollExtent;

    // Detect sudden jumps and prevent them
    if (_lastScrollPosition != null) {
      final jumpThreshold = MediaQuery.of(context).size.height * 0.5;
      final positionDiff = (currentPosition - _lastScrollPosition!).abs();

      if (positionDiff > jumpThreshold) {
        _isScrollJumping = true;
        // Restore to last known good position
        _scrollController.jumpTo(_lastScrollPosition!);
        Future.delayed(const Duration(milliseconds: 100), () {
          _isScrollJumping = false;
        });
        return;
      }
    }

    _lastScrollPosition = currentPosition;

    // Save scroll position with debouncing
    _scrollSaveTimer?.cancel();
    _scrollSaveTimer = Timer(_scrollSaveDelay, () {
      if (mounted && !_isScrollJumping) {
        final provider = context.read<NotesListProvider>();
        final scrollKey = '${provider.npub}_${provider.dataType.name}';
        _globalScrollPositions[scrollKey] = currentPosition;
      }
    });

    // Load more with debouncing
    if (maxScrollExtent > 0 && (maxScrollExtent - currentPosition) < _loadMoreThreshold) {
      _loadMoreTimer?.cancel();
      _loadMoreTimer = Timer(_loadMoreDelay, () {
        if (mounted && !_isScrollJumping) {
          final provider = context.read<NotesListProvider>();
          if (!provider.isLoadingMore && !provider.isLoading) {
            provider.fetchMoreNotes();
          }
        }
      });
    }
  }

  void _preloadCriticalMedia() {
    if (!mounted) return;

    final provider = context.read<NotesListProvider>();
    if (provider.notes.isNotEmpty) {
      final criticalNotes = provider.notes.take(_criticalNotesCount).toList();
      // Use compute or isolate for heavy operations if needed
      MediaProvider.instance.cacheImagesFromVisibleNotes(criticalNotes);
    }
  }

  @override
  void dispose() {
    _loadMoreTimer?.cancel();
    _scrollSaveTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Selector<NotesListProvider, NoteListState>(
      selector: (context, provider) => NoteListState(
        notes: provider.notes,
        isLoading: provider.isLoading,
        isLoadingMore: provider.isLoadingMore,
        hasError: provider.hasError,
        errorMessage: provider.errorMessage,
      ),
      shouldRebuild: (previous, next) {
        // Only rebuild if there are actual changes
        if (previous.isLoading != next.isLoading ||
            previous.isLoadingMore != next.isLoadingMore ||
            previous.hasError != next.hasError ||
            previous.errorMessage != next.errorMessage) {
          return true;
        }

        // For notes list, check if content actually changed
        if (previous.notes.length != next.notes.length) {
          return true;
        }

        // Check if first few items changed (most likely to affect visible area)
        const checkCount = 5;
        final prevCheck = previous.notes.take(checkCount);
        final nextCheck = next.notes.take(checkCount);

        for (int i = 0; i < prevCheck.length && i < nextCheck.length; i++) {
          if (prevCheck.elementAt(i).id != nextCheck.elementAt(i).id) {
            return true;
          }
        }

        return false;
      },
      builder: (context, state, child) {
        if (state.hasError) {
          return _buildErrorState(state.errorMessage ?? 'Unknown error');
        }

        if (state.notes.isNotEmpty) {
          return widget.viewMode == NoteViewMode.grid ? const GridViewWidget() : _buildListView(state);
        }

        if (state.isLoading) {
          return _buildLoadingState();
        }

        return _buildEmptyState();
      },
    );
  }

  Widget _buildListView(NoteListState state) {
    final provider = context.read<NotesListProvider>();

    return SliverList(
      key: _listKey,
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (state.isLoadingMore && index == state.notes.length) {
            return _buildLoadMoreIndicator();
          }

          if (index >= state.notes.length) {
            return const SizedBox.shrink();
          }

          final note = state.notes[index];

          return Column(
            key: ValueKey('${note.id}_$index'), // More stable key
            mainAxisSize: MainAxisSize.min,
            children: [
              // Wrap in RepaintBoundary to prevent unnecessary repaints
              RepaintBoundary(
                child: NoteWidget(
                  note: note,
                  dataService: provider.dataService,
                  currentUserNpub: provider.currentUserNpub,
                  notesNotifier: provider.dataService.notesNotifier,
                  profiles: const {},
                  isSmallView: true,
                ),
              ),
              if (index < state.notes.length - 1) _buildNoteSeparator(),
            ],
          );
        },
        childCount: state.notes.length + (state.isLoadingMore ? 1 : 0),
        addAutomaticKeepAlives: true, // Changed back to true for scroll stability
        addRepaintBoundaries: true,
        addSemanticIndexes: false, // Reduce overhead
      ),
    );
  }

  Widget _buildLoadMoreIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return SliverToBoxAdapter(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildNoteSeparator() {
    return Container(
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: Container(
          height: 0.5,
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor.withOpacity(0.3),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);

    return SliverToBoxAdapter(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.article_outlined,
                size: 64,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
              const SizedBox(height: 16),
              Text(
                'No notes available',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try refreshing or check back later',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    final theme = Theme.of(context);

    return SliverToBoxAdapter(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading notes',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                error,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
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
}

// State class for better performance with Selector
class NoteListState {
  final List<dynamic> notes;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasError;
  final String? errorMessage;

  const NoteListState({
    required this.notes,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasError,
    this.errorMessage,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteListState &&
          runtimeType == other.runtimeType &&
          notes.length == other.notes.length &&
          isLoading == other.isLoading &&
          isLoadingMore == other.isLoadingMore &&
          hasError == other.hasError &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => notes.length.hashCode ^ isLoading.hashCode ^ isLoadingMore.hashCode ^ hasError.hashCode ^ errorMessage.hashCode;
}

class NoteListWidgetFactory {
  static Widget create({
    required String npub,
    required DataType dataType,
    DataService? sharedDataService,
    String? scrollRestorationId,
    NoteViewMode viewMode = NoteViewMode.text,
  }) {
    return ChangeNotifierProvider(
      create: (context) => NotesListProvider(
        npub: npub,
        dataType: dataType,
        sharedDataService: sharedDataService,
      ),
      child: NoteListWidget(viewMode: viewMode),
    );
  }
}
