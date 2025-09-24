import 'dart:developer' as developer;

enum LogLevel {
  debug(0),
  info(1),
  warning(2),
  error(3),
  none(4);

  const LogLevel(this.value);
  final int value;
}

class LoggingService {
  static LoggingService? _instance;
  static LoggingService get instance => _instance ??= LoggingService._();

  LoggingService._();

  LogLevel _currentLevel = LogLevel.error;
  bool _isEnabled = false;

  final Map<String, int> _lastLogTime = {};
  static const int _rateLimitMs = 100;

  void configure({
    LogLevel level = LogLevel.error,
    bool enabled = false,
  }) {
    _currentLevel = level;
    _isEnabled = enabled;
  }

  void debug(String message, [String? tag]) {}

  void info(String message, [String? tag]) {}

  void warning(String message, [String? tag]) {
    if (_isEnabled && _currentLevel.value <= LogLevel.warning.value) {
      _fastLog(message, tag);
    }
  }

  void error(String message, [String? tag, Object? error]) {
    if (_isEnabled && _currentLevel.value <= LogLevel.error.value) {
      final msg = error != null ? '$message: $error' : message;
      _fastLog(msg, tag);
    }
  }

  void _fastLog(String message, String? tag) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = message.hashCode.toString();
    final lastTime = _lastLogTime[key];

    if (lastTime != null && (now - lastTime) < _rateLimitMs) {
      return;
    }
    _lastLogTime[key] = now;

    developer.log(tag != null ? '[$tag] $message' : message, level: 1000);
  }

  void flush() {
    _lastLogTime.clear();
  }

  Map<String, dynamic> getConfig() {
    return {
      'enabled': _isEnabled,
      'level': _currentLevel.name,
    };
  }
}

final loggingService = LoggingService.instance;

void logDebug(String message, [String? tag]) {}
void logInfo(String message, [String? tag]) {}
void logWarning(String message, [String? tag]) => loggingService.warning(message, tag);
void logError(String message, [String? tag, Object? error]) => loggingService.error(message, tag, error);

void optimizedPrint(String message, [String? tag]) {}
