import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../core/di/app_di.dart';
import '../data/repositories/note_repository.dart';
import '../data/repositories/user_repository.dart';
import '../data/services/user_batch_fetcher.dart';
import '../presentation/viewmodels/note_visibility_viewmodel.dart';
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

class _NoteListWidgetState extends State<NoteListWidget> {
  late final NoteRepository _noteRepository;
  late final UserRepository _userRepository;
  final Set<String> _loadedInteractionIds = {};
  final Set<String> _visibleNoteIds = {};
  final Set<String> _preloadedUserIds = {};
  StreamSubscription<List<NoteModel>>? _notesStreamSubscription;
  Timer? _updateTimer;
  bool _isScrolling = false;
  DateTime _lastScrollTime = DateTime.now();
  bool _hasPendingUpdate = false;

  @override
  void initState() {
    super.initState();
    try {
      _noteRepository = AppDI.get<NoteRepository>();
      _userRepository = AppDI.get<UserRepository>();
      _preloadUsersForNotes(widget.notes);
      _setupVisibleNotesSubscription();
      
      if (widget.scrollController != null) {
        widget.scrollController!.addListener(_onScrollChanged);
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _updateVisibleNotes();
            _loadInteractionsForVisibleNotes();
          }
        });
      } else {
        if (widget.notes.isNotEmpty) {
          _visibleNoteIds.addAll(
            widget.notes.take(20).map((note) => _getInteractionNoteId(note))
          );
          _loadInteractionsForVisibleNotes();
        }
      }
    } catch (e) {
    }
  }


  void _preloadUsersForNotes(List<NoteModel> notes) {
    if (notes.isEmpty) return;

    final userIdsToLoad = <String>{};
    final currentProfileKeys = Set<String>.from(widget.profiles.keys);
    
    for (final note in notes.take(30)) {
      if (!_preloadedUserIds.contains(note.author) && 
          !currentProfileKeys.contains(note.author)) {
        userIdsToLoad.add(note.author);
      }
      
      if (note.repostedBy != null && 
          !_preloadedUserIds.contains(note.repostedBy!) &&
          !currentProfileKeys.contains(note.repostedBy!)) {
        userIdsToLoad.add(note.repostedBy!);
      }
    }

    if (userIdsToLoad.isEmpty) return;

    _preloadedUserIds.addAll(userIdsToLoad);

    Future.microtask(() async {
      if (!mounted) return;
      
      try {
        final results = await _userRepository.getUserProfiles(
          userIdsToLoad.toList(),
          priority: FetchPriority.high,
        );
        
        if (!mounted) return;

        bool hasNewUsers = false;
        for (final entry in results.entries) {
          entry.value.fold(
            (user) {
              if (!widget.profiles.containsKey(entry.key)) {
                widget.profiles[entry.key] = user;
                hasNewUsers = true;
              }
            },
            (_) {},
          );
        }

        if (mounted && hasNewUsers) {
          setState(() {});
        }
      } catch (e) {
        debugPrint('[NoteListWidget] Error preloading users: $e');
      }
    });
  }

  @override
  void dispose() {
    _notesStreamSubscription?.cancel();
    _updateTimer?.cancel();
    widget.scrollController?.removeListener(_onScrollChanged);
    super.dispose();
  }

  void _setupVisibleNotesSubscription() {
    _notesStreamSubscription = _noteRepository.notesStream.listen((updatedNotes) {
      if (!mounted || _visibleNoteIds.isEmpty || updatedNotes.isEmpty) return;

      bool hasVisibleUpdates = updatedNotes.any(
        (note) => _visibleNoteIds.contains(_getInteractionNoteId(note))
      );

      if (!hasVisibleUpdates) return;

      if (_isScrolling) {
        _hasPendingUpdate = true;
        return;
      }

      _scheduleUpdate();
    });
  }

  void _scheduleUpdate() {
    if (_hasPendingUpdate) {
      _hasPendingUpdate = false;
      _updateTimer?.cancel();
      _updateTimer = Timer(const Duration(milliseconds: 1000), () {
        if (mounted) setState(() {});
      });
    }
  }

  void _onScrollChanged() {
    if (!widget.scrollController!.hasClients || !mounted) return;

    _lastScrollTime = DateTime.now();
    
    if (!_isScrolling) {
      _isScrolling = true;
    }

    _updateTimer?.cancel();
    _updateTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      
      final timeSinceScroll = DateTime.now().difference(_lastScrollTime);
      if (timeSinceScroll.inMilliseconds >= 280) {
        _isScrolling = false;
        _updateVisibleNotes();
        _loadInteractionsForVisibleNotes();
        _scheduleUpdate();
      }
    });
  }

  void _updateVisibleNotes() {
    if (!mounted) return;

    final newVisibleIds = <String>{};

    if (widget.scrollController == null || !widget.scrollController!.hasClients) {
      if (widget.notes.isNotEmpty) {
        newVisibleIds.addAll(
          widget.notes.take(20).map((note) => _getInteractionNoteId(note))
        );
      }
    } else {
      final scrollPosition = widget.scrollController!.position;
      final viewportTop = scrollPosition.pixels;
      final viewportBottom = viewportTop + scrollPosition.viewportDimension;
      final itemHeight = 180.0;
      final buffer = 600.0;

      final startIndex = ((viewportTop - buffer) / itemHeight).floor().clamp(0, widget.notes.length);
      final endIndex = ((viewportBottom + buffer) / itemHeight).ceil().clamp(0, widget.notes.length);

      for (int i = startIndex; i < endIndex && i < widget.notes.length; i++) {
        newVisibleIds.add(_getInteractionNoteId(widget.notes[i]));
      }

      if (viewportTop <= 200) {
        newVisibleIds.addAll(
          widget.notes.take(20).map((note) => _getInteractionNoteId(note))
        );
      }
    }

    if (newVisibleIds.isNotEmpty && 
        (newVisibleIds.length != _visibleNoteIds.length || 
        !newVisibleIds.every(_visibleNoteIds.contains))) {
      _visibleNoteIds.clear();
      _visibleNoteIds.addAll(newVisibleIds);
    }
  }

  String _getInteractionNoteId(NoteModel note) {
    if (note.isRepost && note.rootId != null && note.rootId!.isNotEmpty) {
      return note.rootId!;
    }
    return note.id;
  }

  void _loadInteractionsForVisibleNotes() {
    if (!mounted || widget.notes.isEmpty || _visibleNoteIds.isEmpty) return;

    final noteIdsToLoad = _visibleNoteIds
        .where((noteId) => !_loadedInteractionIds.contains(noteId))
        .take(15)
        .toList();

    if (noteIdsToLoad.isEmpty) return;

    _loadedInteractionIds.addAll(noteIdsToLoad);

    Future.microtask(() {
      if (!mounted) return;
      try {
        _noteRepository.fetchInteractionsForNotes(noteIdsToLoad);
      } catch (e) {
        _loadedInteractionIds.removeAll(noteIdsToLoad);
      }
    });
  }

  @override
  void didUpdateWidget(NoteListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.notes != widget.notes) {
      _preloadUsersForNotes(widget.notes);
    }

    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScrollChanged);
      widget.scrollController?.addListener(_onScrollChanged);
    }

    if (oldWidget.notes.length != widget.notes.length ||
        (widget.notes.isNotEmpty && oldWidget.notes.isNotEmpty && 
         widget.notes.first.id != oldWidget.notes.first.id)) {
      _visibleNoteIds.clear();
      _loadedInteractionIds.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _updateVisibleNotes();
          _loadInteractionsForVisibleNotes();
        }
      });
    } else if (oldWidget.notes != widget.notes) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _updateVisibleNotes();
          _loadInteractionsForVisibleNotes();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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

    return ChangeNotifierProvider(
      create: (_) => NoteVisibilityViewModel(),
      child: SliverList(
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
            key: ValueKey('note_boundary_${note.id}'),
            child: _NoteItemWidget(
              key: ValueKey('note_item_${note.id}'),
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
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: false,
        addSemanticIndexes: false,
      ),
      ),
    );
  }
}

class _NoteItemWidget extends StatefulWidget {
  final NoteModel note;
  final String currentUserNpub;
  final ValueNotifier<List<NoteModel>> notesNotifier;
  final Map<String, UserModel> profiles;
  final dynamic notesListProvider;
  final bool showSeparator;

  const _NoteItemWidget({
    super.key,
    required this.note,
    required this.currentUserNpub,
    required this.notesNotifier,
    required this.profiles,
    this.notesListProvider,
    required this.showSeparator,
  });

  @override
  State<_NoteItemWidget> createState() => _NoteItemWidgetState();
}

class _NoteItemWidgetState extends State<_NoteItemWidget> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        NoteWidget(
          note: widget.note,
          currentUserNpub: widget.currentUserNpub,
          notesNotifier: widget.notesNotifier,
          profiles: widget.profiles,
          containerColor: null,
          isSmallView: true,
          scrollController: null,
          notesListProvider: widget.notesListProvider,
          isVisible: true,
        ),
        if (widget.showSeparator) const _NoteSeparator(),
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
