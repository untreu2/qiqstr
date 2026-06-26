import 'package:flutter/foundation.dart';

import 'logging_service.dart';

typedef CrashReporter = void Function(
  Object error,
  StackTrace? stack, {
  String? context,
  bool fatal,
});

class CrashReportingService {
  static CrashReportingService? _instance;
  static CrashReportingService get instance =>
      _instance ??= CrashReportingService._();

  CrashReportingService._();

  CrashReporter? _reporter;

  void setReporter(CrashReporter? reporter) {
    _reporter = reporter;
  }

  void recordError(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) {
    final tag = context ?? 'Crash';
    if (fatal) {
      logError('Fatal error', tag, error);
    } else {
      logError('Non-fatal error', tag, error);
    }

    final reporter = _reporter;
    if (reporter == null) return;
    try {
      reporter(error, stack, context: context, fatal: fatal);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CrashReportingService] reporter threw: $e');
      }
    }
  }
}

final crashReporting = CrashReportingService.instance;
