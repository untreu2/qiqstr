import 'dart:collection';
import 'sync_task.dart';

class SyncQueue {
  final _queue = SplayTreeSet<SyncTask>(_compareTasks);
  final _pendingIds = <String>{};

  static int _compareTasks(SyncTask a, SyncTask b) {
    final priorityCompare = a.priority.index.compareTo(b.priority.index);
    if (priorityCompare != 0) return priorityCompare;
    return a.createdAt.compareTo(b.createdAt);
  }

  void add(SyncTask task) {
    if (_pendingIds.contains(task.id)) return;
    _pendingIds.add(task.id);
    _queue.add(task);
  }

  SyncTask? next() {
    if (_queue.isEmpty) return null;
    final task = _queue.first;
    _queue.remove(task);
    _pendingIds.remove(task.id);
    return task;
  }

  SyncTask? peek() {
    if (_queue.isEmpty) return null;
    return _queue.first;
  }

  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;
  int get length => _queue.length;

  void remove(String taskId) {
    _queue.removeWhere((task) => task.id == taskId);
    _pendingIds.remove(taskId);
  }

  void clear() {
    _queue.clear();
    _pendingIds.clear();
  }

  bool contains(String taskId) => _pendingIds.contains(taskId);

  List<SyncTask> get tasks => _queue.toList();
}
