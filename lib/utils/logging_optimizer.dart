import 'package:flutter/foundation.dart';

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
    if (kDebugMode) {
      print(taggedMessage);
    }
    return;
  }

  if (importantStates.any((state) => message.toLowerCase().contains(state.toLowerCase()))) {
    if (kDebugMode) {
      print(taggedMessage);
    }
    return;
  }

  assert(() {
    if (kDebugMode) {
      print(taggedMessage);
    }
    return true;
  }());
}

void debugLog(String message, [String? tag]) {
  assert(() {
    final taggedMessage = tag != null ? '[$tag] $message' : message;
    if (kDebugMode) {
      print(taggedMessage);
    }
    return true;
  }());
}
