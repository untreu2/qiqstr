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
    return noteIds.asMap().entries.map((e) => 'd${e.key}=${e.value}').join('-');
  }

  /// Builds a chain string from a hydrated note map.
  ///
  /// Resolves root and parent from stored fields first, then falls back to
  /// parsing raw `e` tags — covering cases where the DB hydration left
  /// rootId/parentId empty (e.g. a repost whose original was not yet cached).
  static String buildFromNote(Map<String, dynamic> note) {
    final noteId = note['id'] as String? ?? '';
    if (noteId.isEmpty) return '';

    var rootId = note['rootId'] as String?;
    var parentId = note['parentId'] as String?;

    if (rootId == null || rootId.isEmpty) {
      final resolved = _resolveFromTags(note);
      rootId = resolved.$1;
      parentId ??= resolved.$2;
    }

    final hasRoot = rootId != null && rootId.isNotEmpty && rootId != noteId;

    final chain = <String>[];
    if (hasRoot) {
      chain.add(rootId);
      if (parentId != null &&
          parentId.isNotEmpty &&
          parentId != rootId &&
          parentId != noteId) {
        chain.add(parentId);
      }
      chain.add(noteId);
    } else {
      chain.add(noteId);
    }

    return build(_deduplicated(chain));
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

      var parentId = note['parentId'] as String?;
      if (parentId == null || parentId.isEmpty) {
        parentId = note['rootId'] as String?;
      }
      if (parentId != null && parentId.isNotEmpty) {
        currentId = parentId;
      } else {
        final resolved = _resolveFromTags(note);
        final tagRoot = resolved.$1;
        if (tagRoot != null &&
            tagRoot.isNotEmpty &&
            tagRoot != currentId &&
            !chain.contains(tagRoot)) {
          chain.insert(0, tagRoot);
        }
        break;
      }
    }

    if (chain.isEmpty || chain.first != rootNoteId) {
      chain.insert(0, rootNoteId);
    }

    return _deduplicated(chain);
  }

  /// Public accessor for resolving root and parent from a note map.
  static (String?, String?) resolveRootAndParentFromNote(
          Map<String, dynamic> note) =>
      _resolveFromTags(note);

  /// Extracts (rootId, parentId) from raw `e` tags of a note map.
  ///
  /// Priority: explicit `root` marker → explicit `reply` marker → positional
  /// (first e-tag = root, last e-tag = parent per deprecated NIP-10 convention).
  static (String?, String?) _resolveFromTags(Map<String, dynamic> note) {
    final tags = note['tags'] as List<dynamic>? ?? [];
    String? rootId;
    String? replyId;
    final allE = <String>[];

    for (final tag in tags) {
      if (tag is! List || tag.length < 2 || tag[0] != 'e') continue;
      final refId = tag[1] as String? ?? '';
      if (refId.isEmpty) continue;
      final marker = tag.length >= 4 ? tag[3] as String? : null;
      switch (marker) {
        case 'root':
          rootId = refId;
        case 'reply':
          replyId = refId;
        case 'mention':
          break;
        default:
          allE.add(refId);
      }
    }

    if (rootId == null && allE.isNotEmpty) {
      rootId = allE.first;
      if (allE.length > 1) replyId = allE.last;
    }

    return (rootId, replyId);
  }

  static List<String> _deduplicated(List<String> ids) {
    final seen = <String>{};
    return ids.where(seen.add).toList();
  }
}
