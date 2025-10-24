import 'result.dart';

sealed class UIState<T> {
  const UIState();

  const factory UIState.initial() = InitialState<T>;

  const factory UIState.loading([LoadingType type]) = LoadingState<T>;

  const factory UIState.loaded(T data) = LoadedState<T>;

  const factory UIState.error(String message) = ErrorState<T>;

  const factory UIState.empty([String? message]) = EmptyState<T>;

  bool get isInitial => this is InitialState<T>;
  bool get isLoading => this is LoadingState<T>;
  bool get isLoaded => this is LoadedState<T>;
  bool get isError => this is ErrorState<T>;
  bool get isEmpty => this is EmptyState<T>;

  T? get data => switch (this) {
        LoadedState<T>(data: final d) => d,
        _ => null,
      };

  String? get error => switch (this) {
        ErrorState<T>(message: final m) => m,
        _ => null,
      };

  String? get emptyMessage => switch (this) {
        EmptyState<T>(message: final m) => m,
        _ => null,
      };

  LoadingType? get loadingType => switch (this) {
        LoadingState<T>(type: final t) => t,
        _ => null,
      };

  UIState<R> map<R>(R Function(T) mapper) {
    return switch (this) {
      LoadedState<T>(data: final d) => UIState.loaded(mapper(d)),
      InitialState<T>() => const UIState.initial(),
      LoadingState<T>(type: final t) => UIState.loading(t),
      ErrorState<T>(message: final m) => UIState.error(m),
      EmptyState<T>(message: final m) => UIState.empty(m),
    };
  }

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

final class InitialState<T> extends UIState<T> {
  const InitialState();

  @override
  bool operator ==(Object other) => identical(this, other) || other is InitialState<T>;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'InitialState<$T>()';
}

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

enum LoadingType {
  initial,

  refreshing,

  loadingMore,

  backgroundRefresh,
}

extension UIStateExtensions<T> on UIState<T> {
  bool get shouldShowLoading => switch (this) {
        LoadingState<T>(type: LoadingType.initial) => true,
        LoadingState<T>(type: LoadingType.backgroundRefresh) => false,
        LoadingState<T>() => false,
        _ => false,
      };

  bool get shouldShowRefreshIndicator => switch (this) {
        LoadingState<T>(type: LoadingType.refreshing) => true,
        _ => false,
      };

  bool get shouldShowLoadMoreIndicator => switch (this) {
        LoadingState<T>(type: LoadingType.loadingMore) => true,
        _ => false,
      };

  bool get hasData => isLoaded || isEmpty;

  static UIState<T> fromResult<T>(Result<T> result) {
    return result.fold(
      (data) => UIState.loaded(data),
      (error) => UIState.error(error),
    );
  }
}
