/// A type that represents either a success value or an error
/// Used for functional error handling throughout the application
sealed class Result<T> {
  const Result();

  /// Creates a successful result containing [data]
  const factory Result.success(T data) = Success<T>;

  /// Creates an error result containing [error]
  const factory Result.error(String error) = Error<T>;

  /// Returns true if this result represents a success
  bool get isSuccess => this is Success<T>;

  /// Returns true if this result represents an error
  bool get isError => this is Error<T>;

  /// Returns the success data or null if this is an error
  T? get data => switch (this) {
        Success<T>(data: final d) => d,
        Error<T>() => null,
      };

  /// Returns the error message or null if this is a success
  String? get error => switch (this) {
        Success<T>() => null,
        Error<T>(error: final e) => e,
      };

  /// Transforms the success value using [mapper] function
  /// Leaves error values unchanged
  Result<R> map<R>(R Function(T) mapper) {
    return switch (this) {
      Success<T>(data: final d) => Result.success(mapper(d)),
      Error<T>(error: final e) => Result.error(e),
    };
  }

  /// Transforms the success value using [mapper] function that returns a Result
  /// Allows for chaining operations that can fail
  Result<R> flatMap<R>(Result<R> Function(T) mapper) {
    return switch (this) {
      Success<T>(data: final d) => mapper(d),
      Error<T>(error: final e) => Result.error(e),
    };
  }

  /// Executes [onSuccess] if this is a success, [onError] if this is an error
  R fold<R>(R Function(T) onSuccess, R Function(String) onError) {
    return switch (this) {
      Success<T>(data: final d) => onSuccess(d),
      Error<T>(error: final e) => onError(e),
    };
  }

  /// Executes [onSuccess] if this is a success (side effect only)
  void whenSuccess(void Function(T) onSuccess) {
    if (this case Success<T>(data: final d)) {
      onSuccess(d);
    }
  }

  /// Executes [onError] if this is an error (side effect only)
  void whenError(void Function(String) onError) {
    if (this case Error<T>(error: final e)) {
      onError(e);
    }
  }
}

/// Represents a successful result containing [data]
final class Success<T> extends Result<T> {
  const Success(this.data);

  @override
  final T data;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Success<T> && data == other.data;

  @override
  int get hashCode => data.hashCode;

  @override
  String toString() => 'Success($data)';
}

/// Represents an error result containing [error] message
final class Error<T> extends Result<T> {
  const Error(this.error);

  @override
  final String error;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Error<T> && error == other.error;

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'Error($error)';
}

extension FutureResultExtensions<T> on Future<Result<T>> {
  /// Maps the success value asynchronously
  Future<Result<R>> mapAsync<R>(Future<R> Function(T) mapper) async {
    final result = await this;
    return switch (result) {
      Success<T>(data: final d) => Result.success(await mapper(d)),
      Error<T>(error: final e) => Result.error(e),
    };
  }

  /// FlatMaps the success value asynchronously
  Future<Result<R>> flatMapAsync<R>(Future<Result<R>> Function(T) mapper) async {
    final result = await this;
    return switch (result) {
      Success<T>(data: final d) => await mapper(d),
      Error<T>(error: final e) => Result.error(e),
    };
  }
}
