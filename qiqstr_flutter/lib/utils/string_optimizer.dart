import 'dart:convert';

import '../src/rust/api/database.dart' as rust_db;

class _LruCache<K, V> {
  final int maxSize;
  final Map<K, V> _map = <K, V>{};

  _LruCache(this.maxSize);

  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) {
      _map[key] = value;
    }
    return value;
  }

  void put(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    if (_map.length > maxSize) {
      _map.remove(_map.keys.first);
    }
  }
}

class StringOptimizer {
  static StringOptimizer? _instance;
  static StringOptimizer get instance => _instance ??= StringOptimizer._();

  StringOptimizer._();

  static final Map<String, dynamic> _jsonCache = {};
  static const int _maxJsonCacheSize = 500;

  static final _LruCache<String, Map<String, dynamic>> _parseCache =
      _LruCache<String, Map<String, dynamic>>(300);

  static final RegExp _hexRegExp = RegExp(r'^[0-9a-fA-F]+$');

  dynamic decodeJsonOptimized(String jsonString) {
    if (jsonString.length < 1000) {
      final cached = _jsonCache[jsonString];
      if (cached != null) return cached;

      try {
        final decoded = jsonDecode(jsonString);

        if (_jsonCache.length < _maxJsonCacheSize) {
          _jsonCache[jsonString] = decoded;
        }

        return decoded;
      } catch (e) {
        return null;
      }
    }

    try {
      return jsonDecode(jsonString);
    } catch (e) {
      return null;
    }
  }

  String encodeJsonOptimized(dynamic object) {
    try {
      return jsonEncode(object);
    } catch (e) {
      return '{}';
    }
  }

  Map<String, dynamic> parseContentOptimized(String content) {
    final cached = _parseCache.get(content);
    if (cached != null) {
      return Map<String, dynamic>.from(cached);
    }
    try {
      final json = rust_db.parseNoteContent(content: content);
      final parsed = jsonDecode(json) as Map<String, dynamic>;
      _parseCache.put(content, parsed);
      return Map<String, dynamic>.from(parsed);
    } catch (_) {
      return {
        'textParts': [
          {'type': 'text', 'text': content}
        ],
        'mediaUrls': <String>[],
        'linkUrls': <String>[],
        'quoteIds': <String>[],
        'articleIds': <String>[],
      };
    }
  }

  bool isValidHex(String value) {
    return value.length == 64 && _hexRegExp.hasMatch(value);
  }

  String truncateOptimized(String text, int maxLength,
      [String suffix = '...']) {
    if (text.length <= maxLength) return text;

    final truncatedLength = maxLength - suffix.length;
    if (truncatedLength <= 0) return suffix;

    return '${text.substring(0, truncatedLength)}$suffix';
  }
}

final stringOptimizer = StringOptimizer.instance;

String optimizedJsonEncode(dynamic object) =>
    stringOptimizer.encodeJsonOptimized(object);
dynamic optimizedJsonDecode(String json) =>
    stringOptimizer.decodeJsonOptimized(json);

extension OptimizedStringOperations on String {
  Map<String, dynamic> parseContentOptimized() {
    return stringOptimizer.parseContentOptimized(this);
  }

  bool get isValidHex => stringOptimizer.isValidHex(this);

  String truncateOptimized(int maxLength, [String suffix = '...']) {
    return stringOptimizer.truncateOptimized(this, maxLength, suffix);
  }
}
