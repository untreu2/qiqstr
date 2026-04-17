import 'dart:async';

import 'package:flutter/material.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'note_widget.dart';
import '../common/common_buttons.dart';
import '../common/list_separator_widget.dart';
import '../../../l10n/app_localizations.dart';
import '../../theme/theme_manager.dart';

class NoteListWidget extends StatefulWidget {
  final List<Map<String, dynamic>> notes;
  final String? currentUserHex;
  final ValueNotifier<List<Map<String, dynamic>>> notesNotifier;
  final Map<String, Map<String, dynamic>> profiles;
  final bool isLoading;
  final bool canLoadMore;
  final VoidCallback? onLoadMore;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onEmptyRefresh;
  final ScrollController? scrollController;
  final dynamic notesListProvider;
  final List<Map<String, dynamic>> pinnedNotes;
  final void Function(List<String> noteIds)? onNotesVisible;

  const NoteListWidget({
    super.key,
    required this.notes,
    this.currentUserHex,
    required this.notesNotifier,
    required this.profiles,
    this.isLoading = false,
    this.canLoadMore = false,
    this.onLoadMore,
    this.errorMessage,
    this.onRetry,
    this.onEmptyRefresh,
    this.scrollController,
    this.notesListProvider,
    this.pinnedNotes = const [],
    this.onNotesVisible,
  });

  @override
  State<NoteListWidget> createState() => _NoteListWidgetState();
}

class _NoteListWidgetState extends State<NoteListWidget> {
  bool _hasTriggeredEmptyRefresh = false;
  Timer? _interactionSyncTimer;
  final Set<String> _syncedNoteIds = {};
  bool _isSyncing = false;
  bool _initialSyncDone = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_onScroll);
    _checkAndTriggerEmptyRefresh();
    _scheduleInitialInteractionSync();
  }

  @override
  void didUpdateWidget(NoteListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notes.length != widget.notes.length ||
        oldWidget.isLoading != widget.isLoading) {
      if (widget.notes.isNotEmpty) {
        _hasTriggeredEmptyRefresh = false;
        if (!_initialSyncDone) {
          _scheduleInitialInteractionSync();
        }
      } else {
        _checkAndTriggerEmptyRefresh();
      }
    }
  }

  void _checkAndTriggerEmptyRefresh() {
    if (widget.notes.isEmpty &&
        !widget.isLoading &&
        !_hasTriggeredEmptyRefresh &&
        widget.onEmptyRefresh != null) {
      _hasTriggeredEmptyRefresh = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && widget.notes.isEmpty && !widget.isLoading) {
          widget.onEmptyRefresh?.call();
        }
      });
    }
  }

  @override
  void dispose() {
    _interactionSyncTimer?.cancel();
    widget.scrollController?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    _scheduleInteractionSync();
  }

  void _scheduleInitialInteractionSync() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted || widget.notes.isEmpty || _initialSyncDone) return;
      _initialSyncDone = true;
      _syncVisibleInteractions();
    });
  }

  void _scheduleInteractionSync() {
    _interactionSyncTimer?.cancel();
    _interactionSyncTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _syncVisibleInteractions();
    });
  }

  void _syncVisibleInteractions() {
    if (_isSyncing || widget.notes.isEmpty) return;

    final visibleRange = _getVisibleNoteRange();
    final start = (visibleRange.$1 - 2).clamp(0, widget.notes.length - 1);
    final end = (visibleRange.$2 + 2).clamp(0, widget.notes.length - 1);

    final noteIds = <String>[];
    for (var i = start; i <= end; i++) {
      final noteId = widget.notes[i]['id'] as String? ?? '';
      if (noteId.isNotEmpty && !_syncedNoteIds.contains(noteId)) {
        noteIds.add(noteId);
      }
    }

    if (noteIds.isEmpty) return;

    _isSyncing = true;
    Future.microtask(() async {
      try {
        widget.onNotesVisible?.call(noteIds);
        for (final id in noteIds) {
          _syncedNoteIds.add(id);
        }
        if (_syncedNoteIds.length > 200) {
          final toRemove =
              _syncedNoteIds.take(_syncedNoteIds.length - 200).toList();
          for (final id in toRemove) {
            _syncedNoteIds.remove(id);
          }
        }
      } catch (_) {}
      _isSyncing = false;
    });
  }

  (int, int) _getVisibleNoteRange() {
    final controller = widget.scrollController;
    if (controller == null || !controller.hasClients) {
      return (0, (widget.notes.length - 1).clamp(0, 9));
    }

    final viewportTop = controller.offset;
    final viewportBottom = viewportTop + controller.position.viewportDimension;
    const estimatedNoteHeight = 200.0;

    final firstVisible = (viewportTop / estimatedNoteHeight).floor();
    final lastVisible = (viewportBottom / estimatedNoteHeight).ceil();

    return (
      firstVisible.clamp(0, widget.notes.length - 1),
      lastVisible.clamp(0, widget.notes.length - 1),
    );
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
      _checkAndTriggerEmptyRefresh();
      return const SliverToBoxAdapter(
        child: _LoadingState(),
      );
    }

    return _NoteListContent(
      notes: widget.notes,
      currentUserHex: widget.currentUserHex ?? '',
      notesNotifier: widget.notesNotifier,
      profiles: widget.profiles,
      notesListProvider: widget.notesListProvider,
      canLoadMore: widget.canLoadMore,
      isLoading: widget.isLoading,
      pinnedNotes: widget.pinnedNotes,
      onLoadMore: widget.onLoadMore,
    );
  }
}

class _NoteListContent extends StatelessWidget {
  final List<Map<String, dynamic>> notes;
  final String currentUserHex;
  final ValueNotifier<List<Map<String, dynamic>>> notesNotifier;
  final Map<String, Map<String, dynamic>> profiles;
  final dynamic notesListProvider;
  final bool canLoadMore;
  final bool isLoading;
  final List<Map<String, dynamic>> pinnedNotes;
  final VoidCallback? onLoadMore;

  const _NoteListContent({
    required this.notes,
    required this.currentUserHex,
    required this.notesNotifier,
    required this.profiles,
    this.notesListProvider,
    required this.canLoadMore,
    required this.isLoading,
    this.pinnedNotes = const [],
    this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final pinnedCount = pinnedNotes.length;
    final allCount = pinnedCount + notes.length;
    final showFooter = canLoadMore && onLoadMore != null;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (showFooter && index == allCount) {
            return _LoadMoreTrigger(
              key: ValueKey('load_more_${notes.length}'),
              isLoading: isLoading,
              onLoadMore: onLoadMore!,
            );
          }

          final footerOffset = showFooter ? 1 : 0;
          if (index >= allCount + footerOffset) {
            return SizedBox(
                height: MediaQuery.of(context).padding.bottom + 120);
          }

          final isPinned = index < pinnedCount;
          final note =
              isPinned ? pinnedNotes[index] : notes[index - pinnedCount];
          final noteId = note['id'] as String? ?? '';

          return RepaintBoundary(
            key: ValueKey('${isPinned ? 'pinned' : 'note'}_boundary_$noteId'),
            child: _NoteItemWidget(
              key: ValueKey('${isPinned ? 'pinned' : 'note'}_item_$noteId'),
              note: note,
              currentUserHex: currentUserHex,
              notesNotifier: notesNotifier,
              profiles: profiles,
              notesListProvider: notesListProvider,
              showSeparator: index < allCount - 1,
              isPinned: isPinned,
            ),
          );
        },
        childCount: allCount + (showFooter ? 1 : 0) + 1,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
        addSemanticIndexes: false,
      ),
    );
  }
}

class _LoadMoreTrigger extends StatefulWidget {
  final bool isLoading;
  final VoidCallback onLoadMore;

  const _LoadMoreTrigger({
    super.key,
    required this.isLoading,
    required this.onLoadMore,
  });

  @override
  State<_LoadMoreTrigger> createState() => _LoadMoreTriggerState();
}

class _LoadMoreTriggerState extends State<_LoadMoreTrigger> {
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _triggerIfNeeded();
  }

  @override
  void didUpdateWidget(_LoadMoreTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isLoading && oldWidget.isLoading) {
      _triggered = false;
    }
    _triggerIfNeeded();
  }

  void _triggerIfNeeded() {
    if (!_triggered && !widget.isLoading) {
      _triggered = true;
      Future.microtask(() {
        if (mounted) widget.onLoadMore();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _NoteItemWidget extends StatefulWidget {
  final Map<String, dynamic> note;
  final String currentUserHex;
  final ValueNotifier<List<Map<String, dynamic>>> notesNotifier;
  final Map<String, Map<String, dynamic>> profiles;
  final dynamic notesListProvider;
  final bool showSeparator;
  final bool isPinned;

  const _NoteItemWidget({
    super.key,
    required this.note,
    required this.currentUserHex,
    required this.notesNotifier,
    required this.profiles,
    this.notesListProvider,
    required this.showSeparator,
    this.isPinned = false,
  });

  @override
  State<_NoteItemWidget> createState() => _NoteItemWidgetState();
}

class _NoteItemWidgetState extends State<_NoteItemWidget> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isPinned) _PinnedBadge(),
        NoteWidget(
          note: widget.note,
          currentUserHex: widget.currentUserHex,
          notesNotifier: widget.notesNotifier,
          profiles: widget.profiles,
          containerColor: null,
          isSmallView: true,
          scrollController: null,
          notesListProvider: widget.notesListProvider,
          isVisible: true,
        ),
        if (widget.showSeparator) const ListSeparatorWidget(),
      ],
    );
  }
}

class _PinnedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12),
      child: Row(
        children: [
          Icon(CarbonIcons.pin, size: 16, color: colors.textSecondary),
          const SizedBox(width: 6),
          Text(
            l10n.pinnedNotes,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
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
