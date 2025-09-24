const List<String> criticalErrors = [
  'ERROR',
  'CRITICAL',
  'FATAL',
  'Exception',
  'Failed',
  'Connection failed',
  'initialization error',
  'Close error',
];

const List<String> importantStates = [
  'No active connections',
  'offline mode',
  'Unhandled error',
  'Platform error',
];

void safeLog(String message, [String? tag]) {
  final taggedMessage = tag != null ? '[$tag] $message' : message;

  if (criticalErrors.any((error) => message.toLowerCase().contains(error.toLowerCase()))) {
    print(taggedMessage);
    return;
  }

  if (importantStates.any((state) => message.toLowerCase().contains(state.toLowerCase()))) {
    print(taggedMessage);
    return;
  }

  assert(() {
    print(taggedMessage);
    return true;
  }());
}

void debugLog(String message, [String? tag]) {
  assert(() {
    final taggedMessage = tag != null ? '[$tag] $message' : message;
    print(taggedMessage);
    return true;
  }());
}
