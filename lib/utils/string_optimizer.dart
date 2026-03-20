import 'dart:convert';

import '../src/rust/api/database.dart' as rust_db;

class StringOptimizer {
  static StringOptimizer? _instance;
  static StringOptimizer get instance => _instance ??= StringOptimizer._();

  StringOptimizer._();

  static final Map<String, dynamic> _jsonCache = {};
  static const int _maxJsonCacheSize = 500;

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
    try {
      final json = rust_db.parseNoteContent(content: content);
      return jsonDecode(json) as Map<String, dynamic>;
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
