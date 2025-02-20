Map<String, dynamic> parseContent(String content) {
  final RegExp mediaRegExp = RegExp(
    r'(https?:\/\/\S+\.(?:jpg|jpeg|png|webp|gif|mp4|mov))',
    caseSensitive: false,
  );
  final Iterable<RegExpMatch> mediaMatches = mediaRegExp.allMatches(content);
  final List<String> mediaUrls = mediaMatches.map((m) => m.group(0)!).toList();
  final RegExp linkRegExp = RegExp(r'(https?:\/\/\S+)', caseSensitive: false);
  final Iterable<RegExpMatch> linkMatches = linkRegExp.allMatches(content);
  final List<String> linkUrls = linkMatches
      .map((m) => m.group(0)!)
      .where((url) =>
          !mediaUrls.contains(url) &&
          !url.toLowerCase().endsWith('.mp4') &&
          !url.toLowerCase().endsWith('.mov'))
      .toList();
  final String text = content.replaceAll(mediaRegExp, '').trim();
  return {
    'text': text,
    'mediaUrls': mediaUrls,
    'linkUrls': linkUrls,
  };
}
