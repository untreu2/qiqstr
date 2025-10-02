List<List<T>> createOptimizedBatches<T>(List<T> items, int batchSize) {
  if (items.isEmpty) return [];

  final batches = <List<T>>[];
  final totalBatches = (items.length / batchSize).ceil();

  for (int i = 0; i < totalBatches; i++) {
    final start = i * batchSize;
    final end = (start + batchSize > items.length) ? items.length : start + batchSize;
    batches.add(items.sublist(start, end));
  }

  return batches;
}

List<R> filterAndMap<T, R>(List<T> items, bool Function(T) filter, R Function(T) mapper) {
  final result = <R>[];
  for (int i = 0; i < items.length; i++) {
    final item = items[i];
    if (filter(item)) {
      result.add(mapper(item));
    }
  }
  return result;
}

T? findFirst<T>(List<T> items, bool Function(T) predicate) {
  for (int i = 0; i < items.length; i++) {
    if (predicate(items[i])) {
      return items[i];
    }
  }
  return null;
}

bool containsWhere<T>(List<T> items, bool Function(T) predicate) {
  for (int i = 0; i < items.length; i++) {
    if (predicate(items[i])) {
      return true;
    }
  }
  return false;
}

Map<K, List<T>> groupByOptimized<T, K>(List<T> items, K Function(T) keySelector) {
  final result = <K, List<T>>{};
  for (int i = 0; i < items.length; i++) {
    final item = items[i];
    final key = keySelector(item);
    (result[key] ??= []).add(item);
  }
  return result;
}

void processInChunks<T>(List<T> items, int chunkSize, void Function(List<T>) processor) {
  for (int i = 0; i < items.length; i += chunkSize) {
    final end = (i + chunkSize > items.length) ? items.length : i + chunkSize;
    processor(items.sublist(i, end));
  }
}

List<T> removeDuplicatesOptimized<T>(List<T> items) {
  if (items.length <= 1) return List.from(items);

  final seen = <T>{};
  final result = <T>[];

  for (int i = 0; i < items.length; i++) {
    final item = items[i];
    if (seen.add(item)) {
      result.add(item);
    }
  }

  return result;
}

List<T> mergeSortedLists<T>(List<T> list1, List<T> list2, int Function(T, T) compare) {
  final result = <T>[];
  int i = 0, j = 0;

  while (i < list1.length && j < list2.length) {
    if (compare(list1[i], list2[j]) <= 0) {
      result.add(list1[i++]);
    } else {
      result.add(list2[j++]);
    }
  }

  while (i < list1.length) {
    result.add(list1[i++]);
  }
  while (j < list2.length) {
    result.add(list2[j++]);
  }

  return result;
}

Map<String, List<T>> categorizeItems<T>(List<T> items, String Function(T) categorizer) {
  final categories = <String, List<T>>{};

  for (int i = 0; i < items.length; i++) {
    final item = items[i];
    final category = categorizer(item);
    (categories[category] ??= []).add(item);
  }

  return categories;
}

extension ListOptimizations<T> on List<T> {
  void forEachIndexed(void Function(int index, T item) action) {
    for (int i = 0; i < length; i++) {
      action(i, this[i]);
    }
  }

  void reverseInPlace() {
    int start = 0;
    int end = length - 1;
    while (start < end) {
      final temp = this[start];
      this[start] = this[end];
      this[end] = temp;
      start++;
      end--;
    }
  }

  (List<T>, List<T>) partitionOptimized(bool Function(T) predicate) {
    final trueList = <T>[];
    final falseList = <T>[];

    for (int i = 0; i < length; i++) {
      if (predicate(this[i])) {
        trueList.add(this[i]);
      } else {
        falseList.add(this[i]);
      }
    }

    return (trueList, falseList);
  }
}
