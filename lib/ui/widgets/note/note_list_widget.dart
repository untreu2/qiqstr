import 'dart:async';

import 'package:flutter/material.dart';
import 'package:carbon_icons/carbon_icons.dart';
import 'note_widget.dart';
import '../common/common_buttons.dart';
import '../common/list_separator_widget.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/interaction_service.dart';
import '../../../core/di/app_di.dart';
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
  });

  @override
  State<NoteListWidget> createState() => _NoteListWidgetState();
}

class _NoteListWidgetState extends State<NoteListWidget> {
  bool _hasTriggeredLoadMore = false;
  bool _hasTriggeredEmptyRefresh = false;
  Timer? _updateTimer;
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
    _updateTimer?.cancel();
    _interactionSyncTimer?.cancel();
    widget.scrollController?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (widget.scrollController == null) return;

    if (!_hasTriggeredLoadMore && widget.canLoadMore && !widget.isLoading) {
      final maxScroll = widget.scrollController!.position.maxScrollExtent;
      final currentScroll = widget.scrollController!.position.pixels;
      final threshold = maxScroll * 0.8;

      if (currentScroll >= threshold) {
        _hasTriggeredLoadMore = true;
        widget.onLoadMore?.call();
        Future.delayed(const Duration(milliseconds: 500), () {
          _hasTriggeredLoadMore = false;
        });
      }
    }

    _scheduleUpdate();
    _scheduleInteractionSync();
  }

  void _scheduleUpdate() {
    _updateTimer?.cancel();
    _updateTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {});
      }
    });
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
    final start = (visibleRange.$1 - 5).clamp(0, widget.notes.length - 1);
    final end =
        (visibleRange.$2 + 5).clamp(0, widget.notes.length - 1);

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
        final syncService = AppDI.get<SyncService>();
        await syncService.syncInteractionsForNotes(noteIds);
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
        InteractionService.instance.refreshAllActive();
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

  const _NoteListContent({
    required this.notes,
    required this.currentUserHex,
    required this.notesNotifier,
    required this.profiles,
    this.notesListProvider,
    required this.canLoadMore,
    required this.isLoading,
    this.pinnedNotes = const [],
  });

  @override
  Widget build(BuildContext context) {
    final pinnedCount = pinnedNotes.length;
    final allCount = pinnedCount + notes.length;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index >= allCount) {
            return SizedBox(
                height: MediaQuery.of(context).padding.bottom + 120);
          }

          final isPinned = index < pinnedCount;
          final note =
              isPinned ? pinnedNotes[index] : notes[index - pinnedCount];
          final noteId = note['id'] as String? ?? '';

          return RepaintBoundary(
            key: ValueKey(
                '${isPinned ? 'pinned' : 'note'}_boundary_$noteId'),
            child: _NoteItemWidget(
              key: ValueKey(
                  '${isPinned ? 'pinned' : 'note'}_item_$noteId'),
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
        childCount: allCount + 1,
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: false,
        addSemanticIndexes: false,
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

class _NoteItemWidgetState extends State<_NoteItemWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

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
