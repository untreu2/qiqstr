import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_error.dart';

/// Base class for all ViewModels in the application
/// Provides common functionality like error handling, loading states, and lifecycle management
abstract class BaseViewModel extends ChangeNotifier {
  BaseViewModel() {
    initialize();
  }

  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  // Global error state
  AppError? _globalError;
  AppError? get globalError => _globalError;

  // Global loading state
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Subscriptions for cleanup
  final List<StreamSubscription> _subscriptions = [];
  final List<Timer> _timers = [];
  final Map<String, int> _retryAttempts = {};

  /// Called when ViewModel is created
  /// Override this to perform initialization
  @protected
  void initialize() {}

  /// Safely notify listeners only if not disposed
  @protected
  void safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// Set global error state
  @protected
  void setError(AppError error) {
    _globalError = error;
    _isLoading = false;
    safeNotifyListeners();
  }

  /// Clear global error state
  @protected
  void clearError() {
    if (_globalError != null) {
      _globalError = null;
      safeNotifyListeners();
    }
  }

  /// Set global loading state
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

  /// Execute an operation with error handling and loading state
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

      // Clear retry attempts on success
      _retryAttempts.remove(operationName);
    } catch (error) {
      final appError = _convertToAppError(error);
      setError(appError);

      debugPrint('[$runtimeType] Error in $operationName: ${appError.message}');
    } finally {
      if (showLoading) setLoading(false);
    }
  }

  /// Execute operation with retry logic
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

      // Success - clear retry attempts
      _retryAttempts.remove(operationName);
    } catch (error) {
      final appError = _convertToAppError(error);

      if (currentAttempts < maxRetries && appError.isRetryable) {
        // Retry after delay
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
            showLoading: false, // Don't show loading for retries
          );
        });

        return;
      } else {
        // Max retries reached or not retryable
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

  /// Convert any error to AppError
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

  /// Add a subscription for automatic cleanup
  @protected
  void addSubscription(StreamSubscription subscription) {
    if (!_isDisposed) {
      _subscriptions.add(subscription);
    } else {
      subscription.cancel();
    }
  }

  /// Add a timer for automatic cleanup
  @protected
  void addTimer(Timer timer) {
    if (!_isDisposed) {
      _timers.add(timer);
    } else {
      timer.cancel();
    }
  }

  /// Retry the last failed operation
  void retry() {
    if (_globalError != null && _globalError!.isRetryable) {
      clearError();
      onRetry();
    }
  }

  /// Override this to implement retry logic
  @protected
  void onRetry() {}

  @override
  void dispose() {
    _isDisposed = true;

    // Cancel all subscriptions
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    // Cancel all timers
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();

    // Clear retry attempts
    _retryAttempts.clear();

    super.dispose();
  }
}

/// Mixin for ViewModels that need command pattern support
mixin CommandMixin on BaseViewModel {
  final Map<String, Command> _commands = {};

  /// Register a command
  @protected
  void registerCommand(String name, Command command) {
    _commands[name] = command;
  }

  /// Execute a command by name
  Future<void> executeCommand(String name, [dynamic parameter]) async {
    final command = _commands[name];
    if (command != null) {
      await executeOperation(name, () => command.execute(parameter));
    } else {
      throw ArgumentError('Command "$name" not found');
    }
  }

  /// Get command by name
  Command? getCommand(String name) => _commands[name];
}

/// Base class for all commands
abstract class Command {
  /// Execute the command
  Future<void> execute([dynamic parameter]);
}

/// Command that accepts no parameters
abstract class ParameterlessCommand extends Command {
  @override
  Future<void> execute([dynamic parameter]) => executeImpl();

  /// Implement this method in concrete commands
  Future<void> executeImpl();
}

/// Command that accepts a typed parameter
abstract class ParameterizedCommand<T> extends Command {
  @override
  Future<void> execute([dynamic parameter]) {
    if (parameter is T) {
      return executeImpl(parameter);
    } else {
      throw ArgumentError('Expected parameter of type $T, got ${parameter.runtimeType}');
    }
  }

  /// Implement this method in concrete commands
  Future<void> executeImpl(T parameter);
}

/// Simple command implementation
class SimpleCommand extends ParameterlessCommand {
  SimpleCommand(this._action);

  final Future<void> Function() _action;

  @override
  Future<void> executeImpl() => _action();
}

/// Parameterized command implementation
class SimpleParameterizedCommand<T> extends ParameterizedCommand<T> {
  SimpleParameterizedCommand(this._action);

  final Future<void> Function(T) _action;

  @override
  Future<void> executeImpl(T parameter) => _action(parameter);
}
