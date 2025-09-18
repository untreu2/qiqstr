import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math' as math;
import '../providers/notes_list_provider.dart';
import '../providers/interactions_provider.dart';
import '../providers/media_provider.dart';
import '../services/data_service.dart';
import '../services/cache_service.dart';
import '../theme/theme_manager.dart';
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

class _NoteListWidgetState extends State<NoteListWidget> with AutomaticKeepAliveClientMixin<NoteListWidget>, WidgetsBindingObserver {
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
  int _lastScrollTime = 0;
  static const double _scrollThreshold = 10.0;
  int _scrollDebounceInterval = 16;

  bool _isNavigatedAway = false;
  Timer? _navigationStateTimer;
  final Map<String, dynamic> _persistentMediaCache = {};
  static final Map<String, double> _globalScrollPositions = {};

  bool _wantKeepAlive = true;

  @override
  bool get wantKeepAlive => _wantKeepAlive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _initializeScrollController();
    _setupScrollListener();
    _restoreNavigationState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<NotesListProvider>();

      if (provider.dataType == DataType.profile) {
        _interactionFetchDelay = const Duration(milliseconds: 80);
        _scrollDebounceInterval = 12;
      }

      provider.fetchInitialNotes();
      _preloadCriticalMedia();
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
    _savedScrollPosition = savedPosition;

    debugPrint('[NoteListWidget] Initialized scroll controller with position: $savedPosition');
  }

  void _restoreNavigationState() {
    final provider = context.read<NotesListProvider>();
    final cacheKey = '${provider.npub}_${provider.dataType.name}';

    if (_persistentMediaCache.containsKey(cacheKey)) {
      final cacheData = _persistentMediaCache[cacheKey] as Map<String, dynamic>?;
      if (cacheData != null) {
        _visibleNoteIds.addAll((cacheData['visibleNoteIds'] as List<dynamic>? ?? []).cast<String>());
        debugPrint('[NoteListWidget] Restored ${_visibleNoteIds.length} visible note IDs from cache');
      }
    }
  }

  void _preloadCriticalMedia() {
    final provider = context.read<NotesListProvider>();
    if (provider.notes.isNotEmpty) {
      final criticalNotes = provider.notes.take(5).toList();
      MediaProvider.instance.cacheImagesFromVisibleNotes(criticalNotes);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _handleNavigationAway();
        break;
      case AppLifecycleState.resumed:
        _handleNavigationReturn();
        break;
      case AppLifecycleState.detached:
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _handleNavigationAway() {
    _isNavigatedAway = true;
    _persistScrollPosition();
    _persistMediaState();

    _wantKeepAlive = true;

    debugPrint('[NoteListWidget] Navigation away detected, state preserved');
  }

  void _handleNavigationReturn() {
    if (_isNavigatedAway) {
      _isNavigatedAway = false;

      _restoreScrollPosition();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleInteractionFetch();
      });

      debugPrint('[NoteListWidget] Navigation return detected, state restored');
    }
  }

  void _persistScrollPosition() {
    if (_scrollController.hasClients) {
      final provider = context.read<NotesListProvider>();
      final scrollKey = '${provider.npub}_${provider.dataType.name}';
      final currentPosition = _scrollController.position.pixels;

      _globalScrollPositions[scrollKey] = currentPosition;
      _savedScrollPosition = currentPosition;

      debugPrint('[NoteListWidget] Persisted scroll position: $currentPosition for key: $scrollKey');
    }
  }

  void _persistMediaState() {
    final provider = context.read<NotesListProvider>();
    final cacheKey = '${provider.npub}_${provider.dataType.name}';

    _persistentMediaCache[cacheKey] = {
      'visibleNoteIds': _visibleNoteIds.toList(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  void _restoreScrollPosition() {
    if (_scrollController.hasClients && _savedScrollPosition > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients && mounted && !_isUserScrolling) {
            final targetPosition = _savedScrollPosition.clamp(0.0, _scrollController.position.maxScrollExtent);

            if ((_scrollController.position.pixels - targetPosition).abs() > 5.0) {
              _scrollController.jumpTo(targetPosition);
              debugPrint('[NoteListWidget] Restored scroll position to $targetPosition');
            }
          }
        });
      });
    }
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      final currentPosition = _scrollController.position.pixels;
      final nowMillis = DateTime.now().millisecondsSinceEpoch;

      final shouldThrottle =
          (currentPosition - _lastScrollPosition).abs() < _scrollThreshold && (nowMillis - _lastScrollTime) < _scrollDebounceInterval;

      if (!shouldThrottle) {
        _lastScrollPosition = currentPosition;
        _lastScrollTime = nowMillis;

        if (_scrollController.position.isScrollingNotifier.value) {
          _isUserScrolling = true;
          _savedScrollPosition = currentPosition;

          Timer(const Duration(milliseconds: 200), () {
            if (!_isNavigatedAway && mounted) {
              _persistScrollPosition();
            }
          });
        }

        Timer(const Duration(milliseconds: 500), () {
          if (mounted) {
            _isUserScrolling = false;
          }
        });

        final provider = context.read<NotesListProvider>();

        // Lower threshold to trigger earlier
        final threshold = provider.dataType == DataType.profile ? 0.75 : 0.8;
        final maxScrollExtent = _scrollController.position.maxScrollExtent;

        // Additional check: also trigger if we're within 200 pixels of the bottom
        final isNearBottom = (maxScrollExtent - currentPosition) < 200;

        if ((currentPosition >= maxScrollExtent * threshold || isNearBottom) && maxScrollExtent > 0) {
          if (!provider.isLoadingMore) {
            print(
                '[NoteListWidget] Triggering fetchMoreNotes - currentPosition: $currentPosition, maxScrollExtent: $maxScrollExtent, threshold: $threshold');
            provider.fetchMoreNotes();
          }
        }

        if (!_isNavigatedAway) {
          _scheduleInteractionFetch();
        }
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
    if (!mounted || !_scrollController.hasClients || _isNavigatedAway) return;

    final provider = context.read<NotesListProvider>();
    final visibleNoteIds = _getVisibleNoteIds();

    InteractionsProvider.instance.updateVisibleNotes(visibleNoteIds);

    final newVisibleNotes = visibleNoteIds.difference(_visibleNoteIds);
    if (newVisibleNotes.isNotEmpty) {
      provider.fetchInteractionsForNotes(newVisibleNotes.toList());
      provider.fetchProfilesForVisibleNotes(newVisibleNotes.toList());

      final visibleNotes = provider.notes.where((note) => newVisibleNotes.contains(note.id)).toList();
      if (visibleNotes.isNotEmpty) {
        MediaProvider.instance.cacheImagesFromVisibleNotes(visibleNotes);

        _persistCriticalMediaForNavigation(visibleNotes);
      }

      _visibleNoteIds.addAll(newVisibleNotes);

      print('[NoteListWidget] Processing ${newVisibleNotes.length} newly visible notes (automatic interaction + media loading enabled)');
    }

    final removedNotes = _visibleNoteIds.difference(visibleNoteIds);
    if (removedNotes.isNotEmpty) {
      _visibleNoteIds.retainWhere((id) => visibleNoteIds.contains(id));
      print('[NoteListWidget] Stopped tracking ${removedNotes.length} notes that are no longer visible');
    }

    if (visibleNoteIds.isNotEmpty) {
      Future.microtask(() {
        try {
          CacheService.instance.optimizeForVisibleNotes(visibleNoteIds);
        } catch (e) {
          print('[NoteListWidget] Cache optimization error: $e');
        }
      });
    }
  }

  void _persistCriticalMediaForNavigation(List<dynamic> visibleNotes) {
    final provider = context.read<NotesListProvider>();
    final cacheKey = '${provider.npub}_${provider.dataType.name}_media';

    final mediaUrls = <String>[];
    for (final note in visibleNotes.take(10)) {
      final parsedContent = note.parsedContentLazy;
      final noteMediaUrls = parsedContent['mediaUrls'] as List<String>? ?? [];
      if (noteMediaUrls.isNotEmpty) {
        mediaUrls.addAll(noteMediaUrls.where((url) => url.isNotEmpty));
      }
    }

    if (mediaUrls.isNotEmpty) {
      _persistentMediaCache[cacheKey] = {
        'urls': mediaUrls,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
    }
  }

  Set<String> _getVisibleNoteIds() {
    if (!_scrollController.hasClients) return {};

    final provider = context.read<NotesListProvider>();
    final notes = provider.notes;
    if (notes.isEmpty) return {};

    final scrollPosition = _scrollController.position.pixels;
    final cacheThreshold = provider.dataType == DataType.profile ? 20.0 : 50.0;

    if (_cachedVisibleNoteIds != null &&
        (scrollPosition - _lastCalculatedScrollPosition).abs() < cacheThreshold &&
        notes.length == _lastNotesLength) {
      return _cachedVisibleNoteIds!;
    }

    final viewportHeight = _scrollController.position.viewportDimension;

    final bufferMultiplier = provider.dataType == DataType.profile ? 0.4 : 0.3;
    final bufferSize = viewportHeight * bufferMultiplier;
    final visibleStart = math.max(0.0, scrollPosition - bufferSize);
    final visibleEnd = scrollPosition + viewportHeight + bufferSize;

    final visibleNoteIds = <String>{};

    final estimatedItemHeight = provider.dataType == DataType.profile ? viewportHeight / 9 : viewportHeight / 7;
    final startIndex = (visibleStart / estimatedItemHeight).floor().clamp(0, notes.length - 1);
    final endIndex = (visibleEnd / estimatedItemHeight).ceil().clamp(startIndex, notes.length - 1);

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

  void _scheduleNavigationStateCleanup() {
    _navigationStateTimer?.cancel();
    _navigationStateTimer = Timer(const Duration(minutes: 10), () {
      final now = DateTime.now().millisecondsSinceEpoch;
      _persistentMediaCache.removeWhere((key, value) {
        final timestamp = value['timestamp'] as int? ?? 0;
        return (now - timestamp) > Duration(minutes: 30).inMilliseconds;
      });

      if (_globalScrollPositions.length > 20) {
        _globalScrollPositions.clear();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _interactionFetchTimer?.cancel();
    _navigationStateTimer?.cancel();

    _persistScrollPosition();
    _persistMediaState();

    _scrollController.dispose();
    _clearCaches();

    _scheduleNavigationStateCleanup();

    super.dispose();
  }

  void _clearCaches() {
    _cachedVisibleNoteIds = null;
    _visibleNoteIds.clear();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Selector<NotesListProvider, ({List<dynamic> notes, bool isLoading, bool isLoadingMore, bool hasError, String? errorMessage})>(
      selector: (_, provider) => (
        notes: provider.notes,
        isLoading: provider.isLoading,
        isLoadingMore: provider.isLoadingMore,
        hasError: provider.hasError,
        errorMessage: provider.errorMessage,
      ),
      builder: (context, data, child) {
        if (data.hasError) {
          return _buildErrorState(data.errorMessage ?? 'Unknown error');
        }

        if (data.notes.isNotEmpty) {
          if (widget.viewMode == NoteViewMode.grid) {
            return const GridViewWidget();
          } else {
            return _buildNotesList(data.notes, data.isLoadingMore);
          }
        }

        return _buildEmptyState();
      },
    );
  }

  Widget _buildEmptyState() {
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
                color: context.colors.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                'No notes available',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try refreshing or check back later',
                style: TextStyle(
                  color: context.colors.textTertiary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
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

    // Add extra item for loading indicator when loading more
    int itemCount = (noteCount * 2) - 1;
    if (isLoadingMore && noteCount > 0) {
      itemCount += 1;
    }

    return SliverList.builder(
      key: const PageStorageKey<String>('notes_list'),
      itemCount: itemCount,
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        // Show loading indicator at the bottom when loading more
        if (isLoadingMore && index == itemCount - 1) {
          return Container(
            padding: const EdgeInsets.all(20),
            alignment: Alignment.center,
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.colors.textSecondary,
              ),
            ),
          );
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
    return Selector<NotesListProvider, ({DataService dataService, String currentUserNpub})>(
      selector: (_, provider) => (
        dataService: provider.dataService,
        currentUserNpub: provider.currentUserNpub,
      ),
      builder: (context, data, child) {
        return NoteWidget(
          note: note,
          dataService: data.dataService,
          currentUserNpub: data.currentUserNpub,
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
