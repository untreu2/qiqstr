import 'package:flutter/material.dart';
import '../base/ui_state.dart';
import '../../widgets/common_buttons.dart';

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

  final UIState<T> state;

  final Widget Function(BuildContext context, T data) builder;

  final Widget Function()? loading;

  final Widget Function(String message)? error;

  final Widget Function(String? message)? empty;

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
        return const SizedBox.shrink();
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
        return const SizedBox.shrink();
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
            PrimaryButton(
              label: 'Try Again',
              icon: Icons.refresh,
              onPressed: () {},
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

  final UIState<T> state;

  final Widget Function(BuildContext context, T data) builder;

  final Widget Function()? loading;

  final Widget Function(String message)? error;

  final Widget Function(String? message)? empty;

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

extension UIStateWidgetExtensions<T> on UIState<T> {
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
