/// Base class for all application errors
/// Provides a consistent error handling interface
abstract class AppError {
  const AppError({
    required this.message,
    this.userMessage,
    this.code,
    this.isRetryable = true,
  });

  /// Technical error message for debugging
  final String message;

  /// User-friendly message to display in UI
  final String? userMessage;

  /// Error code for programmatic handling
  final String? code;

  /// Whether this error can be retried
  final bool isRetryable;

  /// User-friendly message to display in UI
  String get displayMessage => userMessage ?? message;

  @override
  String toString() => 'AppError(message: $message, code: $code)';
}

/// Network-related errors
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

  factory NetworkError.noConnection() => const NetworkError(
        message: 'No internet connection',
        userMessage: 'Please check your internet connection and try again',
        type: NetworkErrorType.noConnection,
        code: 'NO_CONNECTION',
      );

  factory NetworkError.timeout() => const NetworkError(
        message: 'Request timed out',
        userMessage: 'The request took too long. Please try again',
        type: NetworkErrorType.timeout,
        code: 'TIMEOUT',
      );

  factory NetworkError.serverError(int statusCode) => NetworkError(
        message: 'Server error: $statusCode',
        userMessage: 'Something went wrong on our end. Please try again',
        type: NetworkErrorType.serverError,
        code: 'SERVER_ERROR',
        statusCode: statusCode,
      );

  factory NetworkError.rateLimited() => const NetworkError(
        message: 'Rate limit exceeded',
        userMessage: 'Too many requests. Please wait a moment and try again',
        type: NetworkErrorType.rateLimited,
        code: 'RATE_LIMITED',
        isRetryable: false,
      );

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

/// Authentication-related errors
class AuthError extends AppError {
  const AuthError({
    required super.message,
    super.userMessage,
    super.code,
    super.isRetryable = false,
    this.type = AuthErrorType.unknown,
  });

  final AuthErrorType type;

  factory AuthError.invalidCredentials() => const AuthError(
        message: 'Invalid credentials',
        userMessage: 'Invalid NSEC key. Please check and try again',
        type: AuthErrorType.invalidCredentials,
        code: 'INVALID_CREDENTIALS',
      );

  factory AuthError.notAuthenticated() => const AuthError(
        message: 'User not authenticated',
        userMessage: 'Please log in to continue',
        type: AuthErrorType.notAuthenticated,
        code: 'NOT_AUTHENTICATED',
      );

  factory AuthError.sessionExpired() => const AuthError(
        message: 'Session expired',
        userMessage: 'Your session has expired. Please log in again',
        type: AuthErrorType.sessionExpired,
        code: 'SESSION_EXPIRED',
      );

  @override
  String toString() => 'AuthError(type: $type, message: $message)';
}

enum AuthErrorType {
  invalidCredentials,
  notAuthenticated,
  sessionExpired,
  unknown,
}

/// Validation-related errors
class ValidationError extends AppError {
  const ValidationError({
    required super.message,
    super.userMessage,
    super.code,
    super.isRetryable = false,
    this.field,
  });

  final String? field;

  factory ValidationError.required(String field) => ValidationError(
        message: '$field is required',
        userMessage: '$field cannot be empty',
        code: 'REQUIRED',
        field: field,
      );

  factory ValidationError.invalid(String field, [String? reason]) => ValidationError(
        message: 'Invalid $field${reason != null ? ': $reason' : ''}',
        userMessage: 'Please enter a valid $field',
        code: 'INVALID',
        field: field,
      );

  factory ValidationError.tooShort(String field, int minLength) => ValidationError(
        message: '$field too short, minimum $minLength characters',
        userMessage: '$field must be at least $minLength characters',
        code: 'TOO_SHORT',
        field: field,
      );

  factory ValidationError.tooLong(String field, int maxLength) => ValidationError(
        message: '$field too long, maximum $maxLength characters',
        userMessage: '$field must be no more than $maxLength characters',
        code: 'TOO_LONG',
        field: field,
      );

  @override
  String toString() => 'ValidationError(field: $field, message: $message)';
}

/// Cache-related errors
class CacheError extends AppError {
  const CacheError({
    required super.message,
    super.userMessage,
    super.code,
    super.isRetryable = true,
    this.type = CacheErrorType.unknown,
  });

  final CacheErrorType type;

  factory CacheError.notFound(String key) => CacheError(
        message: 'Cache entry not found: $key',
        userMessage: 'Data not available offline',
        type: CacheErrorType.notFound,
        code: 'CACHE_NOT_FOUND',
      );

  factory CacheError.expired(String key) => CacheError(
        message: 'Cache entry expired: $key',
        userMessage: 'Data is outdated, refreshing...',
        type: CacheErrorType.expired,
        code: 'CACHE_EXPIRED',
      );

  @override
  String toString() => 'CacheError(type: $type, message: $message)';
}

enum CacheErrorType {
  notFound,
  expired,
  storageError,
  unknown,
}

/// Parse/Data format errors
class ParseError extends AppError {
  const ParseError({
    required super.message,
    super.userMessage,
    super.code,
    super.isRetryable = false,
    this.data,
  });

  final dynamic data;

  factory ParseError.invalidFormat(String expectedFormat, [dynamic data]) => ParseError(
        message: 'Invalid format, expected $expectedFormat',
        userMessage: 'Received invalid data format',
        code: 'INVALID_FORMAT',
        data: data,
      );

  factory ParseError.missingField(String field) => ParseError(
        message: 'Missing required field: $field',
        userMessage: 'Incomplete data received',
        code: 'MISSING_FIELD',
      );

  @override
  String toString() => 'ParseError(message: $message, data: $data)';
}

/// Generic unknown error
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
