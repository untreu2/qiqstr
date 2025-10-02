import 'package:flutter/material.dart';
import '../base/ui_state.dart';

/// Widget that builds UI based on UIState
/// Provides consistent loading, error, and empty state handling
class UIStateBuilder<T> extends StatelessWidget {
  const UIStateBuilder({
    super.key,
    required this.state,
    required this.builder,
    this.loading,
    this.error,
    this.empty,
    this.initial,
  });

  /// The current UIState
  final UIState<T> state;

  /// Builder for loaded state
  final Widget Function(BuildContext context, T data) builder;

  /// Builder for loading state (optional)
  final Widget Function()? loading;

  /// Builder for error state (optional)
  final Widget Function(String message)? error;

  /// Builder for empty state (optional)
  final Widget Function(String? message)? empty;

  /// Builder for initial state (optional)
  final Widget Function()? initial;

  @override
  Widget build(BuildContext context) {
    return state.when<Widget>(
      initial: () => initial?.call() ?? _buildDefaultInitial(context),
      loading: (type) => loading?.call() ?? _buildDefaultLoading(context, type),
      loaded: (data) => builder(context, data),
      error: (message) => error?.call(message) ?? _buildDefaultError(context, message),
      empty: (message) => empty?.call(message) ?? _buildDefaultEmpty(context, message),
    );
  }

  Widget _buildDefaultInitial(BuildContext context) {
    return const Center(
      child: SizedBox.shrink(),
    );
  }

  Widget _buildDefaultLoading(BuildContext context, LoadingType type) {
    switch (type) {
      case LoadingType.initial:
        return const Center(
          child: CircularProgressIndicator(),
        );
      case LoadingType.refreshing:
        return const SizedBox.shrink(); // RefreshIndicator handles this
      case LoadingType.loadingMore:
        return Container(
          padding: const EdgeInsets.all(16),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case LoadingType.backgroundRefresh:
        return const SizedBox.shrink(); // Silent background loading
    }
  }

  Widget _buildDefaultError(BuildContext context, String message) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                // Retry functionality would be handled by parent widget
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultEmpty(BuildContext context, String? message) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message ?? 'No data available',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Sliver version of UIStateBuilder for use in CustomScrollView
class SliverUIStateBuilder<T> extends StatelessWidget {
  const SliverUIStateBuilder({
    super.key,
    required this.state,
    required this.builder,
    this.loading,
    this.error,
    this.empty,
    this.initial,
  });

  /// The current UIState
  final UIState<T> state;

  /// Builder for loaded state
  final Widget Function(BuildContext context, T data) builder;

  /// Builder for loading state (optional)
  final Widget Function()? loading;

  /// Builder for error state (optional)
  final Widget Function(String message)? error;

  /// Builder for empty state (optional)
  final Widget Function(String? message)? empty;

  /// Builder for initial state (optional)
  final Widget Function()? initial;

  @override
  Widget build(BuildContext context) {
    return state.when<Widget>(
      initial: () => SliverFillRemaining(
        child: initial?.call() ?? const SizedBox.shrink(),
      ),
      loading: (type) => SliverFillRemaining(
        child: loading?.call() ?? _buildDefaultLoading(context, type),
      ),
      loaded: (data) => builder(context, data),
      error: (message) => SliverFillRemaining(
        child: error?.call(message) ?? _buildDefaultError(context, message),
      ),
      empty: (message) => SliverFillRemaining(
        child: empty?.call(message) ?? _buildDefaultEmpty(context, message),
      ),
    );
  }

  Widget _buildDefaultLoading(BuildContext context, LoadingType type) {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildDefaultError(BuildContext context, String message) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultEmpty(BuildContext context, String? message) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message ?? 'No data available',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Extension on UIState for easy widget building
extension UIStateWidgetExtensions<T> on UIState<T> {
  /// Convert UIState to widget using UIStateBuilder
  Widget toWidget({
    required Widget Function(BuildContext context, T data) builder,
    Widget Function()? loading,
    Widget Function(String message)? error,
    Widget Function(String? message)? empty,
    Widget Function()? initial,
  }) {
    return Builder(
      builder: (context) => UIStateBuilder<T>(
        state: this,
        builder: builder,
        loading: loading,
        error: error,
        empty: empty,
        initial: initial,
      ),
    );
  }

  /// Convert UIState to sliver widget
  Widget toSliverWidget({
    required Widget Function(BuildContext context, T data) builder,
    Widget Function()? loading,
    Widget Function(String message)? error,
    Widget Function(String? message)? empty,
    Widget Function()? initial,
  }) {
    return Builder(
      builder: (context) => SliverUIStateBuilder<T>(
        state: this,
        builder: builder,
        loading: loading,
        error: error,
        empty: empty,
        initial: initial,
      ),
    );
  }
}
