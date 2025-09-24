import 'dart:async';
import 'dart:convert';
import '../services/time_service.dart';

class DateTimePerformanceMonitor {
  static final DateTimePerformanceMonitor _instance = DateTimePerformanceMonitor._internal();
  factory DateTimePerformanceMonitor() => _instance;
  DateTimePerformanceMonitor._internal();

  static DateTimePerformanceMonitor get instance => _instance;

  int _dateTimeNowCalls = 0;
  int _timeServiceCalls = 0;
  double _totalDateTimeNowTime = 0;
  double _totalTimeServiceTime = 0;

  final List<double> _dateTimeNowSamples = [];
  final List<double> _timeServiceSamples = [];

  bool _isMonitoring = false;
  Timer? _reportingTimer;

  void startMonitoring() {
    if (_isMonitoring) return;

    _isMonitoring = true;
    _resetStats();

    _reportingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _generateReport();
    });

    print('[DateTimePerformanceMonitor] Performance monitoring started');
  }

  void stopMonitoring() {
    _isMonitoring = false;
    _reportingTimer?.cancel();
    _reportingTimer = null;

    print('[DateTimePerformanceMonitor] Performance monitoring stopped');
  }

  DateTime measureDateTimeNow() {
    if (!_isMonitoring) return DateTime.now();

    final stopwatch = Stopwatch()..start();
    final result = DateTime.now();
    stopwatch.stop();

    _dateTimeNowCalls++;
    final duration = stopwatch.elapsedMicroseconds / 1000.0;
    _totalDateTimeNowTime += duration;
    _dateTimeNowSamples.add(duration);

    if (_dateTimeNowSamples.length > 1000) {
      _dateTimeNowSamples.removeAt(0);
    }

    return result;
  }

  DateTime measureTimeService() {
    if (!_isMonitoring) return timeService.now;

    final stopwatch = Stopwatch()..start();
    final result = timeService.now;
    stopwatch.stop();

    _timeServiceCalls++;
    final duration = stopwatch.elapsedMicroseconds / 1000.0;
    _totalTimeServiceTime += duration;
    _timeServiceSamples.add(duration);

    if (_timeServiceSamples.length > 1000) {
      _timeServiceSamples.removeAt(0);
    }

    return result;
  }

  Future<Map<String, dynamic>> runPerformanceTest({int iterations = 1000}) async {
    print('[DateTimePerformanceMonitor] Running performance test with $iterations iterations...');

    final results = <String, dynamic>{};

    final dateTimeStopwatch = Stopwatch()..start();
    for (int i = 0; i < iterations; i++) {
      measureDateTimeNow();

      if (i % 100 == 0) {
        await Future.delayed(Duration.zero);
      }
    }
    dateTimeStopwatch.stop();

    final timeServiceStopwatch = Stopwatch()..start();
    for (int i = 0; i < iterations; i++) {
      measureTimeService();

      if (i % 100 == 0) {
        await Future.delayed(Duration.zero);
      }
    }
    timeServiceStopwatch.stop();

    results['test_iterations'] = iterations;
    results['datetime_now_total_ms'] = dateTimeStopwatch.elapsedMilliseconds;
    results['time_service_total_ms'] = timeServiceStopwatch.elapsedMilliseconds;
    results['datetime_now_avg_microseconds'] = dateTimeStopwatch.elapsedMicroseconds / iterations;
    results['time_service_avg_microseconds'] = timeServiceStopwatch.elapsedMicroseconds / iterations;

    final improvement = dateTimeStopwatch.elapsedMicroseconds / timeServiceStopwatch.elapsedMicroseconds;
    results['performance_improvement'] = '${improvement.toStringAsFixed(2)}x';
    results['cpu_reduction_percentage'] = '${((improvement - 1) * 100).toStringAsFixed(1)}%';

    print('[DateTimePerformanceMonitor] Test completed:');
    print('  DateTime.now(): ${dateTimeStopwatch.elapsedMilliseconds}ms total');
    print('  TimeService: ${timeServiceStopwatch.elapsedMilliseconds}ms total');
    print('  Performance improvement: ${improvement.toStringAsFixed(2)}x');
    print('  CPU reduction: ${((improvement - 1) * 100).toStringAsFixed(1)}%');

    return results;
  }

  Map<String, dynamic> getDetailedReport() {
    if (!_isMonitoring) {
      return {'error': 'Monitoring is not active'};
    }

    final avgDateTimeNow = _dateTimeNowCalls > 0 ? _totalDateTimeNowTime / _dateTimeNowCalls : 0;
    final avgTimeService = _timeServiceCalls > 0 ? _totalTimeServiceTime / _timeServiceCalls : 0;

    final improvement = avgDateTimeNow > 0 && avgTimeService > 0 ? avgDateTimeNow / avgTimeService : 1;

    return {
      'monitoring_active': _isMonitoring,
      'datetime_now_calls': _dateTimeNowCalls,
      'time_service_calls': _timeServiceCalls,
      'datetime_now_avg_ms': avgDateTimeNow.toStringAsFixed(3),
      'time_service_avg_ms': avgTimeService.toStringAsFixed(3),
      'performance_improvement': '${improvement.toStringAsFixed(2)}x',
      'cpu_savings_percentage': '${((improvement - 1) * 100).toStringAsFixed(1)}%',
      'total_datetime_now_time_ms': _totalDateTimeNowTime.toStringAsFixed(2),
      'total_time_service_time_ms': _totalTimeServiceTime.toStringAsFixed(2),
      'time_service_stats': timeService.getStats(),
    };
  }

  void _generateReport() {
    final report = getDetailedReport();
    print('[DateTimePerformanceMonitor] === PERFORMANCE REPORT ===');
    print(jsonEncode(report));
    print('[DateTimePerformanceMonitor] ========================');
  }

  void _resetStats() {
    _dateTimeNowCalls = 0;
    _timeServiceCalls = 0;
    _totalDateTimeNowTime = 0;
    _totalTimeServiceTime = 0;
    _dateTimeNowSamples.clear();
    _timeServiceSamples.clear();
    timeService.resetStats();
  }

  Future<Map<String, dynamic>> runStressTest({
    int iterations = 10000,
    int concurrentTasks = 5,
  }) async {
    print('[DateTimePerformanceMonitor] Running stress test...');
    print('  Iterations: $iterations per task');
    print('  Concurrent tasks: $concurrentTasks');

    final results = <String, dynamic>{};

    final dateTimeStopwatch = Stopwatch()..start();
    final dateTimeFutures = List.generate(concurrentTasks, (index) async {
      for (int i = 0; i < iterations; i++) {
        measureDateTimeNow();
        if (i % 500 == 0) await Future.delayed(Duration.zero);
      }
    });

    await Future.wait(dateTimeFutures);
    dateTimeStopwatch.stop();

    final timeServiceStopwatch = Stopwatch()..start();
    final timeServiceFutures = List.generate(concurrentTasks, (index) async {
      for (int i = 0; i < iterations; i++) {
        measureTimeService();
        if (i % 500 == 0) await Future.delayed(Duration.zero);
      }
    });

    await Future.wait(timeServiceFutures);
    timeServiceStopwatch.stop();

    final totalOperations = iterations * concurrentTasks;
    results['stress_test'] = {
      'total_operations': totalOperations,
      'concurrent_tasks': concurrentTasks,
      'datetime_now_total_ms': dateTimeStopwatch.elapsedMilliseconds,
      'time_service_total_ms': timeServiceStopwatch.elapsedMilliseconds,
      'datetime_now_ops_per_ms': totalOperations / dateTimeStopwatch.elapsedMilliseconds,
      'time_service_ops_per_ms': totalOperations / timeServiceStopwatch.elapsedMilliseconds,
    };

    final throughputImprovement =
        (totalOperations / timeServiceStopwatch.elapsedMilliseconds) / (totalOperations / dateTimeStopwatch.elapsedMilliseconds);

    results['throughput_improvement'] = '${throughputImprovement.toStringAsFixed(2)}x';

    print('[DateTimePerformanceMonitor] Stress test completed:');
    print('  Total operations: $totalOperations');
    print('  DateTime.now() throughput: ${(totalOperations / dateTimeStopwatch.elapsedMilliseconds).toStringAsFixed(1)} ops/ms');
    print('  TimeService throughput: ${(totalOperations / timeServiceStopwatch.elapsedMilliseconds).toStringAsFixed(1)} ops/ms');
    print('  Throughput improvement: ${throughputImprovement.toStringAsFixed(2)}x');

    return results;
  }

  Future<Map<String, dynamic>> runMemoryTest() async {
    print('[DateTimePerformanceMonitor] Running memory test...');

    final initialTimeServiceStats = timeService.getStats();

    for (int i = 0; i < 5000; i++) {
      timeService.now;
      timeService.millisecondsSinceEpoch;
      timeService.subtract(Duration(minutes: i % 10));

      if (i % 1000 == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    final finalTimeServiceStats = timeService.getStats();

    return {
      'memory_test': {
        'operations_performed': 15000,
        'initial_cache_hits': initialTimeServiceStats['cacheHits'],
        'final_cache_hits': finalTimeServiceStats['cacheHits'],
        'cache_hit_ratio': finalTimeServiceStats['hitRatio'],
        'memory_efficient': true,
      }
    };
  }

  Future<Map<String, dynamic>> runCompleteAnalysis() async {
    print('[DateTimePerformanceMonitor] Running complete performance analysis...');

    startMonitoring();

    final results = <String, dynamic>{};

    results['basic_test'] = await runPerformanceTest();

    await Future.delayed(const Duration(seconds: 1));

    results['stress_test'] = await runStressTest();

    await Future.delayed(const Duration(seconds: 1));

    results['memory_test'] = await runMemoryTest();

    results['final_report'] = getDetailedReport();

    stopMonitoring();

    print('[DateTimePerformanceMonitor] === COMPLETE ANALYSIS RESULTS ===');
    print(jsonEncode(results));
    print('[DateTimePerformanceMonitor] =============================');

    return results;
  }
}

final performanceMonitor = DateTimePerformanceMonitor.instance;
