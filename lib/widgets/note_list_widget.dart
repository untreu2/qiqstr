import 'dart:async';
import 'package:flutter/material.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../core/di/app_di.dart';
import '../data/repositories/note_repository.dart';
import 'note_widget.dart';

class NoteListWidget extends StatefulWidget {
  final List<NoteModel> notes;
  final String? currentUserNpub;
  final ValueNotifier<List<NoteModel>> notesNotifier;
  final Map<String, UserModel> profiles;
  final bool isLoading;
  final bool canLoadMore;
  final VoidCallback? onLoadMore;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final ScrollController? scrollController;
  final dynamic notesListProvider;

  const NoteListWidget({
    super.key,
    required this.notes,
    this.currentUserNpub,
    required this.notesNotifier,
    required this.profiles,
    this.isLoading = false,
    this.canLoadMore = false,
    this.onLoadMore,
    this.errorMessage,
    this.onRetry,
    this.scrollController,
    this.notesListProvider,
  });

  @override
  State<NoteListWidget> createState() => _NoteListWidgetState();
}

class _NoteListWidgetState extends State<NoteListWidget> with AutomaticKeepAliveClientMixin {
  late final NoteRepository _noteRepository;
  final Set<String> _loadedInteractionIds = {};
  final Set<String> _visibleNoteIds = {};
  StreamSubscription<List<NoteModel>>? _notesStreamSubscription;
  Timer? _visibilityCheckTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    try {
      _noteRepository = AppDI.get<NoteRepository>();
      _setupVisibleNotesSubscription();
      
      if (widget.scrollController != null) {
        widget.scrollController!.addListener(_onScrollChanged);
        _visibilityCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _updateVisibleNotes());
        
        // Initial visibility check after first frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateVisibleNotes();
          // Also check after a short delay to ensure scroll controller is ready
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              _updateVisibleNotes();
            }
          });
        });
      } else {
        // If no scroll controller, consider first 15 notes as visible
        if (widget.notes.isNotEmpty) {
          final newVisibleIds = <String>{};
          for (final note in widget.notes.take(15)) {
            final noteId = _getInteractionNoteId(note);
            newVisibleIds.add(noteId);
          }
          _visibleNoteIds.addAll(newVisibleIds);
          _loadInteractionsForVisibleNotes();
        }
      }
    } catch (e) {
      // Handle silently
    }
  }

  @override
  void dispose() {
    _notesStreamSubscription?.cancel();
    _visibilityCheckTimer?.cancel();
    widget.scrollController?.removeListener(_onScrollChanged);
    super.dispose();
  }

  void _setupVisibleNotesSubscription() {
    _notesStreamSubscription = _noteRepository.notesStream.listen((updatedNotes) {
      if (updatedNotes.isEmpty || !mounted || _visibleNoteIds.isEmpty) return;

      // Only process updates for visible notes - trigger rebuild for visible notes only
      bool hasVisibleUpdates = false;
      for (final updatedNote in updatedNotes) {
        final noteId = _getInteractionNoteId(updatedNote);
        
        if (_visibleNoteIds.contains(noteId)) {
          hasVisibleUpdates = true;
          break;
        }
      }

      // Trigger rebuild only if there are updates for visible notes
      // The NoteWidget will read the updated counts from the updated note in the stream
      if (hasVisibleUpdates && mounted) {
        setState(() {});
      }
    });
  }

  void _onScrollChanged() {
    _updateVisibleNotes();
  }

  void _updateVisibleNotes() {
    if (widget.scrollController == null || !widget.scrollController!.hasClients) {
      // If scroll controller not available, consider first 15 notes as visible
      if (widget.notes.isNotEmpty) {
        final newVisibleIds = <String>{};
        for (final note in widget.notes.take(15)) {
          final noteId = _getInteractionNoteId(note);
          newVisibleIds.add(noteId);
        }
        if (newVisibleIds.length != _visibleNoteIds.length || 
            !newVisibleIds.every((id) => _visibleNoteIds.contains(id))) {
          _visibleNoteIds.clear();
          _visibleNoteIds.addAll(newVisibleIds);
          _loadInteractionsForVisibleNotes();
        }
      }
      return;
    }

    final scrollPosition = widget.scrollController!.position;
    final viewportTop = scrollPosition.pixels;
    final viewportBottom = viewportTop + scrollPosition.viewportDimension;

    final newVisibleIds = <String>{};
    final itemHeight = 200.0; // Approximate height per note
    final buffer = 500.0; // Buffer for preloading

    // Always include first 15 notes when at top
    if (viewportTop <= 100) {
      for (final note in widget.notes.take(15)) {
        final noteId = _getInteractionNoteId(note);
        newVisibleIds.add(noteId);
      }
    }

    // Calculate which items are in viewport
    final startIndex = ((viewportTop - buffer) / itemHeight).floor().clamp(0, widget.notes.length);
    final endIndex = ((viewportBottom + buffer) / itemHeight).ceil().clamp(0, widget.notes.length);

    for (int i = startIndex; i < endIndex; i++) {
      if (i >= widget.notes.length) break;
      final note = widget.notes[i];
      final noteId = _getInteractionNoteId(note);
      newVisibleIds.add(noteId);
    }

    if (newVisibleIds.length != _visibleNoteIds.length || 
        !newVisibleIds.every((id) => _visibleNoteIds.contains(id))) {
      _visibleNoteIds.clear();
      _visibleNoteIds.addAll(newVisibleIds);
      _loadInteractionsForVisibleNotes();
    }
  }

  String _getInteractionNoteId(NoteModel note) {
    // For reposts, always use rootId
    if (note.isRepost && note.rootId != null && note.rootId!.isNotEmpty) {
      return note.rootId!;
    }
    return note.id;
  }

  void _loadInteractionsForVisibleNotes() {
    if (widget.notes.isEmpty || _visibleNoteIds.isEmpty) return;

    final noteIdsToLoad = <String>[];
    
    for (final note in widget.notes) {
      final noteId = _getInteractionNoteId(note);
      
      if (_visibleNoteIds.contains(noteId) && !_loadedInteractionIds.contains(noteId)) {
        noteIdsToLoad.add(noteId);
      }
    }

    if (noteIdsToLoad.isEmpty) return;

    _loadedInteractionIds.addAll(noteIdsToLoad);

    Future.microtask(() {
      try {
        _noteRepository.fetchInteractionsForNotes(noteIdsToLoad);
        debugPrint('[NoteListWidget] Fetching interactions for ${noteIdsToLoad.length} visible notes (including reposts)');
      } catch (e) {
        debugPrint('[NoteListWidget] Error fetching interactions: $e');
        _loadedInteractionIds.removeAll(noteIdsToLoad);
      }
    });
  }

  @override
  void didUpdateWidget(NoteListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScrollChanged);
      widget.scrollController?.addListener(_onScrollChanged);
    }

    if (oldWidget.notes.length != widget.notes.length ||
        (widget.notes.isNotEmpty && oldWidget.notes.isNotEmpty && widget.notes.first.id != oldWidget.notes.first.id)) {
      _visibleNoteIds.clear();
      _loadedInteractionIds.clear();
      _updateVisibleNotes();
      _loadInteractionsForVisibleNotes();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.errorMessage != null) {
      return SliverToBoxAdapter(
        child: _ErrorState(
          errorMessage: widget.errorMessage!,
          onRetry: widget.onRetry ?? () {},
        ),
      );
    }

    if (widget.notes.isEmpty && widget.isLoading) {
      return const SliverToBoxAdapter(
        child: _LoadingState(),
      );
    }

    if (widget.notes.isEmpty) {
      return const SliverToBoxAdapter(
        child: _EmptyState(),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == widget.notes.length) {
            if (widget.canLoadMore && widget.onLoadMore != null) {
              return _LoadMoreButton(onPressed: widget.onLoadMore!);
            } else if (widget.isLoading) {
              return const _LoadMoreIndicator();
            }
            return const SizedBox.shrink();
          }

          if (index >= widget.notes.length) {
            return const SizedBox.shrink();
          }

          final note = widget.notes[index];

          return RepaintBoundary(
            key: ValueKey('note_${note.id}'),
            child: _NoteItemWidget(
              note: note,
              currentUserNpub: widget.currentUserNpub ?? '',
              notesNotifier: widget.notesNotifier,
              profiles: widget.profiles,
              notesListProvider: widget.notesListProvider,
              showSeparator: index < widget.notes.length - 1,
            ),
          );
        },
        childCount: widget.notes.length + (widget.canLoadMore || widget.isLoading ? 1 : 0),
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
      ),
    );
  }
}

class _NoteItemWidget extends StatelessWidget {
  final NoteModel note;
  final String currentUserNpub;
  final ValueNotifier<List<NoteModel>> notesNotifier;
  final Map<String, UserModel> profiles;
  final dynamic notesListProvider;
  final bool showSeparator;

  const _NoteItemWidget({
    required this.note,
    required this.currentUserNpub,
    required this.notesNotifier,
    required this.profiles,
    this.notesListProvider,
    required this.showSeparator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        NoteWidget(
          note: note,
          currentUserNpub: currentUserNpub,
          notesNotifier: notesNotifier,
          profiles: profiles,
          containerColor: null,
          isSmallView: true,
          scrollController: null,
          notesListProvider: notesListProvider,
        ),
        if (showSeparator) const _NoteSeparator(),
      ],
    );
  }
}

class _LoadMoreButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _LoadMoreButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
      child: Column(
        children: [
          ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.surface,
              foregroundColor: theme.colorScheme.onSurface,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25.0),
              ),
            ),
            child: const Text(
              'Load more notes',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 200),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
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
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _NoteSeparator extends StatelessWidget {
  const _NoteSeparator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Center(
        child: Container(
          height: 0.5,
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
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

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.article_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'No notes available',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try refreshing or check back later',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
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

    return Center(
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
    );
  }
}
