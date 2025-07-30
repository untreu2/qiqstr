/// Task for data processing in isolates
class DataProcessingTask {
  final String data;
  final String type;
  final DateTime timestamp;
  final int priority;

  DataProcessingTask(
    this.data,
    this.type,
    this.timestamp, {
    this.priority = 1,
  });
}

/// Metrics for cache processing
class CacheMetrics {
  int processedItems = 0;
  int errors = 0;
  Duration totalTime = Duration.zero;
  DateTime lastUpdate = DateTime.now();

  void recordProcessing(int items, Duration time, {bool hasError = false}) {
    processedItems += items;
    totalTime += time;
    if (hasError) errors++;
    lastUpdate = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
        'processedItems': processedItems,
        'errors': errors,
        'totalTimeMs': totalTime.inMilliseconds,
        'lastUpdate': lastUpdate.toIso8601String(),
      };
}

/// Metrics for notes processing
class NotesMetrics {
  int processedNotes = 0;
  int errors = 0;
  Duration totalTime = Duration.zero;
  DateTime lastUpdate = DateTime.now();

  void recordProcessing(int notes, Duration time, {bool hasError = false}) {
    processedNotes += notes;
    totalTime += time;
    if (hasError) errors++;
    lastUpdate = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
        'processedNotes': processedNotes,
        'errors': errors,
        'totalTimeMs': totalTime.inMilliseconds,
        'lastUpdate': lastUpdate.toIso8601String(),
      };
}

/// Configuration for isolate processing
class IsolateConfig {
  final int optimalBatchSize;
  final Duration maxProcessingTime;
  final int maxConcurrentTasks;
  final Duration taskTimeout;

  const IsolateConfig({
    this.optimalBatchSize = 50,
    this.maxProcessingTime = const Duration(seconds: 5),
    this.maxConcurrentTasks = 4,
    this.taskTimeout = const Duration(seconds: 10),
  });
}
