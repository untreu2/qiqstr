abstract class Logger {
  void debug(String message, [String? tag]);
  void info(String message, [String? tag]);
  void warning(String message, [String? tag]);
  void error(String message, [String? tag, Object? error]);
}

class NoOpLogger implements Logger {
  @override
  void debug(String message, [String? tag]) {}

  @override
  void info(String message, [String? tag]) {}

  @override
  void warning(String message, [String? tag]) {}

  @override
  void error(String message, [String? tag, Object? error]) {}
}

class PrintLogger implements Logger {
  @override
  void debug(String message, [String? tag]) {
    final prefix = tag != null ? '[$tag]' : '';
    // ignore: avoid_print
    print('$prefix $message');
  }

  @override
  void info(String message, [String? tag]) {
    final prefix = tag != null ? '[$tag]' : '';
    // ignore: avoid_print
    print('$prefix $message');
  }

  @override
  void warning(String message, [String? tag]) {
    final prefix = tag != null ? '[$tag]' : '';
    // ignore: avoid_print
    print('WARNING: $prefix $message');
  }

  @override
  void error(String message, [String? tag, Object? error]) {
    final prefix = tag != null ? '[$tag]' : '';
    final errorMsg = error != null ? '$message: $error' : message;
    // ignore: avoid_print
    print('ERROR: $prefix $errorMsg');
  }
}

