Map<String, dynamic> parseContent(String content) {
  final RegExp mediaRegExp = RegExp(
    r'(https?:\/\/\S+\.(?:jpg|jpeg|png|webp|gif|mp4|mov))',
    caseSensitive: false,
  );
  final mediaMatches = mediaRegExp.allMatches(content);
  final List<String> mediaUrls = mediaMatches.map((m) => m.group(0)!).toList();

  final RegExp linkRegExp = RegExp(r'(https?:\/\/\S+)', caseSensitive: false);
  final linkMatches = linkRegExp.allMatches(content);
  final List<String> linkUrls = linkMatches
      .map((m) => m.group(0)!)
      .where((u) =>
          !mediaUrls.contains(u) &&
          !u.toLowerCase().endsWith('.mp4') &&
          !u.toLowerCase().endsWith('.mov'))
      .toList();

  final RegExp quoteRegExp =
      RegExp(r'nostr:(note1[0-9a-z]+|nevent1[0-9a-z]+)', caseSensitive: false);
  final quoteMatches = quoteRegExp.allMatches(content);
  final List<String> quoteIds =
      quoteMatches.map((m) => m.group(0)!.replaceFirst('nostr:', '')).toList();

  String cleanedText = content;
  for (final m in [...mediaMatches, ...quoteMatches]) {
    cleanedText = cleanedText.replaceFirst(m.group(0)!, '');
  }
  cleanedText = cleanedText.trim();

  final RegExp mentionRegExp = RegExp(
      r'nostr:(npub1[0-9a-z]+|nprofile1[0-9a-z]+)',
      caseSensitive: false);
  final mentionMatches = mentionRegExp.allMatches(cleanedText);

  final List<Map<String, dynamic>> textParts = [];
  int lastEnd = 0;
  for (final m in mentionMatches) {
    if (m.start > lastEnd) {
      textParts.add({
        'type': 'text',
        'text': cleanedText.substring(lastEnd, m.start),
      });
    }

    final id = m.group(0)!.replaceFirst('nostr:', '');
    textParts.add({'type': 'mention', 'id': id});
    lastEnd = m.end;
  }

  if (lastEnd < cleanedText.length) {
    textParts.add({
      'type': 'text',
      'text': cleanedText.substring(lastEnd),
    });
  }

  return {
    'mediaUrls': mediaUrls,
    'linkUrls': linkUrls,
    'quoteIds': quoteIds,
    'textParts': textParts,
  };
}
