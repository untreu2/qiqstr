import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_error.dart';

abstract class BaseViewModel extends ChangeNotifier {
  BaseViewModel() {
    initialize();
  }

  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  AppError? _globalError;
  AppError? get globalError => _globalError;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  final List<StreamSubscription> _subscriptions = [];
  final List<Timer> _timers = [];
  final Map<String, int> _retryAttempts = {};

  @protected
  void initialize() {}

  @protected
  void safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @protected
  void setError(AppError error) {
    _globalError = error;
    _isLoading = false;
    safeNotifyListeners();
  }

  @protected
  void clearError() {
    if (_globalError != null) {
      _globalError = null;
      safeNotifyListeners();
    }
  }

  @protected
  void setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      if (loading) {
        clearError();
      }
      safeNotifyListeners();
    }
  }

  @protected
  Future<void> executeOperation(
    String operationName,
    Future<void> Function() operation, {
    bool showLoading = true,
    bool clearErrorOnStart = true,
  }) async {
    try {
      if (showLoading) setLoading(true);
      if (clearErrorOnStart) clearError();

      await operation();

      _retryAttempts.remove(operationName);
    } catch (error) {
      final appError = _convertToAppError(error);
      setError(appError);

      debugPrint('[$runtimeType] Error in $operationName: ${appError.message}');
    } finally {
      if (showLoading) setLoading(false);
    }
  }

  @protected
  Future<void> executeWithRetry(
    String operationName,
    Future<void> Function() operation, {
    int maxRetries = 3,
    Duration delay = const Duration(milliseconds: 1000),
    bool showLoading = true,
  }) async {
    final currentAttempts = _retryAttempts[operationName] ?? 0;

    try {
      if (showLoading && currentAttempts == 0) setLoading(true);
      if (currentAttempts == 0) clearError();

      await operation();

      _retryAttempts.remove(operationName);
    } catch (error) {
      final appError = _convertToAppError(error);

      if (currentAttempts < maxRetries && appError.isRetryable) {
        _retryAttempts[operationName] = currentAttempts + 1;

        final retryDelay = Duration(
          milliseconds: delay.inMilliseconds * (currentAttempts + 1),
        );

        Timer(retryDelay, () {
          executeWithRetry(
            operationName,
            operation,
            maxRetries: maxRetries,
            delay: delay,
            showLoading: false,
          );
        });

        return;
      } else {
        _retryAttempts.remove(operationName);
        setError(appError);

        debugPrint('[$runtimeType] Error in $operationName after ${currentAttempts + 1} attempts: ${appError.message}');
      }
    } finally {
      if (showLoading && (_retryAttempts[operationName] ?? 0) == 0) {
        setLoading(false);
      }
    }
  }

  AppError _convertToAppError(dynamic error) {
    if (error is AppError) {
      return error;
    } else if (error is Exception) {
      return UnknownError.fromException(error);
    } else {
      return UnknownError(
        message: 'Unknown error: ${error.toString()}',
        userMessage: 'Something unexpected happened. Please try again',
        code: 'UNKNOWN',
      );
    }
  }

  @protected
  void addSubscription(StreamSubscription subscription) {
    if (!_isDisposed) {
      _subscriptions.add(subscription);
    } else {
      subscription.cancel();
    }
  }

  @protected
  void addTimer(Timer timer) {
    if (!_isDisposed) {
      _timers.add(timer);
    } else {
      timer.cancel();
    }
  }

  void retry() {
    if (_globalError != null && _globalError!.isRetryable) {
      clearError();
      onRetry();
    }
  }

  @protected
  void onRetry() {}

  @override
  void dispose() {
    _isDisposed = true;

    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();

    _retryAttempts.clear();

    super.dispose();
  }
}

mixin CommandMixin on BaseViewModel {
  final Map<String, Command> _commands = {};

  @protected
  void registerCommand(String name, Command command) {
    _commands[name] = command;
  }

  Future<void> executeCommand(String name, [dynamic parameter]) async {
    final command = _commands[name];
    if (command != null) {
      await executeOperation(name, () => command.execute(parameter));
    } else {
      throw ArgumentError('Command "$name" not found');
    }
  }

  Command? getCommand(String name) => _commands[name];
}

abstract class Command {
  Future<void> execute([dynamic parameter]);
}

abstract class ParameterlessCommand extends Command {
  @override
  Future<void> execute([dynamic parameter]) => executeImpl();

  Future<void> executeImpl();
}

abstract class ParameterizedCommand<T> extends Command {
  @override
  Future<void> execute([dynamic parameter]) {
    if (parameter is T) {
      return executeImpl(parameter);
    } else {
      throw ArgumentError('Expected parameter of type $T, got ${parameter.runtimeType}');
    }
  }

  Future<void> executeImpl(T parameter);
}

class SimpleCommand extends ParameterlessCommand {
  SimpleCommand(this._action);

  final Future<void> Function() _action;

  @override
  Future<void> executeImpl() => _action();
}

class SimpleParameterizedCommand<T> extends ParameterizedCommand<T> {
  SimpleParameterizedCommand(this._action);

  final Future<void> Function(T) _action;

  @override
  Future<void> executeImpl(T parameter) => _action(parameter);
}
