sealed class Result<T> {
  const Result();

  const factory Result.success(T data) = Success<T>;

  const factory Result.error(String error) = Error<T>;

  bool get isSuccess => this is Success<T>;

  bool get isError => this is Error<T>;

  T? get data => switch (this) {
        Success<T>(data: final d) => d,
        Error<T>() => null,
      };

  String? get error => switch (this) {
        Success<T>() => null,
        Error<T>(error: final e) => e,
      };

  Result<R> map<R>(R Function(T) mapper) {
    return switch (this) {
      Success<T>(data: final d) => Result.success(mapper(d)),
      Error<T>(error: final e) => Result.error(e),
    };
  }

  Result<R> flatMap<R>(Result<R> Function(T) mapper) {
    return switch (this) {
      Success<T>(data: final d) => mapper(d),
      Error<T>(error: final e) => Result.error(e),
    };
  }

  R fold<R>(R Function(T) onSuccess, R Function(String) onError) {
    return switch (this) {
      Success<T>(data: final d) => onSuccess(d),
      Error<T>(error: final e) => onError(e),
    };
  }

  void whenSuccess(void Function(T) onSuccess) {
    if (this case Success<T>(data: final d)) {
      onSuccess(d);
    }
  }

  void whenError(void Function(String) onError) {
    if (this case Error<T>(error: final e)) {
      onError(e);
    }
  }
}

final class Success<T> extends Result<T> {
  const Success(this.data);

  @override
  final T data;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Success<T> && data == other.data;

  @override
  int get hashCode => data.hashCode;

  @override
  String toString() => 'Success($data)';
}

final class Error<T> extends Result<T> {
  const Error(this.error);

  @override
  final String error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Error<T> && error == other.error;

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'Error($error)';
}

extension FutureResultExtensions<T> on Future<Result<T>> {
  Future<Result<R>> mapAsync<R>(Future<R> Function(T) mapper) async {
    final result = await this;
    return switch (result) {
      Success<T>(data: final d) => Result.success(await mapper(d)),
      Error<T>(error: final e) => Result.error(e),
    };
  }

  Future<Result<R>> flatMapAsync<R>(
      Future<Result<R>> Function(T) mapper) async {
    final result = await this;
    return switch (result) {
      Success<T>(data: final d) => await mapper(d),
      Error<T>(error: final e) => Result.error(e),
    };
  }
}
