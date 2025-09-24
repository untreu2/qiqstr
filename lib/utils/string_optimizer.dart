import 'dart:convert';

class StringOptimizer {
  static StringOptimizer? _instance;
  static StringOptimizer get instance => _instance ??= StringOptimizer._();

  StringOptimizer._();

  static final Map<String, RegExp> _regexpCache = {};

  static final Map<String, dynamic> _jsonCache = {};
  static const int _maxJsonCacheSize = 500;

  static final Map<String, String> _stringPool = {};
  static const int _maxStringPoolSize = 1000;

  static final RegExp _mediaUrlRegExp = RegExp(
    r'(https?:\/\/\S+\.(?:jpg|jpeg|png|webp|gif|mp4|mov))',
    caseSensitive: false,
  );

  static final RegExp _linkRegExp = RegExp(
    r'(https?:\/\/\S+)',
    caseSensitive: false,
  );

  static final RegExp _quoteRegExp = RegExp(
    r'(?:nostr:)?(note1[0-9a-z]+|nevent1[0-9a-z]+)',
    caseSensitive: false,
  );

  static final RegExp _mentionRegExp = RegExp(
    r'nostr:(npub1[0-9a-z]+|nprofile1[0-9a-z]+)',
    caseSensitive: false,
  );

  static final RegExp _hexRegExp = RegExp(r'^[0-9a-fA-F]+$');

  static final RegExp _validPattern = RegExp(r'^[a-zA-Z0-9._-]+$');

  RegExp getCachedRegExp(String pattern, {bool caseSensitive = true}) {
    final key = '$pattern:$caseSensitive';
    return _regexpCache.putIfAbsent(key, () => RegExp(pattern, caseSensitive: caseSensitive));
  }

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

  String internString(String str) {
    if (str.length > 100) return str;

    final cached = _stringPool[str];
    if (cached != null) return cached;

    if (_stringPool.length < _maxStringPoolSize) {
      _stringPool[str] = str;
      return str;
    }

    return str;
  }

  Map<String, dynamic> parseContentOptimized(String content) {
    final mediaMatches = _mediaUrlRegExp.allMatches(content);
    final mediaUrls = mediaMatches.map((m) => m.group(0)!).toList();

    final linkMatches = _linkRegExp.allMatches(content);
    final linkUrls = linkMatches
        .map((m) => m.group(0)!)
        .where((u) => !mediaUrls.contains(u) && !u.toLowerCase().endsWith('.mp4') && !u.toLowerCase().endsWith('.mov'))
        .toList();

    final quoteMatches = _quoteRegExp.allMatches(content);
    final quoteIds = quoteMatches.map((m) => m.group(1)!).toList();

    String cleanedText = content;
    for (final m in [...mediaMatches, ...quoteMatches]) {
      cleanedText = cleanedText.replaceFirst(m.group(0)!, '');
    }
    cleanedText = cleanedText.trim();

    final mentionMatches = _mentionRegExp.allMatches(cleanedText);
    final textParts = <Map<String, dynamic>>[];

    int lastEnd = 0;
    for (final m in mentionMatches) {
      if (m.start > lastEnd) {
        textParts.add({
          'type': 'text',
          'text': cleanedText.substring(lastEnd, m.start),
        });
      }

      textParts.add({
        'type': 'mention',
        'id': m.group(1)!,
      });

      lastEnd = m.end;
    }

    if (lastEnd < cleanedText.length) {
      textParts.add({
        'type': 'text',
        'text': cleanedText.substring(lastEnd),
      });
    }

    return {
      'textParts': textParts,
      'mediaUrls': mediaUrls,
      'linkUrls': linkUrls,
      'quoteIds': quoteIds,
    };
  }

  bool isValidHex(String value) {
    return value.length == 64 && _hexRegExp.hasMatch(value);
  }

  bool isValidUsername(String username) {
    return _validPattern.hasMatch(username);
  }

  String cleanUrl(String url) {
    return url.replaceAll(_getCachedRegExp(r'/+$'), '');
  }

  List<String> splitOptimized(String text, String pattern) {
    if (pattern == '@') {
      return text.split('@');
    }

    return text.split(pattern);
  }

  String substringOptimized(String text, int start, [int? end]) {
    if (start < 0 || start >= text.length) return '';

    final actualEnd = end ?? text.length;
    if (actualEnd <= start || actualEnd > text.length) {
      return text.substring(start);
    }

    return text.substring(start, actualEnd);
  }

  String truncateOptimized(String text, int maxLength, [String suffix = '...']) {
    if (text.length <= maxLength) return text;

    final truncatedLength = maxLength - suffix.length;
    if (truncatedLength <= 0) return suffix;

    return '${text.substring(0, truncatedLength)}$suffix';
  }

  String formatUsername(String username) {
    return username.replaceAll(' ', '_');
  }

  String generateDisplayName(String identifier, {int maxLength = 25}) {
    if (identifier.isEmpty) return 'Anonymous';

    if (identifier.length <= maxLength) return identifier;

    return '${identifier.substring(0, maxLength)}...';
  }

  String formatCount(int count) {
    if (count < 1000) return count.toString();

    if (count < 1000000) {
      final formatted = (count / 1000).toStringAsFixed(1);
      return formatted.endsWith('.0') ? '${formatted.substring(0, formatted.length - 2)}K' : '${formatted}K';
    }

    final formatted = (count / 1000000).toStringAsFixed(1);
    return formatted.endsWith('.0') ? '${formatted.substring(0, formatted.length - 2)}M' : '${formatted}M';
  }

  RegExp _getCachedRegExp(String pattern) {
    return _regexpCache.putIfAbsent(pattern, () => RegExp(pattern));
  }

  void clearCaches() {
    _jsonCache.clear();
    _stringPool.clear();
    _regexpCache.clear();
  }

  Map<String, int> getCacheStats() {
    return {
      'regexpCache': _regexpCache.length,
      'jsonCache': _jsonCache.length,
      'stringPool': _stringPool.length,
    };
  }
}

final stringOptimizer = StringOptimizer.instance;

String optimizedJsonEncode(dynamic object) => stringOptimizer.encodeJsonOptimized(object);
dynamic optimizedJsonDecode(String json) => stringOptimizer.decodeJsonOptimized(json);
String optimizedSubstring(String text, int start, [int? end]) => stringOptimizer.substringOptimized(text, start, end);
String optimizedTruncate(String text, int maxLength, [String suffix = '...']) => stringOptimizer.truncateOptimized(text, maxLength, suffix);
bool isValidHexString(String value) => stringOptimizer.isValidHex(value);
String formatDisplayName(String name, {int maxLength = 25}) => stringOptimizer.generateDisplayName(name, maxLength: maxLength);
String formatCountOptimized(int count) => stringOptimizer.formatCount(count);

extension OptimizedStringOperations on String {
  Map<String, dynamic> parseContentOptimized() {
    return stringOptimizer.parseContentOptimized(this);
  }

  bool get isValidHex => stringOptimizer.isValidHex(this);

  String truncateOptimized(int maxLength, [String suffix = '...']) {
    return stringOptimizer.truncateOptimized(this, maxLength, suffix);
  }

  String get formatUsername => stringOptimizer.formatUsername(this);

  List<String> splitOptimized(String pattern) {
    return stringOptimizer.splitOptimized(this, pattern);
  }
}
