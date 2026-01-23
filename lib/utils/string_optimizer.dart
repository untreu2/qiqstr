import 'dart:convert';

class StringOptimizer {
  static StringOptimizer? _instance;
  static StringOptimizer get instance => _instance ??= StringOptimizer._();

  StringOptimizer._();

  static final Map<String, dynamic> _jsonCache = {};
  static const int _maxJsonCacheSize = 500;

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

  static final RegExp _articleRegExp = RegExp(
    r'(?:nostr:)?(naddr1[0-9a-z]+)',
    caseSensitive: false,
  );

  static final RegExp _mentionRegExp = RegExp(
    r'nostr:(npub1[0-9a-z]+|nprofile1[0-9a-z]+)',
    caseSensitive: false,
  );

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
    final mediaMatches = _mediaUrlRegExp.allMatches(content);
    final mediaUrls = mediaMatches.map((m) => m.group(0)!).toList();

    final linkMatches = _linkRegExp.allMatches(content);
    final linkUrls = linkMatches
        .map((m) => m.group(0)!)
        .where((u) => !mediaUrls.contains(u) && !u.toLowerCase().endsWith('.mp4') && !u.toLowerCase().endsWith('.mov'))
        .toList();

    final quoteMatches = _quoteRegExp.allMatches(content);
    final quoteIds = quoteMatches.map((m) => m.group(1)!).toList();

    final articleMatches = _articleRegExp.allMatches(content);
    final articleIds = articleMatches.map((m) => m.group(1)!).toList();

    String cleanedText = content;
    for (final m in [...mediaMatches, ...quoteMatches, ...articleMatches]) {
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
      'articleIds': articleIds,
    };
  }

  bool isValidHex(String value) {
    return value.length == 64 && _hexRegExp.hasMatch(value);
  }

  String truncateOptimized(String text, int maxLength, [String suffix = '...']) {
    if (text.length <= maxLength) return text;

    final truncatedLength = maxLength - suffix.length;
    if (truncatedLength <= 0) return suffix;

    return '${text.substring(0, truncatedLength)}$suffix';
  }

}

final stringOptimizer = StringOptimizer.instance;

String optimizedJsonEncode(dynamic object) => stringOptimizer.encodeJsonOptimized(object);
dynamic optimizedJsonDecode(String json) => stringOptimizer.decodeJsonOptimized(json);

extension OptimizedStringOperations on String {
  Map<String, dynamic> parseContentOptimized() {
    return stringOptimizer.parseContentOptimized(this);
  }

  bool get isValidHex => stringOptimizer.isValidHex(this);

  String truncateOptimized(int maxLength, [String suffix = '...']) {
    return stringOptimizer.truncateOptimized(this, maxLength, suffix);
  }
}
