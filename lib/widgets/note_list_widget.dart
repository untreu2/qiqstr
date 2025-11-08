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
  final Set<String> _preloadedUserIds = {};
  StreamSubscription<List<NoteModel>>? _notesStreamSubscription;
  bool _isScrolling = false;
  DateTime _lastScrollTime = DateTime.now();
  DateTime _lastInteractionFetchTime = DateTime.now();
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
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fetchInteractionsForVisibleNotes();
        }
      });
    } catch (e) {
      debugPrint('[NoteListWidget] Error in initState: $e');
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
    if (widget.scrollController != null) {
      widget.scrollController!.removeListener(_onScrollChanged);
    }
    _notesStreamSubscription?.cancel();
    super.dispose();
  }

  void _setupVisibleNotesSubscription() {
    _notesStreamSubscription = _noteRepository.notesStream.listen((updatedNotes) {
      if (!mounted || updatedNotes.isEmpty) return;

      if (_isScrolling) {
        _hasPendingUpdate = true;
        debugPrint('[NoteListWidget] Update deferred - user scrolling');
        return;
      }

      _scheduleUpdate();
    });
  }

  void _fetchInteractionsForVisibleNotes() {
    if (!mounted || widget.scrollController == null || !widget.scrollController!.hasClients) {
      return;
    }

    final now = DateTime.now();
    final timeSinceLastFetch = now.difference(_lastInteractionFetchTime);
    if (timeSinceLastFetch.inMilliseconds < 800) {
      debugPrint('[NoteListWidget] Skipping fetch - too soon (${timeSinceLastFetch.inMilliseconds}ms)');
      return;
    }

    try {
      final scrollController = widget.scrollController!;
      final viewportHeight = scrollController.position.viewportDimension;
      final scrollOffset = scrollController.offset;
      
      final estimatedItemHeight = 350.0;
      final startIndex = (scrollOffset / estimatedItemHeight).floor().clamp(0, widget.notes.length - 1);
      final endIndex = ((scrollOffset + viewportHeight) / estimatedItemHeight).ceil().clamp(0, widget.notes.length);
      
      final buffer = 1;
      final bufferedStartIndex = (startIndex - buffer).clamp(0, widget.notes.length - 1);
      final bufferedEndIndex = (endIndex + buffer).clamp(0, widget.notes.length);
      
      final maxVisibleNotes = 8;
      final actualEndIndex = bufferedEndIndex > bufferedStartIndex + maxVisibleNotes 
          ? bufferedStartIndex + maxVisibleNotes 
          : bufferedEndIndex;
      
      final visibleNotes = widget.notes.sublist(bufferedStartIndex, actualEndIndex);
      
      if (visibleNotes.isEmpty) return;
      
      final noteIdsToFetch = <String>{};
      for (final note in visibleNotes) {
        if (note.isRepost && note.rootId != null) {
          noteIdsToFetch.add(note.rootId!);
        } else {
          noteIdsToFetch.add(note.id);
        }
      }
      
      _lastInteractionFetchTime = now;
      
      debugPrint('[NoteListWidget] Fetching interactions for ${noteIdsToFetch.length} visible notes (${visibleNotes.length} notes, indices: $bufferedStartIndex-$actualEndIndex, total: ${widget.notes.length})');
      
      _noteRepository.fetchInteractionsForNotes(
        noteIdsToFetch.toList(),
        useCount: false,
        forceLoad: true,
      );
    } catch (e) {
      debugPrint('[NoteListWidget] Error fetching interactions for visible notes: $e');
    }
  }

  void _scheduleUpdate() {
    if (!_hasPendingUpdate) return;
    
    _hasPendingUpdate = false;
    
    if (!_isScrolling && mounted) {
      setState(() {});
    }
  }

  void _onScrollChanged() {
    if (!widget.scrollController!.hasClients || !mounted) return;

    final now = DateTime.now();
    if (_lastScrollTime.difference(now).inMilliseconds.abs() < 100) {
      return;
    }
    
    _lastScrollTime = now;
    
    if (!_isScrolling) {
      _isScrolling = true;
      _startScrollDebounce();
    }
  }
  
  void _startScrollDebounce() {
    final scrollTime = DateTime.now();
    _lastScrollTime = scrollTime;
    
    Future.microtask(() async {
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      
      final timeSinceScroll = DateTime.now().difference(_lastScrollTime);
      if (timeSinceScroll.inMilliseconds >= 780) {
        _onScrollStopped();
      } else {
        _startScrollDebounce();
      }
    });
  }

  void _onScrollStopped() {
    _isScrolling = false;
    
    if (_hasPendingUpdate) {
      _scheduleUpdate();
    }
    
    _fetchInteractionsForVisibleNotes();
  }


  @override
  void didUpdateWidget(NoteListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.notes != widget.notes) {
      _preloadUsersForNotes(widget.notes);
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fetchInteractionsForVisibleNotes();
        }
      });
    }

    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScrollChanged);
      widget.scrollController?.addListener(_onScrollChanged);
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
