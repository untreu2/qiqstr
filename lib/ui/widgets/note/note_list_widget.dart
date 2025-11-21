import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/note_model.dart';
import '../../../models/user_model.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/user_batch_fetcher.dart';
import '../../../presentation/viewmodels/note_visibility_viewmodel.dart';
import 'note_widget.dart';
import '../common/common_buttons.dart';

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
  DateTime _lastUserFetchTime = DateTime.now();
  bool _hasPendingUpdate = false;
  final Set<String> _fetchedUserIds = {};
  Timer? _setStateDebounceTimer;
  bool _isLoadingMore = false;

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
          _fetchUsersForVisibleNotes();
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
    
    for (final note in notes) {
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

    _userRepository.getUserProfiles(
      userIdsToLoad.toList(),
      priority: FetchPriority.urgent,
    ).then((results) {
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
        _debouncedSetState();
      }
    }).catchError((e) {
      debugPrint('[NoteListWidget] Error preloading users: $e');
    });
  }

  void _debouncedSetState() {
    _setStateDebounceTimer?.cancel();
    _setStateDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _setStateDebounceTimer?.cancel();
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


  void _fetchUsersForVisibleNotes() {
    if (!mounted || widget.scrollController == null || !widget.scrollController!.hasClients) {
      return;
    }

    final now = DateTime.now();
    final timeSinceLastFetch = now.difference(_lastUserFetchTime);
    if (timeSinceLastFetch.inMilliseconds < 100) {
      return;
    }

    try {
      final scrollController = widget.scrollController!;
      final viewportHeight = scrollController.position.viewportDimension;
      final scrollOffset = scrollController.offset;
      
      final estimatedItemHeight = 350.0;
      final startIndex = (scrollOffset / estimatedItemHeight).floor().clamp(0, widget.notes.length - 1);
      final endIndex = ((scrollOffset + viewportHeight) / estimatedItemHeight).ceil().clamp(0, widget.notes.length);
      
      final buffer = 5;
      final bufferedStartIndex = (startIndex - buffer).clamp(0, widget.notes.length - 1);
      final bufferedEndIndex = (endIndex + buffer).clamp(0, widget.notes.length);
      
      final maxVisibleNotes = 20;
      final actualEndIndex = bufferedEndIndex > bufferedStartIndex + maxVisibleNotes 
          ? bufferedStartIndex + maxVisibleNotes 
          : bufferedEndIndex;
      
      if (bufferedStartIndex >= actualEndIndex || bufferedStartIndex >= widget.notes.length) {
        return;
      }
      
      final visibleNotes = widget.notes.sublist(bufferedStartIndex, actualEndIndex.clamp(0, widget.notes.length));
      
      if (visibleNotes.isEmpty) return;
      
      final userIdsToFetch = <String>{};
      final currentProfileKeys = Set<String>.from(widget.profiles.keys);
      
      for (final note in visibleNotes) {
        if (!_fetchedUserIds.contains(note.author) && !currentProfileKeys.contains(note.author)) {
          userIdsToFetch.add(note.author);
          _fetchedUserIds.add(note.author);
        }
        
        if (note.repostedBy != null && 
            !_fetchedUserIds.contains(note.repostedBy!) &&
            !currentProfileKeys.contains(note.repostedBy!)) {
          userIdsToFetch.add(note.repostedBy!);
          _fetchedUserIds.add(note.repostedBy!);
        }
      }
      
      if (userIdsToFetch.isEmpty) return;
      
      _lastUserFetchTime = now;
      
      _userRepository.getUserProfiles(
        userIdsToFetch.toList(),
        priority: FetchPriority.high,
      ).then((results) {
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
          _debouncedSetState();
        }
      }).catchError((e) {
        debugPrint('[NoteListWidget] Error fetching users for visible notes: $e');
      });
      
      if (_fetchedUserIds.length > 200) {
        final cutoff = bufferedStartIndex - 20;
        if (cutoff > 0) {
          for (int i = 0; i < cutoff && i < widget.notes.length; i++) {
            final note = widget.notes[i];
            _fetchedUserIds.remove(note.author);
            if (note.repostedBy != null) {
              _fetchedUserIds.remove(note.repostedBy!);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[NoteListWidget] Error fetching users for visible notes: $e');
    }
  }

  void _scheduleUpdate() {
    if (!_hasPendingUpdate) return;
    
    _hasPendingUpdate = false;
    
    if (!_isScrolling && mounted) {
      _debouncedSetState();
    }
  }

  void _onScrollChanged() {
    if (!widget.scrollController!.hasClients || !mounted) return;

    final now = DateTime.now();
    final timeSinceLastScroll = now.difference(_lastScrollTime).inMilliseconds.abs();
    if (timeSinceLastScroll < 50) {
      return;
    }
    
    _lastScrollTime = now;
    
    if (!_isScrolling) {
      _isScrolling = true;
    }
    
    if (widget.canLoadMore && 
        widget.onLoadMore != null && 
        !_isLoadingMore && 
        !widget.isLoading) {
      final scrollController = widget.scrollController!;
      final position = scrollController.position;
      
      if (position.hasContentDimensions && 
          position.maxScrollExtent != double.infinity) {
        final maxScrollExtent = position.maxScrollExtent;
        final currentScrollPosition = position.pixels;
        final threshold = 200.0; // Load more when 200px from bottom
        
        if (maxScrollExtent - currentScrollPosition < threshold) {
          _isLoadingMore = true;
          widget.onLoadMore!();
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _isLoadingMore = false;
            }
          });
        }
      }
    }
    
    _fetchUsersForVisibleNotes();
    
    _startScrollDebounce();
  }
  
  void _startScrollDebounce() {
    final scrollTime = DateTime.now();
    _lastScrollTime = scrollTime;
    
    Future.microtask(() async {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      
      final timeSinceScroll = DateTime.now().difference(_lastScrollTime);
      if (timeSinceScroll.inMilliseconds >= 280) {
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
    
    _fetchUsersForVisibleNotes();
  }

  void _onNoteBecameVisible(String noteId) {
    if (!mounted) return;
  }


  @override
  void didUpdateWidget(NoteListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.notes != widget.notes) {
      _preloadUsersForNotes(widget.notes);
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fetchUsersForVisibleNotes();
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
        child: Consumer<NoteVisibilityViewModel>(
        builder: (context, visibilityViewModel, _) {
          return _NoteListWithVisibility(
            notes: widget.notes,
            currentUserNpub: widget.currentUserNpub ?? '',
            notesNotifier: widget.notesNotifier,
            profiles: widget.profiles,
            notesListProvider: widget.notesListProvider,
            canLoadMore: widget.canLoadMore,
            isLoading: widget.isLoading,
            visibilityViewModel: visibilityViewModel,
            onNoteVisible: _onNoteBecameVisible,
          );
        },
      ),
    );
  }
}

class _NoteListWithVisibility extends StatelessWidget {
  final List<NoteModel> notes;
  final String currentUserNpub;
  final ValueNotifier<List<NoteModel>> notesNotifier;
  final Map<String, UserModel> profiles;
  final dynamic notesListProvider;
  final bool canLoadMore;
  final bool isLoading;
  final NoteVisibilityViewModel visibilityViewModel;
  final Function(String) onNoteVisible;

  const _NoteListWithVisibility({
    required this.notes,
    required this.currentUserNpub,
    required this.notesNotifier,
    required this.profiles,
    this.notesListProvider,
    required this.canLoadMore,
    required this.isLoading,
    required this.visibilityViewModel,
    required this.onNoteVisible,
  });

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == notes.length) {
            if (isLoading || canLoadMore) {
              return const _LoadMoreIndicator();
            }
            return const SizedBox.shrink();
          }

          if (index >= notes.length) {
            return const SizedBox.shrink();
          }

          final note = notes[index];

          return RepaintBoundary(
            key: ValueKey('note_boundary_${note.id}'),
            child: _NoteItemWidget(
              key: ValueKey('note_item_${note.id}'),
              note: note,
              currentUserNpub: currentUserNpub,
              notesNotifier: notesNotifier,
              profiles: profiles,
              notesListProvider: notesListProvider,
              showSeparator: index < notes.length - 1,
              visibilityViewModel: visibilityViewModel,
              onNoteVisible: onNoteVisible,
            ),
          );
        },
        childCount: notes.length + (canLoadMore || isLoading ? 1 : 0),
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: false,
        addSemanticIndexes: false,
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
  final NoteVisibilityViewModel visibilityViewModel;
  final Function(String) onNoteVisible;

  const _NoteItemWidget({
    super.key,
    required this.note,
    required this.currentUserNpub,
    required this.notesNotifier,
    required this.profiles,
    this.notesListProvider,
    required this.showSeparator,
    required this.visibilityViewModel,
    required this.onNoteVisible,
  });

  @override
  State<_NoteItemWidget> createState() => _NoteItemWidgetState();
}

class _NoteItemWidgetState extends State<_NoteItemWidget> with AutomaticKeepAliveClientMixin {
  final GlobalKey _widgetKey = GlobalKey();
  bool _hasReportedVisibility = false;
  DateTime _lastVisibilityCheck = DateTime(1970);
  static const _visibilityCheckThrottle = Duration(milliseconds: 100);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVisibility();
    });
  }

  void _checkVisibility() {
    if (!mounted) return;
    
    final now = DateTime.now();
    final timeSinceLastCheck = now.difference(_lastVisibilityCheck);
    if (timeSinceLastCheck < _visibilityCheckThrottle && _hasReportedVisibility) {
      return;
    }
    
    _lastVisibilityCheck = now;
    
    final renderObject = _widgetKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.attached && renderObject.hasSize) {
      try {
      final position = renderObject.localToGlobal(Offset.zero);
      final size = renderObject.size;
      final screenHeight = MediaQuery.of(context).size.height;
      final screenWidth = MediaQuery.of(context).size.width;
      
      final isVisible = position.dy < screenHeight && 
                       position.dy + size.height > 0 &&
                       position.dx < screenWidth &&
                       position.dx + size.width > 0;
      
      if (isVisible && !_hasReportedVisibility) {
        _hasReportedVisibility = true;
        final noteId = widget.note.isRepost && widget.note.rootId != null 
            ? widget.note.rootId! 
            : widget.note.id;
        widget.visibilityViewModel.updateVisibility(noteId, true);
        widget.onNoteVisible(noteId);
      } else if (!isVisible && _hasReportedVisibility) {
        _hasReportedVisibility = false;
        final noteId = widget.note.isRepost && widget.note.rootId != null 
            ? widget.note.rootId! 
            : widget.note.id;
        widget.visibilityViewModel.updateVisibility(noteId, false);
        }
      } catch (e) {
        debugPrint('[NoteItemWidget] Error checking visibility: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    if (!_hasReportedVisibility) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkVisibility();
      });
    }
    
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification && !_hasReportedVisibility) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkVisibility();
          });
        }
        return false;
      },
      child: Column(
        key: _widgetKey,
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
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      alignment: Alignment.center,
      constraints: const BoxConstraints(minHeight: 56),
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
            PrimaryButton(
              label: 'Retry',
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
