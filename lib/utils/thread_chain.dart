class ThreadChain {
  static List<String> parse(String chain) {
    if (chain.isEmpty) return [];
    final regex = RegExp(r'd(\d+)=([a-f0-9]+)');
    final matches = regex.allMatches(chain);
    final map = <int, String>{};
    for (final match in matches) {
      final index = int.parse(match.group(1)!);
      final noteId = match.group(2)!;
      map[index] = noteId;
    }
    final sortedKeys = map.keys.toList()..sort();
    return sortedKeys.map((k) => map[k]!).toList();
  }

  static String build(List<String> noteIds) {
    if (noteIds.isEmpty) return '';
    return noteIds
        .asMap()
        .entries
        .map((e) => 'd${e.key}=${e.value}')
        .join('-');
  }

  static List<String> buildChainToNote(
    String noteId,
    String rootNoteId,
    Map<String, dynamic>? Function(String) getNote,
  ) {
    final chain = <String>[];
    var currentId = noteId;
    final visited = <String>{};

    while (currentId.isNotEmpty && !visited.contains(currentId)) {
      visited.add(currentId);
      chain.insert(0, currentId);

      if (currentId == rootNoteId) break;

      final note = getNote(currentId);
      if (note == null) break;

      final parentId = note['parentId'] as String?;
      if (parentId != null && parentId.isNotEmpty) {
        currentId = parentId;
      } else {
        final noteRootId = note['rootId'] as String?;
        if (noteRootId != null &&
            noteRootId.isNotEmpty &&
            noteRootId != currentId &&
            !chain.contains(noteRootId)) {
          chain.insert(0, noteRootId);
        }
        break;
      }
    }

    if (chain.isEmpty || chain.first != rootNoteId) {
      chain.insert(0, rootNoteId);
    }

    final seen = <String>{};
    chain.removeWhere((id) => !seen.add(id));

    return chain;
  }
}
