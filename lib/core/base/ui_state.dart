import 'result.dart';

/// Represents the state of UI components with different loading states
/// Used throughout the application for consistent state management
sealed class UIState<T> {
  const UIState();

  /// Initial state - no data loaded yet
  const factory UIState.initial() = InitialState<T>;

  /// Loading state - operation in progress
  const factory UIState.loading([LoadingType type]) = LoadingState<T>;

  /// Success state with data
  const factory UIState.loaded(T data) = LoadedState<T>;

  /// Error state with error message
  const factory UIState.error(String message) = ErrorState<T>;

  /// Empty state with optional message
  const factory UIState.empty([String? message]) = EmptyState<T>;

  /// Convenient getters for state checking
  bool get isInitial => this is InitialState<T>;
  bool get isLoading => this is LoadingState<T>;
  bool get isLoaded => this is LoadedState<T>;
  bool get isError => this is ErrorState<T>;
  bool get isEmpty => this is EmptyState<T>;

  /// Returns the data if loaded, null otherwise
  T? get data => switch (this) {
        LoadedState<T>(data: final d) => d,
        _ => null,
      };

  /// Returns the error message if error state, null otherwise
  String? get error => switch (this) {
        ErrorState<T>(message: final m) => m,
        _ => null,
      };

  /// Returns the empty message if empty state, null otherwise
  String? get emptyMessage => switch (this) {
        EmptyState<T>(message: final m) => m,
        _ => null,
      };

  /// Returns the loading type if loading state, null otherwise
  LoadingType? get loadingType => switch (this) {
        LoadingState<T>(type: final t) => t,
        _ => null,
      };

  /// Maps the data using [mapper] function, preserves other states
  UIState<R> map<R>(R Function(T) mapper) {
    return switch (this) {
      LoadedState<T>(data: final d) => UIState.loaded(mapper(d)),
      InitialState<T>() => const UIState.initial(),
      LoadingState<T>(type: final t) => UIState.loading(t),
      ErrorState<T>(message: final m) => UIState.error(m),
      EmptyState<T>(message: final m) => UIState.empty(m),
    };
  }

  /// Executes appropriate callback based on current state
  R when<R>({
    required R Function() initial,
    required R Function(LoadingType type) loading,
    required R Function(T data) loaded,
    required R Function(String message) error,
    required R Function(String? message) empty,
  }) {
    return switch (this) {
      InitialState<T>() => initial(),
      LoadingState<T>(type: final t) => loading(t),
      LoadedState<T>(data: final d) => loaded(d),
      ErrorState<T>(message: final m) => error(m),
      EmptyState<T>(message: final m) => empty(m),
    };
  }

  /// Executes appropriate callback based on current state (optional callbacks)
  R maybeWhen<R>({
    R Function()? initial,
    R Function(LoadingType type)? loading,
    R Function(T data)? loaded,
    R Function(String message)? error,
    R Function(String? message)? empty,
    required R Function() orElse,
  }) {
    return switch (this) {
      InitialState<T>() => initial?.call() ?? orElse(),
      LoadingState<T>(type: final t) => loading?.call(t) ?? orElse(),
      LoadedState<T>(data: final d) => loaded?.call(d) ?? orElse(),
      ErrorState<T>(message: final m) => error?.call(m) ?? orElse(),
      EmptyState<T>(message: final m) => empty?.call(m) ?? orElse(),
    };
  }
}

/// Initial state - component hasn't started loading data yet
final class InitialState<T> extends UIState<T> {
  const InitialState();

  @override
  bool operator ==(Object other) => identical(this, other) || other is InitialState<T>;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'InitialState<$T>()';
}

/// Loading state - component is currently loading data
final class LoadingState<T> extends UIState<T> {
  const LoadingState([this.type = LoadingType.initial]);

  final LoadingType type;

  @override
  bool operator ==(Object other) => identical(this, other) || other is LoadingState<T> && type == other.type;

  @override
  int get hashCode => type.hashCode;

  @override
  String toString() => 'LoadingState<$T>($type)';
}

/// Successfully loaded state with data
final class LoadedState<T> extends UIState<T> {
  const LoadedState(this.data);

  @override
  final T data;

  @override
  bool operator ==(Object other) => identical(this, other) || other is LoadedState<T> && data == other.data;

  @override
  int get hashCode => data.hashCode;

  @override
  String toString() => 'LoadedState<$T>($data)';
}

/// Error state with error message
final class ErrorState<T> extends UIState<T> {
  const ErrorState(this.message);

  final String message;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ErrorState<T> && message == other.message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'ErrorState<$T>($message)';
}

/// Empty state - data was loaded but collection is empty
final class EmptyState<T> extends UIState<T> {
  const EmptyState([this.message]);

  final String? message;

  @override
  bool operator ==(Object other) => identical(this, other) || other is EmptyState<T> && message == other.message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'EmptyState<$T>($message)';
}

/// Different types of loading states
enum LoadingType {
  /// Initial loading - first time loading data
  initial,

  /// Refreshing - user initiated refresh (pull-to-refresh)
  refreshing,

  /// Loading more - pagination loading more items
  loadingMore,

  /// Background refresh - automatic background updates
  backgroundRefresh,
}

/// Extension methods for UIState
extension UIStateExtensions<T> on UIState<T> {
  /// Returns true if this state should show a loading indicator
  bool get shouldShowLoading => switch (this) {
        LoadingState<T>(type: LoadingType.initial) => true,
        LoadingState<T>(type: LoadingType.backgroundRefresh) => false,
        LoadingState<T>() => false,
        _ => false,
      };

  /// Returns true if this state should show a refresh indicator
  bool get shouldShowRefreshIndicator => switch (this) {
        LoadingState<T>(type: LoadingType.refreshing) => true,
        _ => false,
      };

  /// Returns true if this state should show load more indicator
  bool get shouldShowLoadMoreIndicator => switch (this) {
        LoadingState<T>(type: LoadingType.loadingMore) => true,
        _ => false,
      };

  /// Returns true if this state represents any kind of data (loaded or empty)
  bool get hasData => isLoaded || isEmpty;

  static UIState<T> fromResult<T>(Result<T> result) {
    return result.fold(
      (data) => UIState.loaded(data),
      (error) => UIState.error(error),
    );
  }
}
