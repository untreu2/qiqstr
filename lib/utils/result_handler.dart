import '../../core/base/result.dart';
import '../../core/base/ui_state.dart';

class ResultHandler {
  static void handleResult<T>(
    Result<T> result, {
    required void Function(T data) onSuccess,
    void Function(String error)? onError,
    void Function(UIState<T>)? onStateUpdate,
  }) {
    result.fold(
      (data) {
        onSuccess(data);
        onStateUpdate?.call(LoadedState(data));
      },
      (error) {
        onError?.call(error);
        onStateUpdate?.call(ErrorState(error));
      },
    );
  }

  static Future<R> handleResultAsync<T, R>(
    Future<Result<T>> futureResult, {
    required R Function(T data) onSuccess,
    required R Function(String error) onError,
  }) async {
    final result = await futureResult;
    return result.fold(onSuccess, onError);
  }

  static void handleResultWithState<T>(
    Result<T> result,
    void Function(UIState<T>) updateState, {
    void Function(T data)? onSuccess,
    void Function(String error)? onError,
  }) {
    result.fold(
      (data) {
        onSuccess?.call(data);
        updateState(LoadedState(data));
      },
      (error) {
        onError?.call(error);
        updateState(ErrorState(error));
      },
    );
  }

  static Future<void> handleResultFuture<T>(
    Future<Result<T>> futureResult, {
    required void Function(T data) onSuccess,
    void Function(String error)? onError,
    void Function(UIState<T>)? onStateUpdate,
  }) async {
    final result = await futureResult;
    handleResult(
      result,
      onSuccess: onSuccess,
      onError: onError,
      onStateUpdate: onStateUpdate,
    );
  }
}

