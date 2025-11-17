abstract class AppError {
  const AppError({
    required this.message,
    this.userMessage,
    this.code,
    this.isRetryable = true,
  });

  final String message;

  final String? userMessage;

  final String? code;

  final bool isRetryable;

  String get displayMessage => userMessage ?? message;

  @override
  String toString() => 'AppError(message: $message, code: $code)';
}

class NetworkError extends AppError {
  const NetworkError({
    required super.message,
    super.userMessage,
    super.code,
    super.isRetryable = true,
    this.type = NetworkErrorType.unknown,
    this.statusCode,
  });

  final NetworkErrorType type;
  final int? statusCode;

  @override
  String toString() => 'NetworkError(type: $type, message: $message, statusCode: $statusCode)';
}

enum NetworkErrorType {
  noConnection,
  timeout,
  serverError,
  rateLimited,
  unknown,
}

class AuthError extends AppError {
  const AuthError({
    required super.message,
    super.userMessage,
    super.code,
    super.isRetryable = false,
    this.type = AuthErrorType.unknown,
  });

  final AuthErrorType type;

  @override
  String toString() => 'AuthError(type: $type, message: $message)';
}

enum AuthErrorType {
  invalidCredentials,
  notAuthenticated,
  sessionExpired,
  unknown,
}

class ValidationError extends AppError {
  const ValidationError({
    required super.message,
    super.userMessage,
    super.code,
    super.isRetryable = false,
    this.field,
  });

  final String? field;

  @override
  String toString() => 'ValidationError(field: $field, message: $message)';
}

class UnknownError extends AppError {
  const UnknownError({
    required super.message,
    super.userMessage,
    super.code,
    super.isRetryable = true,
  });

  factory UnknownError.fromException(Exception exception) => UnknownError(
        message: 'Unknown error: ${exception.toString()}',
        userMessage: 'Something unexpected happened. Please try again',
        code: 'UNKNOWN',
      );

  @override
  String toString() => 'UnknownError(message: $message)';
}
