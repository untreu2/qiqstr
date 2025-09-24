import 'dart:collection';

class MemoryOptimizer {
  static MemoryOptimizer? _instance;
  static MemoryOptimizer get instance => _instance ??= MemoryOptimizer._();

  MemoryOptimizer._();

  final Queue<List<String>> _stringListPool = Queue<List<String>>();
  final Queue<List<Map<String, dynamic>>> _mapListPool = Queue<List<Map<String, dynamic>>>();
  final Queue<Map<String, dynamic>> _stringMapPool = Queue<Map<String, dynamic>>();
  final Queue<Map<String, String>> _stringStringMapPool = Queue<Map<String, String>>();
  final Queue<Set<String>> _stringSetPool = Queue<Set<String>>();

  static const int _maxPoolSize = 50;

  List<String> getStringList([int? capacity]) {
    if (_stringListPool.isNotEmpty) {
      final list = _stringListPool.removeFirst();
      list.clear();
      return list;
    }
    return capacity != null ? List<String>.empty(growable: true) : <String>[];
  }

  List<Map<String, dynamic>> getMapList([int? capacity]) {
    if (_mapListPool.isNotEmpty) {
      final list = _mapListPool.removeFirst();
      list.clear();
      return list;
    }
    return capacity != null ? List<Map<String, dynamic>>.empty(growable: true) : <Map<String, dynamic>>[];
  }

  Map<String, dynamic> getStringMap() {
    if (_stringMapPool.isNotEmpty) {
      final map = _stringMapPool.removeFirst();
      map.clear();
      return map;
    }
    return <String, dynamic>{};
  }

  Map<String, String> getStringStringMap() {
    if (_stringStringMapPool.isNotEmpty) {
      final map = _stringStringMapPool.removeFirst();
      map.clear();
      return map;
    }
    return <String, String>{};
  }

  Set<String> getStringSet() {
    if (_stringSetPool.isNotEmpty) {
      final set = _stringSetPool.removeFirst();
      set.clear();
      return set;
    }
    return <String>{};
  }

  void returnStringList(List<String> list) {
    if (_stringListPool.length < _maxPoolSize) {
      list.clear();
      _stringListPool.add(list);
    }
  }

  void returnMapList(List<Map<String, dynamic>> list) {
    if (_mapListPool.length < _maxPoolSize) {
      list.clear();
      _mapListPool.add(list);
    }
  }

  void returnStringMap(Map<String, dynamic> map) {
    if (_stringMapPool.length < _maxPoolSize) {
      map.clear();
      _stringMapPool.add(map);
    }
  }

  void returnStringStringMap(Map<String, String> map) {
    if (_stringStringMapPool.length < _maxPoolSize) {
      map.clear();
      _stringStringMapPool.add(map);
    }
  }

  void returnStringSet(Set<String> set) {
    if (_stringSetPool.length < _maxPoolSize) {
      set.clear();
      _stringSetPool.add(set);
    }
  }

  static List<T> preallocatedList<T>(int capacity) {
    return List<T>.filled(capacity, null as T, growable: true)..length = 0;
  }

  static Map<K, V> preallocatedMap<K, V>([int? capacity]) {
    return capacity != null ? Map<K, V>.identity() : <K, V>{};
  }

  static List<T> buildList<T>(int estimatedSize, Iterable<T> source) {
    final list = List<T>.empty(growable: true);
    if (estimatedSize > 0) {
      list.length = 0;
    }
    list.addAll(source);
    return list;
  }

  static List<List<T>> createBatches<T>(List<T> items, int batchSize) {
    if (items.isEmpty) return <List<T>>[];

    final batchCount = (items.length / batchSize).ceil();
    final batches = preallocatedList<List<T>>(batchCount);

    for (int i = 0; i < items.length; i += batchSize) {
      final endIndex = (i + batchSize > items.length) ? items.length : i + batchSize;
      batches.add(items.sublist(i, endIndex));
    }

    return batches;
  }

  static List<T> copyList<T>(List<T> source) {
    return List<T>.from(source, growable: true);
  }

  static Map<K, V> buildMap<K, V>(Iterable<MapEntry<K, V>> entries) {
    final map = <K, V>{};
    for (final entry in entries) {
      map[entry.key] = entry.value;
    }
    return map;
  }

  void clearPools() {
    _stringListPool.clear();
    _mapListPool.clear();
    _stringMapPool.clear();
    _stringStringMapPool.clear();
    _stringSetPool.clear();
  }

  Map<String, int> getMemoryStats() {
    return {
      'stringListPool': _stringListPool.length,
      'mapListPool': _mapListPool.length,
      'stringMapPool': _stringMapPool.length,
      'stringStringMapPool': _stringStringMapPool.length,
      'stringSetPool': _stringSetPool.length,
    };
  }
}

class CollectionBuilders {
  static List<String> buildStringList(int capacity, void Function(List<String>) builder) {
    final list = MemoryOptimizer.preallocatedList<String>(capacity);
    builder(list);
    return list;
  }

  static Map<String, dynamic> buildStringMap(void Function(Map<String, dynamic>) builder) {
    final map = memoryOptimizer.getStringMap();
    builder(map);
    return map;
  }

  static Set<String> buildStringSet(void Function(Set<String>) builder) {
    final set = memoryOptimizer.getStringSet();
    builder(set);
    return set;
  }
}

final memoryOptimizer = MemoryOptimizer.instance;

extension MemoryEfficientList<T> on List<T> {
  void addAllOptimized(Iterable<T> items) {
    final itemsList = items.toList();
    if (itemsList.length > (length * 0.5)) {
      _growToCapacity(length + itemsList.length);
    }
    addAll(itemsList);
  }

  void _growToCapacity(int capacity) {
    if (capacity > length) {
      length = capacity;
      length = length - (capacity - length);
    }
  }
}

extension MemoryEfficientMap<K, V> on Map<K, V> {
  void putAllOptimized(Map<K, V> other) {
    if (other.length < 10) {
      for (final entry in other.entries) {
        this[entry.key] = entry.value;
      }
      return;
    }

    for (final entry in other.entries) {
      this[entry.key] = entry.value;
    }
  }
}
