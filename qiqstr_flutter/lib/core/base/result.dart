import 'app_error.dart';

sealed class Result<T> {
  const Result();

  const factory Result.success(T data) = Success<T>;

  factory Result.error(String message) = Error<T>.fromMessage;

  factory Result.failure(AppError appError) = Error<T>;

  bool get isSuccess => this is Success<T>;

  bool get isError => this is Error<T>;

  T? get data => switch (this) {
        Success<T>(data: final d) => d,
        Error<T>() => null,
      };

  AppError? get appError => switch (this) {
        Success<T>() => null,
        Error<T>(appError: final e) => e,
      };

  String? get error => appError?.message;

  Result<R> map<R>(R Function(T) mapper) {
    return switch (this) {
      Success<T>(data: final d) => Result.success(mapper(d)),
      Error<T>(appError: final e) => Error<R>(e),
    };
  }

  Result<R> flatMap<R>(Result<R> Function(T) mapper) {
    return switch (this) {
      Success<T>(data: final d) => mapper(d),
      Error<T>(appError: final e) => Error<R>(e),
    };
  }

  R fold<R>(R Function(T) onSuccess, R Function(String) onError) {
    return switch (this) {
      Success<T>(data: final d) => onSuccess(d),
      Error<T>(appError: final e) => onError(e.displayMessage),
    };
  }

  R foldError<R>(R Function(T) onSuccess, R Function(AppError) onError) {
    return switch (this) {
      Success<T>(data: final d) => onSuccess(d),
      Error<T>(appError: final e) => onError(e),
    };
  }

  void whenSuccess(void Function(T) onSuccess) {
    if (this case Success<T>(data: final d)) {
      onSuccess(d);
    }
  }

  void whenError(void Function(String) onError) {
    if (this case Error<T>(appError: final e)) {
      onError(e.displayMessage);
    }
  }

  void whenAppError(void Function(AppError) onError) {
    if (this case Error<T>(appError: final e)) {
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
  const Error(this.appError);

  factory Error.fromMessage(String message) =>
      Error(UnknownError(message: message));

  @override
  final AppError appError;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Error<T> && appError.message == other.appError.message;

  @override
  int get hashCode => appError.message.hashCode;

  @override
  String toString() => 'Error(${appError.message})';
}

extension FutureResultExtensions<T> on Future<Result<T>> {
  Future<Result<R>> mapAsync<R>(Future<R> Function(T) mapper) async {
    final result = await this;
    return switch (result) {
      Success<T>(data: final d) => Result.success(await mapper(d)),
      Error<T>(appError: final e) => Error<R>(e),
    };
  }

  Future<Result<R>> flatMapAsync<R>(
      Future<Result<R>> Function(T) mapper) async {
    final result = await this;
    return switch (result) {
      Success<T>(data: final d) => await mapper(d),
      Error<T>(appError: final e) => Error<R>(e),
    };
  }
}
