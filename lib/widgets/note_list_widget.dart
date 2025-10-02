import 'package:flutter/material.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import 'note_widget.dart';

class NoteListWidget extends StatelessWidget {
  final List<NoteModel> notes;
  final String? currentUserNpub;
  final ValueNotifier<List<NoteModel>> notesNotifier;
  final Map<String, UserModel> profiles;
  final bool isLoading;
  final bool hasMore;
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
    this.hasMore = false,
    this.onLoadMore,
    this.errorMessage,
    this.onRetry,
    this.scrollController,
    this.notesListProvider,
  });

  @override
  Widget build(BuildContext context) {
    if (errorMessage != null) {
      return SliverToBoxAdapter(
        child: _ErrorState(
          errorMessage: errorMessage!,
          onRetry: onRetry ?? () {},
        ),
      );
    }

    if (notes.isEmpty && isLoading) {
      return const SliverToBoxAdapter(
        child: _LoadingState(),
      );
    }

    if (notes.isEmpty) {
      return const SliverToBoxAdapter(
        child: _EmptyState(),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == notes.length) {
            if (hasMore && onLoadMore != null) {
              return _LoadMoreButton(onPressed: onLoadMore!);
            } else if (isLoading) {
              return const _LoadMoreIndicator();
            }
            return const SizedBox.shrink();
          }

          if (index >= notes.length) {
            return const SizedBox.shrink();
          }

          final note = notes[index];

          return RepaintBoundary(
            key: ValueKey('note_${note.id}'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NoteWidget(
                  note: note,
                  currentUserNpub: currentUserNpub ?? '',
                  notesNotifier: notesNotifier,
                  profiles: profiles,
                  containerColor: null,
                  isSmallView: true,
                  scrollController: scrollController,
                  notesListProvider: notesListProvider,
                ),
                if (index < notes.length - 1) const _NoteSeparator(),
              ],
            ),
          );
        },
        childCount: notes.length + (hasMore || isLoading ? 1 : 0),
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: false,
      ),
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
