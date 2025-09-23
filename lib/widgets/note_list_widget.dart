import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/notes_list_provider.dart';
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
  @override
  bool get wantKeepAlive => true;

  // Immutable cached data
  late final ScrollController _scrollController;
  late final String _scrollKey;
  late final NotesListProvider _provider;

  // Static cache for scroll positions
  static final Map<String, double> _globalScrollPositions = {};

  // Performance constants
  static const double _loadMoreThreshold = 200.0;
  static const Duration _scrollSaveDelay = Duration(milliseconds: 0);
  static const Duration _loadMoreDelay = Duration(milliseconds: 100);

  // Minimal state tracking
  Timer? _loadMoreTimer;
  Timer? _scrollSaveTimer;
  bool _isScrollJumping = false;
  double? _lastScrollPosition;
  bool _isInitialized = false;

  // Single consolidated state
  final ValueNotifier<_ListState> _stateNotifier = ValueNotifier(_ListState.initial());

  @override
  void initState() {
    super.initState();
    _precomputeData();
    _initializeController();
    _setupProviderListener();
    _scheduleAsyncInitialization();
  }

  void _precomputeData() {
    _provider = context.read<NotesListProvider>();
    _scrollKey = '${_provider.npub}_${_provider.dataType.name}';
    _isInitialized = true;
  }

  void _initializeController() {
    final savedPosition = _globalScrollPositions[_scrollKey] ?? 0.0;

    _scrollController = ScrollController(
      keepScrollOffset: true,
      initialScrollOffset: savedPosition,
    );

    _scrollController.addListener(_onScroll);
  }

  void _setupProviderListener() {
    _provider.addListener(_onProviderChange);
    _syncProviderState();
  }

  void _onProviderChange() {
    if (!mounted) return;
    _syncProviderState();
  }

  void _syncProviderState() {
    final currentState = _stateNotifier.value;

    final newState = _ListState(
      notes: List.unmodifiable(_provider.notes),
      isLoading: _provider.isLoading,
      isLoadingMore: _provider.isLoadingMore,
      hasError: _provider.hasError,
      errorMessage: _provider.errorMessage,
    );

    // Only update if something actually changed
    if (currentState != newState) {
      _stateNotifier.value = newState;
    }
  }

  void _scheduleAsyncInitialization() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _provider.fetchInitialNotes();
      _restoreScrollPosition();
    });
  }

  void _restoreScrollPosition() {
    final savedPosition = _globalScrollPositions[_scrollKey] ?? 0.0;

    if (savedPosition > 0) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(savedPosition);
        }
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isScrollJumping) return;

    final currentPosition = _scrollController.position.pixels;
    final maxScrollExtent = _scrollController.position.maxScrollExtent;

    // Anti-jump protection
    if (_lastScrollPosition != null) {
      final jumpThreshold = MediaQuery.of(context).size.height * 0.5;
      final positionDiff = (currentPosition - _lastScrollPosition!).abs();

      if (positionDiff > jumpThreshold) {
        _isScrollJumping = true;
        _scrollController.jumpTo(_lastScrollPosition!);
        Future.delayed(const Duration(milliseconds: 100), () {
          _isScrollJumping = false;
        });
        return;
      }
    }

    _lastScrollPosition = currentPosition;

    // Debounced scroll position saving
    _scrollSaveTimer?.cancel();
    _scrollSaveTimer = Timer(_scrollSaveDelay, () {
      if (mounted && !_isScrollJumping) {
        _globalScrollPositions[_scrollKey] = currentPosition;
      }
    });

    // Debounced load more
    if (maxScrollExtent > 0 && (maxScrollExtent - currentPosition) < _loadMoreThreshold) {
      _loadMoreTimer?.cancel();
      _loadMoreTimer = Timer(_loadMoreDelay, () {
        if (mounted && !_isScrollJumping) {
          final state = _stateNotifier.value;
          if (!state.isLoading && !state.isLoadingMore) {
            _provider.fetchMoreNotes();
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _loadMoreTimer?.cancel();
    _scrollSaveTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _provider.removeListener(_onProviderChange);
    _stateNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!_isInitialized) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return ValueListenableBuilder<_ListState>(
      valueListenable: _stateNotifier,
      builder: (context, state, _) {
        if (state.hasError) {
          return _ErrorState(
            errorMessage: state.errorMessage ?? 'Unknown error',
            onRetry: () => _provider.fetchInitialNotes(),
          );
        }

        if (state.notes.isNotEmpty) {
          return widget.viewMode == NoteViewMode.grid
              ? const GridViewWidget()
              : _OptimizedListView(
                  state: state,
                  scrollController: _scrollController,
                  provider: _provider,
                );
        }

        if (state.isLoading) {
          return const _LoadingState();
        }

        return const _EmptyState();
      },
    );
  }
}

// Immutable state class
class _ListState {
  final List<dynamic> notes;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasError;
  final String? errorMessage;

  const _ListState({
    required this.notes,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasError,
    this.errorMessage,
  });

  factory _ListState.initial() {
    return const _ListState(
      notes: [],
      isLoading: false,
      isLoadingMore: false,
      hasError: false,
      errorMessage: null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ListState &&
          runtimeType == other.runtimeType &&
          notes.length == other.notes.length &&
          isLoading == other.isLoading &&
          isLoadingMore == other.isLoadingMore &&
          hasError == other.hasError &&
          errorMessage == other.errorMessage &&
          _areNotesEqual(notes, other.notes);

  bool _areNotesEqual(List<dynamic> current, List<dynamic> other) {
    if (current.length != other.length) return false;

    // Quick check - compare first 10 items for visible changes
    const checkCount = 10;
    final actualCheckCount = current.length < checkCount ? current.length : checkCount;

    for (int i = 0; i < actualCheckCount; i++) {
      if (current[i].id != other[i].id) return false;
    }

    return true;
  }

  @override
  int get hashCode => notes.length.hashCode ^ isLoading.hashCode ^ isLoadingMore.hashCode ^ hasError.hashCode ^ errorMessage.hashCode;
}

// Optimized list view - single ValueListenableBuilder, no nested listeners
class _OptimizedListView extends StatelessWidget {
  final _ListState state;
  final ScrollController scrollController;
  final NotesListProvider provider;

  const _OptimizedListView({
    required this.state,
    required this.scrollController,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          // Handle load more indicator
          if (index == state.notes.length) {
            return state.isLoadingMore ? const _LoadMoreIndicator() : const SizedBox.shrink();
          }

          // Handle out of bounds
          if (index >= state.notes.length) {
            return const SizedBox.shrink();
          }

          final note = state.notes[index];

          return RepaintBoundary(
            key: ValueKey('note_${note.id}'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NoteWidget(
                  note: note,
                  dataService: provider.dataService,
                  currentUserNpub: provider.currentUserNpub,
                  notesNotifier: provider.dataService.notesNotifier,
                  profiles: const {},
                  isSmallView: true,
                  notesListProvider: provider,
                ),
                if (index < state.notes.length - 1) const _NoteSeparator(),
              ],
            ),
          );
        },
        childCount: state.notes.length + (state.isLoadingMore ? 1 : 0),
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: false, // We handle this manually
        addSemanticIndexes: false,
      ),
    );
  }
}

// Immutable components
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
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
}

class _LoadMoreIndicator extends StatelessWidget {
  const _LoadMoreIndicator();

  @override
  Widget build(BuildContext context) {
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
}

class _NoteSeparator extends StatelessWidget {
  const _NoteSeparator();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
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
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
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
}

class _ErrorState extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
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
                errorMessage,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Factory remains the same
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
